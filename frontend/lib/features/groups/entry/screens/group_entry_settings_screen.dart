import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/failure.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/ocr_settings_page.dart' show failureMessage;
import '../entry_repository.dart';
import '../models/verification_form.dart';
import 'audit_log_screen.dart';
import 'form_builder_screen.dart';

/// How a group admits people, and what it asks of applicants.
///
/// Settings are applied on save rather than per-toggle: switching a group
/// from open to approval-required mid-edit, before the admin has attached a
/// form, would leave it briefly gated by nothing.
class GroupEntrySettingsScreen extends StatefulWidget {
  const GroupEntrySettingsScreen({
    super.key,
    required this.repository,
    required this.groupId,
    required this.groupName,
  });

  final GroupEntryRepository repository;
  final String groupId;
  final String groupName;

  @override
  State<GroupEntrySettingsScreen> createState() =>
      _GroupEntrySettingsScreenState();
}

class _GroupEntrySettingsScreenState extends State<GroupEntrySettingsScreen> {
  GroupEntrySettings _settings =
      const GroupEntrySettings(joinMode: GroupJoinMode.requestApproval);
  GroupEntrySettings? _saved;

  VerificationForm? _form;
  NetworkFailure? _failure;
  bool _loading = true;
  bool _saving = false;

  bool get _dirty => _saved != null && _settings != _saved;

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
      final form = await widget.repository.activeForm(widget.groupId);
      if (!mounted) return;
      // The group's own mode is not exposed on a read endpoint yet, so the
      // presence of a form is the best available signal for the initial state.
      final initial = GroupEntrySettings(
        joinMode: GroupJoinMode.requestApproval,
        verificationFormId: form?.id,
      );
      setState(() {
        _form = form;
        _settings = initial;
        _saved = initial;
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.saveSettings(widget.groupId, _settings);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _saved = _settings;
        _saving = false;
      });
      _toast(L.of(context).settingsSaved);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _saving = false);
      _toast(failureMessage(L.of(context), NetworkFailureClassifier.from(e)));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFormBuilder() async {
    final created = await Navigator.of(context).push<VerificationForm>(
      MaterialPageRoute(
        builder: (_) => FormBuilderScreen(
          repository: widget.repository,
          groupId: widget.groupId,
          existing: _form,
        ),
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      _form = created;
      _settings = _settings.copyWith(verificationFormId: created.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(t.entrySettingsTitle),
        actions: [
          IconButton(
            tooltip: t.auditLogTitle,
            icon: const Icon(IronIcons.summary, size: IronIcons.sizeInline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AuditLogScreen(
                  repository: widget.repository,
                  groupId: widget.groupId,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _body(t),
      bottomNavigationBar: _loading || _failure != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(IronSpacing.md),
                child: IronButton(
                  label: t.saveChanges,
                  loading: _saving,
                  onPressed: _dirty ? _save : null,
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
    if (_failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(IronSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                failureMessage(t, _failure!),
                textAlign: TextAlign.center,
                style: IronTypography.bodyMedium(
                    color: IronColors.textSecondary),
              ),
              const SizedBox(height: IronSpacing.md),
              IronButton(
                label: t.retry,
                variant: IronButtonVariant.secondary,
                expand: false,
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(IronSpacing.md),
      children: [
        _SectionLabel(text: t.joinModeSection),
        const SizedBox(height: IronSpacing.xs),
        for (final mode in GroupJoinMode.values)
          _ModeTile(
            mode: mode,
            selected: _settings.joinMode == mode,
            onTap: () => setState(
              () => _settings = _settings.copyWith(joinMode: mode),
            ),
          ),

        // The form only affects request_approval, so offering it in other
        // modes would be a control with no effect.
        if (_settings.joinMode.usesForm) ...[
          const SizedBox(height: IronSpacing.lg),
          _SectionLabel(text: t.verificationFormSection),
          const SizedBox(height: IronSpacing.xs),
          _FormCard(
            form: _form,
            onTap: _openFormBuilder,
          ),

          const SizedBox(height: IronSpacing.lg),
          _SectionLabel(text: t.requestHandlingSection),
          const SizedBox(height: IronSpacing.xs),
          _ExpiryTile(
            days: _settings.requestExpiryDays,
            onChanged: (d) => setState(
              () => _settings = _settings.copyWith(requestExpiryDays: d),
            ),
          ),
          const SizedBox(height: IronSpacing.xs),
          _SwitchTile(
            title: t.allowRejoinTitle,
            subtitle: t.allowRejoinHint,
            value: _settings.allowRejoin,
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(allowRejoin: v),
            ),
          ),
        ],

        const SizedBox(height: IronSpacing.xl),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: IronTypography.headlineMedium(color: IronColors.textPrimary),
      );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final GroupJoinMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final (title, subtitle, icon) = switch (mode) {
      GroupJoinMode.open => (t.modeOpen, t.modeOpenHint, IronIcons.groups),
      GroupJoinMode.inviteOnly => (
          t.modeInviteOnly,
          t.modeInviteOnlyHint,
          IronIcons.verified
        ),
      GroupJoinMode.requestApproval => (
          t.modeRequestApproval,
          t.modeRequestApprovalHint,
          IronIcons.shield
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: IronSpacing.xs),
      child: Material(
        color: selected ? IronColors.accentSubtle : IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IronRadius.md),
          child: Container(
            padding: const EdgeInsets.all(IronSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(IronRadius.md),
              border: Border.all(
                color: selected
                    ? IronColors.accentText
                    : IronColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: IronIcons.sizeInline,
                  color: selected
                      ? IronColors.accentText
                      : IronColors.textSecondary,
                ),
                const SizedBox(width: IronSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: IronTypography.bodyLarge(
                            color: IronColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: IronTypography.bodySmall(
                            color: IronColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(IronIcons.success,
                      size: IronIcons.sizeInline,
                      color: IronColors.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.form, required this.onTap});

  final VerificationForm? form;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final hasForm = form != null;

    return Material(
      color: IronColors.surfacePrimary,
      borderRadius: BorderRadius.circular(IronRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IronRadius.md),
        child: Container(
          padding: const EdgeInsets.all(IronSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IronRadius.md),
            border: Border.all(
              // A gated group with no form asks nothing of applicants, which
              // is almost certainly not what the admin intended.
              color: hasForm
                  ? IronColors.borderSubtle
                  : IronColors.semanticWarning.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasForm ? IronIcons.summary : IronIcons.info,
                size: IronIcons.sizeInline,
                color: hasForm
                    ? IronColors.textSecondary
                    : IronColors.semanticWarning,
              ),
              const SizedBox(width: IronSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasForm ? form!.name : t.noFormAttached,
                      style: IronTypography.bodyLarge(
                          color: IronColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasForm
                          ? t.fieldCount(form!.fields.length)
                          : t.noFormAttachedHint,
                      style: IronTypography.bodySmall(
                          color: IronColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const Icon(IronIcons.forward,
                  size: IronIcons.sizeCompact, color: IronColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpiryTile extends StatelessWidget {
  const _ExpiryTile({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  static const _choices = [0, 3, 7, 14, 30];

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Container(
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.requestExpiryTitle,
            style: IronTypography.bodyLarge(color: IronColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            t.requestExpiryHint,
            style: IronTypography.bodySmall(color: IronColors.textTertiary),
          ),
          const SizedBox(height: IronSpacing.sm),
          Wrap(
            spacing: IronSpacing.xs,
            children: [
              for (final choice in _choices)
                ChoiceChip(
                  label: Text(
                    // 0 reads as "never", not "immediately".
                    choice == 0 ? t.expiryNever : t.expiryDays(choice),
                  ),
                  selected: days == choice,
                  onSelected: (_) => onChanged(choice),
                  backgroundColor: IronColors.surfaceSecondary,
                  selectedColor: IronColors.accentSubtle,
                  side: BorderSide(
                    color: days == choice
                        ? IronColors.accentText
                        : IronColors.borderInteractive,
                  ),
                  labelStyle: IronTypography.bodySmall(
                    color: days == choice
                        ? IronColors.textPrimary
                        : IronColors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: IronSpacing.md,
        end: IronSpacing.xs,
        top: IronSpacing.xs,
        bottom: IronSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        activeColor: IronColors.accentPrimary,
        title: Text(
          title,
          style: IronTypography.bodyLarge(color: IronColors.textPrimary),
        ),
        subtitle: Text(
          subtitle,
          style: IronTypography.bodySmall(color: IronColors.textTertiary),
        ),
      ),
    );
  }
}
