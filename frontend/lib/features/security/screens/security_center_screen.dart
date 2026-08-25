import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/security_bloc.dart';
import '../domain/security_posture.dart';
import '../security_repository.dart';

/// IronShield — the Security Center.
///
/// WHAT THIS SCREEN REFUSES TO DO
///
/// It does not show a percentage. A number implies a precision that a handful
/// of boolean signals cannot support, and its only real function would be to
/// make the user feel measured rather than informed.
///
/// It does not show a reassuring summary and hide the detail behind it. Every
/// finding carries the fact it came from and a "why am I seeing this?" that
/// explains it in a sentence — including the findings that are good news, so
/// the user can tell the difference between "checked and fine" and "not
/// checked".
///
/// And it never claims more than it knows. A signal the app could not establish
/// produces no row at all, rather than a row that assumes the best.
class SecurityCenterScreen extends StatelessWidget {
  const SecurityCenterScreen({
    super.key,
    this.encryptionDefault,
    this.keywordsAreLocal,
    this.cloudOcrEnabled,
  });

  /// Passed in by whoever knows. Null is a legitimate answer and produces
  /// silence on that point.
  final bool? encryptionDefault;
  final bool? keywordsAreLocal;
  final bool? cloudOcrEnabled;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => SecurityBloc(
        SecurityRepository(ctx.read<ApiClient>()),
        encryptionDefault: encryptionDefault,
        keywordsAreLocal: keywordsAreLocal,
        cloudOcrEnabled: cloudOcrEnabled,
      )..add(const SecurityRequested()),
      child: const _SecurityCenterView(),
    );
  }
}

class _SecurityCenterView extends StatelessWidget {
  const _SecurityCenterView();

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(t.securityCenterTitle),
        backgroundColor: IronColors.backgroundPrimary,
      ),
      body: BlocConsumer<SecurityBloc, SecurityState>(
        listener: (context, state) {
          // Surfaced rather than swallowed: telling someone their account is
          // secured while a device is still signed in would be the worst lie
          // this screen could tell.
          if (state.partialFailureCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                t.securitySecureAccountPartial(state.partialFailureCount),
              ),
              backgroundColor: IronColors.semanticError,
            ));
          }
        },
        builder: (context, state) {
          if (state.loading && !state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final failure = state.failure;
          if (failure != null && !state.hasData) {
            return _ErrorState(failure: failure);
          }

          final posture = state.posture;
          if (posture == null) {
            return const _ErrorState(failure: NetworkFailure.unknown);
          }

          return RefreshIndicator(
            onRefresh: () async =>
                context.read<SecurityBloc>().add(const SecurityRequested()),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _LevelHeader(level: posture.level),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IronSpacing.lg,
                    vertical: IronSpacing.sm,
                  ),
                  child: Text(
                    t.securityCenterSubtitle,
                    style: IronTypography.bodySmall(
                      color: IronColors.textTertiary,
                    ),
                  ),
                ),
                if (posture.findings.isEmpty)
                  _Row(
                    icon: Icons.check_circle_outline,
                    tint: IronColors.semanticSuccess,
                    title: t.securityCheckedNothingWrong,
                  )
                else
                  for (final finding in posture.findings)
                    _FindingRow(finding: finding),
                const SizedBox(height: IronSpacing.md),
                _SectionHeader(title: t.securityActiveSessions),
                if (posture.sessions.isEmpty)
                  _Row(
                    icon: Icons.devices_other,
                    tint: IronColors.textTertiary,
                    title: t.securityNoOtherDevices,
                  )
                else
                  for (final session in posture.sessions)
                    _SessionRow(session: session, busy: state.working),
                if (posture.otherSessions.isNotEmpty) ...[
                  const SizedBox(height: IronSpacing.lg),
                  _SecureAccountButton(busy: state.working),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LevelHeader extends StatelessWidget {
  const _LevelHeader({required this.level});

  final SecurityLevel level;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    final (label, tint, icon) = switch (level) {
      SecurityLevel.high => (
          t.securityLevelHigh,
          IronColors.semanticSuccess,
          Icons.shield_outlined,
        ),
      SecurityLevel.medium => (
          t.securityLevelMedium,
          IronColors.semanticWarning,
          Icons.shield_outlined,
        ),
      SecurityLevel.low => (
          t.securityLevelLow,
          IronColors.semanticError,
          Icons.gpp_maybe_outlined,
        ),
    };

    return Semantics(
      header: true,
      // The level is stated in words, not carried by the colour. A user who
      // cannot distinguish amber from red still learns the same thing.
      label: '${t.securityCenterTitle}. $label',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.all(IronSpacing.lg),
          padding: const EdgeInsets.all(IronSpacing.lg),
          decoration: BoxDecoration(
            color: IronColors.surfacePrimary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: IronColors.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 32, color: tint),
              const SizedBox(width: IronSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: IronTypography.titleMedium(
                    color: IronColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingRow extends StatefulWidget {
  const _FindingRow({required this.finding});

  final SecurityFinding finding;

  @override
  State<_FindingRow> createState() => _FindingRowState();
}

class _FindingRowState extends State<_FindingRow> {
  bool _explained = false;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final f = widget.finding;

    // Localized at the edge, from a code. A finding that carried its own
    // sentence would be shown in English to an Arabic-speaking user.
    final (title, why) = switch (f.code) {
      'other_devices_signed_in' => (
          t.securityFindingOtherDevices,
          t.securityFindingOtherDevicesWhy,
        ),
      'stale_session' => (
          t.securityFindingStaleSession,
          t.securityFindingStaleSessionWhy,
        ),
      'encryption_on' => (
          t.securityFindingEncryptionOn,
          t.securityFindingEncryptionOnWhy,
        ),
      'encryption_not_default' => (
          t.securityFindingEncryptionOff,
          t.securityFindingEncryptionOffWhy,
        ),
      'keywords_stay_on_device' => (
          t.securityFindingKeywordsLocal,
          t.securityFindingKeywordsLocalWhy,
        ),
      'cloud_ocr_enabled' => (
          t.securityFindingCloudOcr,
          t.securityFindingCloudOcrWhy,
        ),
      // An unknown code means a newer build wrote a finding this one cannot
      // name. Showing the raw code is honest; showing nothing would hide it.
      _ => (f.code, ''),
    };

    final (icon, tint) = switch (f.severity) {
      FindingSeverity.critical => (Icons.error_outline, IronColors.semanticError),
      FindingSeverity.warning =>
        (Icons.warning_amber_outlined, IronColors.semanticWarning),
      FindingSeverity.informational =>
        (Icons.info_outline, IronColors.textSecondary),
    };

    return _Row(
      icon: icon,
      tint: tint,
      title: title,
      subtitle: _explained && why.isNotEmpty ? why : null,
      trailing: why.isEmpty
          ? null
          : TextButton(
              onPressed: () => setState(() => _explained = !_explained),
              child: Text(
                t.securityWhyLabel,
                style: IronTypography.labelSmall(color: IronColors.accentText),
              ),
            ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.busy});

  final ActiveSession session;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final name = session.displayName ?? t.securityUnknownDevice;

    final lastSeen = session.lastActiveAt;
    final detail = [
      if (session.isCurrent) t.securityThisDevice,
      if (session.geoCity != null) session.geoCity!,
      if (lastSeen == null)
        t.securityNeverActive
      else
        t.securityLastActive(_relative(context, lastSeen)),
    ].join(' · ');

    return _Row(
      icon: session.isCurrent ? Icons.smartphone : Icons.devices_other,
      tint: session.isCurrent
          ? IronColors.semanticSuccess
          : IronColors.textSecondary,
      title: name,
      subtitle: detail,
      // The current session is never offered for revocation here. Signing
      // yourself out belongs on the sign-out control, not in a list of other
      // people's devices.
      trailing: session.isCurrent
          ? null
          : IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.logout),
              color: IronColors.textSecondary,
              tooltip: t.securitySignOutDevice,
              onPressed: busy ? null : () => _confirmRevoke(context, name),
            ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, String name) async {
    final t = L.of(context);
    final bloc = context.read<SecurityBloc>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IronColors.surfacePrimary,
        title: Text(name),
        content: Text(t.securitySignOutDeviceConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.securitySignOutDevice),
          ),
        ],
      ),
    );
    if (confirmed == true) bloc.add(SessionRevoked(session.id));
  }

  /// Coarse on purpose. "3 days ago" is what someone deciding whether they
  /// recognise a device needs; a timestamp to the second is noise.
  static String _relative(BuildContext context, DateTime at) {
    final delta = DateTime.now().toUtc().difference(at);
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    if (delta.inHours < 24) return '${delta.inHours}h';
    return '${delta.inDays}d';
  }
}

class _SecureAccountButton extends StatelessWidget {
  const _SecureAccountButton({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: IronSpacing.lg),
      child: FilledButton.icon(
        onPressed: busy ? null : () => _confirm(context),
        icon: const Icon(Icons.lock_outline),
        label: Text(t.securitySecureAccount),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final t = L.of(context);
    final bloc = context.read<SecurityBloc>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IronColors.surfacePrimary,
        title: Text(t.securitySecureAccount),
        content: Text(t.securitySecureAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.securitySecureAccount),
          ),
        ],
      ),
    );
    if (confirmed == true) bloc.add(const OtherSessionsRevoked());
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          IronSpacing.lg,
          IronSpacing.lg,
          IronSpacing.lg,
          IronSpacing.xs,
        ),
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: IronTypography.labelSmall(color: IronColors.textSecondary),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: IronSpacing.lg,
        vertical: 4,
      ),
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: IronSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: IronTypography.bodyMedium(
                    color: IronColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: IronTypography.bodySmall(
                      color: IronColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.failure});

  final NetworkFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IronSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: IronColors.textTertiary),
            const SizedBox(height: IronSpacing.md),
            Text(
              t.securityLoadFailed,
              style: IronTypography.bodyLarge(color: IronColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: IronSpacing.xs),
            // The specific reason, not a generic apology: offline and
            // unauthorized call for different actions from the user.
            Text(
              failureMessage(t, failure),
              style: IronTypography.bodySmall(color: IronColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: IronSpacing.md),
            FilledButton(
              onPressed: () =>
                  context.read<SecurityBloc>().add(const SecurityRequested()),
              child: Text(t.retry),
            ),
          ],
        ),
      ),
    );
  }
}
