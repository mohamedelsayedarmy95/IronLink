import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/alert_bloc.dart';
import '../domain/keyword_alert.dart';
import '../widgets/smart_alert_ticker.dart' show priorityColor;

/// Alert history (§4.5, §5.6).
///
/// The ticker answers "what needs me now"; this answers "what happened". They
/// are different questions, and the previous implementation could answer
/// neither — its fifty in-memory alerts were gone the moment the app was
/// killed, so a missed alert and a handled one looked identical afterwards.
///
/// Alerts are kept for 48 hours and then deleted (§4.5). That is said on the
/// screen rather than left to be discovered, because a user who assumes this
/// is an archive will one day go looking for something that was never going to
/// be there.
class AlertCenterScreen extends StatefulWidget {
  const AlertCenterScreen({super.key, this.onOpenDocument});

  final void Function(KeywordAlert alert)? onOpenDocument;

  @override
  State<AlertCenterScreen> createState() => _AlertCenterScreenState();
}

class _AlertCenterScreenState extends State<AlertCenterScreen> {
  @override
  void initState() {
    super.initState();
    // Re-read on open: alerts may have expired while the screen was away, and
    // showing a stale list would contradict the retention promise above.
    context.read<AlertBloc>().add(const AlertsRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(l.alertCenterTitle),
        backgroundColor: IronColors.backgroundPrimary,
      ),
      body: BlocBuilder<AlertBloc, AlertState>(
        builder: (context, state) {
          final alerts = state.filteredHistory;

          return Column(
            children: [
              _FilterBar(current: state.filter),
              if (alerts.isEmpty)
                Expanded(child: _EmptyState(filter: state.filter))
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      ..._sectioned(context, alerts),
                      Padding(
                        padding: const EdgeInsets.all(IronSpacing.lg),
                        child: Text(
                          l.alertRetentionNote,
                          style: IronTypography.labelSmall(
                            color: IronColors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Today / Yesterday / Earlier (§5.6).
  ///
  /// Grouped against the device's local midnight rather than a rolling 24
  /// hours, because "yesterday" is a calendar word — an alert from 11pm last
  /// night is yesterday's at 1am, not "two hours ago".
  List<Widget> _sectioned(BuildContext context, List<KeywordAlert> alerts) {
    final l = L.of(context);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final today = <KeywordAlert>[];
    final yesterday = <KeywordAlert>[];
    final earlier = <KeywordAlert>[];

    for (final alert in alerts) {
      final at = alert.detectedAt.toLocal();
      if (!at.isBefore(todayStart)) {
        today.add(alert);
      } else if (!at.isBefore(yesterdayStart)) {
        yesterday.add(alert);
      } else {
        earlier.add(alert);
      }
    }

    return [
      ..._section(l.alertSectionToday, today),
      ..._section(l.alertSectionYesterday, yesterday),
      ..._section(l.alertSectionEarlier, earlier),
    ];
  }

  List<Widget> _section(String title, List<KeywordAlert> alerts) {
    if (alerts.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          IronSpacing.lg,
          IronSpacing.lg,
          IronSpacing.lg,
          IronSpacing.sm,
        ),
        // A header, so a screen reader announces the grouping instead of
        // reading a flat list of times.
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: IronTypography.labelSmall(color: IronColors.textSecondary),
          ),
        ),
      ),
      for (final alert in alerts)
        AlertHistoryTile(alert: alert, onOpenDocument: widget.onOpenDocument),
    ];
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.current});

  final AlertHistoryFilter current;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final labels = {
      AlertHistoryFilter.all: l.alertFilterAll,
      AlertHistoryFilter.unacknowledged: l.alertFilterUnacknowledged,
      AlertHistoryFilter.acknowledged: l.alertFilterAcknowledged,
      AlertHistoryFilter.highConfidence: l.alertFilterHighConfidence,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: IronSpacing.lg,
        vertical: IronSpacing.sm,
      ),
      child: Row(
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: current == entry.key,
                onSelected: (_) => context
                    .read<AlertBloc>()
                    .add(AlertFilterChanged(entry.key)),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final AlertHistoryFilter filter;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IronSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_none,
              size: 48,
              color: IronColors.textTertiary,
            ),
            const SizedBox(height: IronSpacing.md),
            Text(
              l.alertCenterEmpty,
              style: IronTypography.bodyLarge(color: IronColors.textSecondary),
            ),
            const SizedBox(height: IronSpacing.sm),
            Text(
              l.alertCenterEmptyHint,
              style: IronTypography.bodySmall(color: IronColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One alert in history: conversation, document, matched text, context, time
/// and status (§5.6).
class AlertHistoryTile extends StatelessWidget {
  const AlertHistoryTile({
    super.key,
    required this.alert,
    this.onOpenDocument,
  });

  final KeywordAlert alert;
  final void Function(KeywordAlert alert)? onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final accent = priorityColor(alert.priorityLevel);
    final status = _statusLabel(l, alert);

    return Semantics(
      button: onOpenDocument != null,
      // One sentence, so the tile is not read as four disconnected fragments.
      label: '${alert.matchedText ?? ''}. ${alert.contextText ?? ''}. $status',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpenDocument == null
              ? null
              : () {
                  context.read<AlertBloc>().add(AlertDocumentOpened(alert.id));
                  onOpenDocument!.call(alert);
                },
          child: Container(
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
                // A bar rather than a dot: at 3px wide and full height it
                // still reads at a glance without becoming decoration, and
                // priority is never carried by colour alone — the status text
                // below and the ordering both state it.
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: IronSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.matchedText ?? '',
                        style: IronTypography.bodyMedium(
                          color: IronColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (alert.contextText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          alert.contextText!,
                          style: IronTypography.bodySmall(
                            color: IronColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _Meta(text: status),
                          if (alert.documentPage != null)
                            _Meta(text: l.alertPageNumber(alert.documentPage!)),
                          _Meta(
                            text: alert.processingSource == ProcessingSource.local
                                ? l.alertProcessedLocally
                                : l.alertProcessedInCloud,
                          ),
                          if (alert.suppressedByDailyCap)
                            _Meta(text: l.alertSuppressedByCap),
                        ],
                      ),
                    ],
                  ),
                ),
                if (alert.status.isOutstanding)
                  IconButton(
                    // 48dp minimum, as everywhere else.
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.check),
                    color: IronColors.accentText,
                    tooltip: l.smartAlertAcknowledge,
                    onPressed: () => context
                        .read<AlertBloc>()
                        .add(AlertAcknowledged(alert.id)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _statusLabel(L l, KeywordAlert alert) => switch (alert.status) {
        AlertStatus.acknowledged => l.alertStatusAcknowledged,
        AlertStatus.documentOpened => l.alertStatusOpened,
        AlertStatus.dismissed => l.alertStatusDismissed,
        AlertStatus.expired => l.alertStatusExpired,
        _ => l.alertStatusPresented,
      };
}

class _Meta extends StatelessWidget {
  const _Meta({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: IronTypography.labelSmall(color: IronColors.textTertiary),
      );
}
