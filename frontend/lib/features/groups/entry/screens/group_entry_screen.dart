import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/failure.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/ocr_settings_page.dart' show failureMessage;
import '../entry_repository.dart';
import '../models/verification_form.dart';
import '../widgets/request_status_card.dart';
import 'join_request_screen.dart';

/// The applicant's view of a gated group: what it asks, where their request
/// stands, and what they can do next.
class GroupEntryScreen extends StatefulWidget {
  const GroupEntryScreen({
    super.key,
    required this.repository,
    required this.groupId,
    required this.groupName,
    this.groupDescription,
    this.memberCount = 0,
  });

  final GroupEntryRepository repository;
  final String groupId;
  final String groupName;
  final String? groupDescription;
  final int memberCount;

  @override
  State<GroupEntryScreen> createState() => _GroupEntryScreenState();
}

class _GroupEntryScreenState extends State<GroupEntryScreen> {
  JoinRequest? _request;
  NetworkFailure? _failure;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final request = await widget.repository.myRequest(widget.groupId);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = NetworkFailureClassifier.from(e);
        _loading = false;
      });
    }
  }

  Future<void> _openForm({JoinRequest? amending}) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JoinRequestScreen(
          repository: widget.repository,
          groupId: widget.groupId,
          groupName: widget.groupName,
          existingRequest: amending,
        ),
      ),
    );
    if (submitted == true && mounted) await _load();
  }

  Future<void> _cancel() async {
    final t = L.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.cancelRequestTitle),
            content: Text(t.cancelRequestConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.keepRequest),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: IronColors.semanticError),
                child: Text(t.cancelRequest),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.cancel(widget.groupId);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _request = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(failureMessage(
              L.of(context), NetworkFailureClassifier.from(e))),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(title: Text(widget.groupName)),
      body: _body(t),
    );
  }

  Widget _body(L t) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: IronColors.accentText),
      );
    }
    if (_failure != null) {
      return IronErrorState(
        title: t.requestsLoadFailedTitle,
        message: failureMessage(t, _failure!),
        retryLabel: t.retry,
        onRetry: _load,
      );
    }

    final request = _request;

    return RefreshIndicator(
      onRefresh: _load,
      color: IronColors.accentText,
      backgroundColor: IronColors.surfacePrimary,
      child: ListView(
        padding: const EdgeInsets.all(IronSpacing.md),
        children: [
          _GroupHeader(
            name: widget.groupName,
            description: widget.groupDescription,
            memberCount: widget.memberCount,
          ),
          const SizedBox(height: IronSpacing.lg),

          // Says the group is gated before asking for anything, so the form
          // is expected rather than a surprise.
          Container(
            padding: const EdgeInsets.all(IronSpacing.md),
            decoration: BoxDecoration(
              color: IronColors.surfacePrimary,
              borderRadius: BorderRadius.circular(IronRadius.md),
              border: Border.all(color: IronColors.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(IronIcons.shield,
                    size: IronIcons.sizeInline,
                    color: IronColors.textSecondary),
                const SizedBox(width: IronSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.modeRequestApproval,
                        style: IronTypography.bodyLarge(
                            color: IronColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.groupRequiresApproval,
                        style: IronTypography.bodySmall(
                            color: IronColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: IronSpacing.md),

          if (request == null)
            IronButton(
              label: t.requestToJoin,
              onPressed: _busy ? null : () => _openForm(),
            )
          else
            RequestStatusCard(
              request: request,
              busy: _busy,
              onCancel: request.status == JoinRequestStatus.pending ||
                      request.status == JoinRequestStatus.moreInfoNeeded
                  ? _cancel
                  : null,
              onAmend: request.status.isEditable
                  ? () => _openForm(amending: request)
                  : null,
              // Expired requests may always be resubmitted. A rejected one is
              // not offered here: whether re-applying is allowed is the
              // group's setting, and the server is the authority on it.
              onRequestAgain: request.status == JoinRequestStatus.expired
                  ? () => _openForm()
                  : null,
            ),

          const SizedBox(height: IronSpacing.xl),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.description,
    required this.memberCount,
  });

  final String name;
  final String? description;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: IronColors.surfacePrimary,
            border: Border.all(color: IronColors.borderSubtle),
          ),
          child: Text(
            name.characters.first,
            style: IronTypography.displaySmall(color: IronColors.accentText),
          ),
        ),
        const SizedBox(height: IronSpacing.sm),
        Text(
          name,
          textAlign: TextAlign.center,
          style: IronTypography.headlineLarge(color: IronColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          t.memberCount(memberCount),
          style: IronTypography.bodySmall(color: IronColors.textTertiary),
        ),
        if (description != null && description!.trim().isNotEmpty) ...[
          const SizedBox(height: IronSpacing.sm),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: IronTypography.bodyMedium(color: IronColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
