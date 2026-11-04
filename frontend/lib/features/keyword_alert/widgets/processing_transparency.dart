import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/keyword_alert.dart';

/// Where documents are read, stated plainly (§7.2).
///
/// WHY A SURFACE RATHER THAN A SETTING
///
/// "Local by default" is a claim, and a claim the user cannot check is
/// indistinguishable from marketing. This shows what actually happened: the
/// current mode, and — per alert — where that specific document was read. The
/// per-alert part matters because the setting can change afterwards, and a
/// user reviewing an alert from last week is entitled to know where *it* was
/// processed, not where the next one would be.
///
/// The claim it makes is deliberately narrow. It says where text extraction
/// ran. It does not say "your data is safe", because that is not a thing a
/// widget can know.
class ProcessingTransparencyCard extends StatelessWidget {
  const ProcessingTransparencyCard({
    super.key,
    required this.cloudEnabled,
    required this.localEngineAvailable,
  });

  /// Off unless the user turned it on. §10.3 treats a cloud opt-in rate above
  /// 20% as a privacy health failure, not a growth metric.
  final bool cloudEnabled;

  /// False on a platform with no on-device engine, where the honest thing to
  /// say is that image documents cannot be checked — not to quietly start
  /// sending them somewhere.
  final bool localEngineAvailable;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Container(
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            cloudEnabled ? Icons.cloud_outlined : Icons.phone_android,
            size: 20,
            color: cloudEnabled
                ? IronColors.semanticWarning
                : IronColors.semanticSuccess,
          ),
          const SizedBox(width: IronSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cloudEnabled
                      ? l.alertProcessedInCloud
                      : l.alertProcessedLocally,
                  style: IronTypography.bodyMedium(
                    color: IronColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localEngineAvailable
                      ? l.securityCenterLocalExplained
                      : l.securityCenterNoLocalEngine,
                  style: IronTypography.bodySmall(
                    color: IronColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-alert badge: where *this* document was read.
class ProcessingSourceBadge extends StatelessWidget {
  const ProcessingSourceBadge({super.key, required this.source});

  final ProcessingSource source;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final local = source == ProcessingSource.local;

    return Semantics(
      // The icon repeats the label rather than replacing it. A user who cannot
      // distinguish the two icons still hears which one it is.
      label: local ? l.alertProcessedLocally : l.alertProcessedInCloud,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              local ? Icons.phone_android : Icons.cloud_outlined,
              size: 12,
              color: IronColors.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              local ? l.alertProcessedLocally : l.alertProcessedInCloud,
              style: IronTypography.labelSmall(color: IronColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
