import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/secure_storage.dart';

import '../../../../core/failure.dart';
import '../../../../core/icons.dart';
import '../../../../core/media_service.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/ocr_settings_page.dart' show failureMessage;
import '../entry_repository.dart';
import '../models/verification_form.dart';
import '../widgets/dynamic_form_field.dart';

/// Fills in the admin's verification form and submits a join request.
///
/// Drafts are held in secure storage rather than plain preferences: the
/// answers here are exactly the sensitive identifiers the form exists to
/// collect (military ID, national ID), and a half-finished form is no less
/// sensitive than a submitted one.
class JoinRequestScreen extends StatefulWidget {
  const JoinRequestScreen({
    super.key,
    required this.repository,
    required this.groupId,
    required this.groupName,
    this.existingRequest,
  });

  final GroupEntryRepository repository;
  final String groupId;
  final String groupName;

  /// Set when amending after the admin asked for more information; the form
  /// opens pre-filled with what was submitted before.
  final JoinRequest? existingRequest;

  @override
  State<JoinRequestScreen> createState() => _JoinRequestScreenState();
}

class _JoinRequestScreenState extends State<JoinRequestScreen> {
  static const _storage = ironSecureStorage;
  static const _draftTtl = Duration(days: 7);

  final Map<String, dynamic> _answers = {};
  final Map<String, String> _errors = {};

  VerificationForm? _form;
  NetworkFailure? _loadFailure;
  bool _loading = true;
  bool _submitting = false;
  bool _restoredDraft = false;

  Timer? _autoSaveTimer;

  String get _draftKey => 'join_draft_${widget.groupId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailure = null;
    });
    try {
      final form = await widget.repository.activeForm(widget.groupId);
      if (!mounted) return;

      // An amendment starts from what was already submitted; a fresh request
      // starts from whatever draft survived the last session.
      if (widget.existingRequest != null) {
        _answers
          ..clear()
          ..addAll(widget.existingRequest!.answers);
      } else {
        await _restoreDraft();
      }

      setState(() {
        _form = form;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadFailure = NetworkFailureClassifier.from(e);
        _loading = false;
      });
    }
  }

  Future<void> _restoreDraft() async {
    final raw = await _storage.read(key: _draftKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['saved_at'] as String? ?? '');
      // Stale drafts are dropped rather than resurfaced: answers from weeks
      // ago are as likely to be wrong as useful.
      if (savedAt == null ||
          DateTime.now().difference(savedAt) > _draftTtl) {
        await _storage.delete(key: _draftKey);
        return;
      }
      final answers = decoded['answers'] as Map<String, dynamic>? ?? {};
      if (answers.isEmpty) return;
      _answers
        ..clear()
        ..addAll(answers);
      _restoredDraft = true;
    } catch (_) {
      // A corrupt draft is discarded silently — there is nothing the user
      // could do about it, and blocking the form on it would be worse.
      await _storage.delete(key: _draftKey);
    }
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (widget.existingRequest != null) return;
    await _storage.write(
      key: _draftKey,
      value: jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'answers': _answers,
      }),
    );
  }

  void _setAnswer(String fieldId, dynamic value) {
    setState(() {
      _answers[fieldId] = value;
      // Clearing the error as soon as the field is touched avoids leaving a
      // red message under something the user has already fixed.
      _errors.remove(fieldId);
    });
    _scheduleAutoSave();
  }

  ({int filled, int total}) get _progress {
    final required = _form?.fields.where((f) => f.isRequired).toList() ?? [];
    final filled = required.where((f) {
      final v = _answers[f.id];
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.isNotEmpty;
      if (v is bool) return v;
      return true;
    }).length;
    return (filled: filled, total: required.length);
  }

  bool get _canSubmit {
    final p = _progress;
    return p.filled == p.total && !_submitting;
  }

  Future<void> _submit() async {
    final form = _form;
    if (form == null) return;

    setState(() {
      _submitting = true;
      _errors.clear();
    });

    try {
      await widget.repository.submit(widget.groupId, answers: _answers);
      await _storage.delete(key: _draftKey);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } on FieldValidationException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _errors
          ..clear()
          ..addAll(e.fieldErrors);
        _submitting = false;
      });
      _scrollToFirstError();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final failure = NetworkFailureClassifier.from(e);
      setState(() => _submitting = false);
      // The draft is deliberately left in place so a failed submit never
      // costs the user their answers.
      _showRetryBanner(failure);
    }
  }

  void _scrollToFirstError() {
    final firstBad = _form?.fields
        .firstWhere(
          (f) => _errors.containsKey(f.id),
          orElse: () => _form!.fields.first,
        )
        .id;
    if (firstBad == null) return;
    final ctx = _fieldKeys[firstBad]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: IronMotion.entrance,
        curve: IronMotion.entranceCurve,
        alignment: 0.2,
      );
    }
  }

  final Map<String, GlobalKey> _fieldKeys = {};

  void _showRetryBanner(NetworkFailure failure) {
    final t = L.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: IronColors.surfaceSecondary,
        content: Text(failureMessage(t, failure)),
        action: SnackBarAction(
          label: t.retry,
          textColor: IronColors.accentText,
          onPressed: _submit,
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final progress = _progress;

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(t.completeVerificationForm),
        bottom: _loading || _form == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: _ProgressStrip(
                  filled: progress.filled,
                  total: progress.total,
                ),
              ),
      ),
      body: _body(t),
      bottomNavigationBar: _loading || _form == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(IronSpacing.md),
                child: IronButton(
                  label: widget.existingRequest != null
                      ? t.resubmit
                      : t.submitRequest,
                  loading: _submitting,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ),
            ),
    );
  }

  Widget _body(L t) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: IronColors.accentText),
      );
    }

    if (_loadFailure != null) {
      return IronErrorState(
        title: t.formLoadFailedTitle,
        message: failureMessage(t, _loadFailure!),
        retryLabel: t.retry,
        onRetry: _load,
      );
    }

    final form = _form;
    // No form means the group asks nothing; submitting is a single tap.
    if (form == null || form.fields.isEmpty) {
      return IronEmptyState(
        title: t.noFormRequired,
        message: t.noFormRequiredHint,
        rings: 1,
        actionLabel: t.submitRequest,
        onAction: _submitting ? null : _submit,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(IronSpacing.md),
      children: [
        Text(
          t.joinRequestFor(widget.groupName),
          style: IronTypography.headlineLarge(color: IronColors.textPrimary),
        ),
        const SizedBox(height: IronSpacing.xxs),
        Text(
          t.completeFormBelow,
          style: IronTypography.bodyMedium(color: IronColors.textSecondary),
        ),

        if (_restoredDraft) ...[
          const SizedBox(height: IronSpacing.sm),
          _Notice(
            icon: IronIcons.info,
            color: IronColors.semanticInfo,
            message: t.draftRestored,
          ),
        ],

        if (widget.existingRequest?.adminNotes != null) ...[
          const SizedBox(height: IronSpacing.sm),
          _Notice(
            icon: IronIcons.info,
            color: IronColors.semanticWarning,
            message: widget.existingRequest!.adminNotes!,
          ),
        ],

        const SizedBox(height: IronSpacing.lg),

        for (final field in form.fields)
          Container(
            key: _fieldKeys.putIfAbsent(field.id, GlobalKey.new),
            child: DynamicFormField(
              field: field,
              value: _answers[field.id],
              errorText: _errors[field.id],
              enabled: !_submitting,
              media: context.read<MediaService>(),
              onChanged: (v) => _setAnswer(field.id, v),
            ),
          ),

        const SizedBox(height: IronSpacing.sm),
        Row(
          children: [
            const Icon(IronIcons.lock,
                size: IronIcons.sizeCompact, color: IronColors.textTertiary),
            const SizedBox(width: IronSpacing.xs),
            Expanded(
              child: Text(
                t.formAnswersEncrypted,
                style: IronTypography.bodySmall(color: IronColors.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: IronSpacing.xl),
      ],
    );
  }
}

/// Progress across required fields only.
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final ratio = total == 0 ? 1.0 : filled / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          IronSpacing.md, 0, IronSpacing.md, IronSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: IronColors.surfaceSecondary,
              valueColor: const AlwaysStoppedAnimation(IronColors.accentText),
            ),
          ),
          const SizedBox(height: IronSpacing.xxs),
          Text(
            t.requiredFieldsProgress(filled, total),
            style: IronTypography.labelSmall(color: IronColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IronSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: IronIcons.sizeCompact, color: color),
          const SizedBox(width: IronSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: IronTypography.bodySmall(color: IronColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
