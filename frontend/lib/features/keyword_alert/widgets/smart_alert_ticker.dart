import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/alert_bloc.dart';
import '../domain/keyword_alert.dart';
import '../domain/keyword_rule.dart';

/// The Smart Alert ticker (§5.2, §5.2.1).
///
/// WHY THIS IS NOT A MARQUEE
///
/// The component it replaces was an infinitely scrolling horizontal marquee of
/// raw alert maps. Three things were wrong with that, and the middle one is
/// disqualifying:
///
/// * Moving text is harder to read, and this is meant to feel like
///   mission-critical information rather than an advertisement (§5.1).
/// * WCAG 2.2.2 requires that any automatically moving content lasting more
///   than five seconds can be paused, stopped, or hidden. An endless loop with
///   no control fails it outright.
/// * There was nothing to press. §5.2 requires the ticker to persist until
///   "تم الاطلاع" is explicitly pressed, and a scrolling strip of text has no
///   such button — so acknowledgement could not exist.
///
/// So it is a static, anchored row that stays until answered.
///
/// ACKNOWLEDGE IS NOT SEEN
///
/// Swiping the ticker away hides it and nothing more: the alert stays in
/// ALERT_PRESENTED and stays in history (§5.2.1). Opening the document is
/// also not acknowledgement. Only the explicit press clears it. That
/// distinction is the entire reason this feature is more than a notification,
/// so it is enforced in the events this widget sends, not in a convention.
class SmartAlertTicker extends StatelessWidget {
  const SmartAlertTicker({super.key, this.onOpenDocument});

  /// Opens the existing IronLink viewer at the matched page or region (§5.4).
  /// Injected rather than imported so the ticker does not depend on the
  /// viewer, which would make it untestable without one.
  final void Function(KeywordAlert alert)? onOpenDocument;

  /// §5.2.1: matches the standard IronLink list-row height.
  static const double containerHeight = 56;
  static const double horizontalPadding = 16;
  static const double verticalPadding = 12;
  static const double cornerRadius = 12;
  static const double iconSize = 20;

  /// §5.9 accessibility floor. The visible label may be smaller; the target
  /// may not.
  static const double minTouchTarget = 48;

  static const Duration entranceDuration = Duration(milliseconds: 220);
  static const Duration exitDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlertBloc, AlertState>(
      buildWhen: (a, b) =>
          a.leadAlert?.id != b.leadAlert?.id ||
          a.visibleCount != b.visibleCount,
      builder: (context, state) {
        final alert = state.leadAlert;

        return AnimatedSwitcher(
          duration: entranceDuration,
          reverseDuration: exitDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            // Respects the platform "reduce motion" setting: the slide is
            // decoration, the fade carries the meaning, so removing the slide
            // costs nothing.
            final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
            final fade = FadeTransition(opacity: animation, child: child);
            if (reduceMotion) return fade;
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.35),
                end: Offset.zero,
              ).animate(animation),
              child: fade,
            );
          },
          child: alert == null
              ? const SizedBox.shrink(key: ValueKey('no-alert'))
              : _TickerCard(
                  key: ValueKey(alert.id),
                  alert: alert,
                  visibleCount: state.visibleCount,
                  onOpenDocument: onOpenDocument,
                ),
        );
      },
    );
  }
}

class _TickerCard extends StatefulWidget {
  const _TickerCard({
    super.key,
    required this.alert,
    required this.visibleCount,
    this.onOpenDocument,
  });

  final KeywordAlert alert;
  final int visibleCount;
  final void Function(KeywordAlert alert)? onOpenDocument;

  @override
  State<_TickerCard> createState() => _TickerCardState();
}

class _TickerCardState extends State<_TickerCard> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    // Recorded once the frame is actually on screen. Marking an alert
    // "presented" when it was merely created would claim the user saw
    // something that was drawn while the app was in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.alert.status == AlertStatus.alertCreated) {
        context.read<AlertBloc>().add(AlertPresented(widget.alert.id));
      }
    });
  }

  Future<void> _acknowledge() async {
    // A brief checkmark before the fade (§5.2.1) — enough to confirm the press
    // registered, short enough not to be a delay.
    setState(() => _confirming = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    context.read<AlertBloc>().add(AlertAcknowledged(widget.alert.id));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final alert = widget.alert;
    final accent = priorityColor(alert.priorityLevel);

    final summary = widget.visibleCount > 1
        ? l.smartAlertMoreCount(widget.visibleCount)
        : null;

    return SafeArea(
      // §5.2.1: never renders under a status bar or notch. Only the top edge —
      // the ticker is anchored below the app bar and has no business reserving
      // space at the bottom.
      top: true,
      bottom: false,
      child: Semantics(
        container: true,
        liveRegion: true,
        // Read as one sentence rather than as five disconnected fragments,
        // which is what a screen reader does with a Row of Texts.
        label: l.smartAlertSemantics(
          alert.matchedText ?? '',
          alert.contextText ?? '',
        ),
        child: Dismissible(
          key: ValueKey('dismiss-${alert.id}'),
          direction: DismissDirection.horizontal,
          // Visual only. The alert stays outstanding and stays in history —
          // swiping is "not now", not "handled".
          onDismissed: (_) =>
              context.read<AlertBloc>().add(AlertHidden(alert.id)),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: SmartAlertTicker.containerHeight,
              // Auto-height up to three rows before internal scroll (§5.2.1).
              maxHeight: 168,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(
              horizontal: SmartAlertTicker.horizontalPadding,
              vertical: SmartAlertTicker.verticalPadding,
            ),
            decoration: BoxDecoration(
              color: IronColors.surfacePrimary,
              borderRadius:
                  BorderRadius.circular(SmartAlertTicker.cornerRadius),
              border: Border.all(color: IronColors.borderSubtle),
              boxShadow: const [
                // "Very restrained glow" (§5.1): a 2dp-equivalent lift, not a
                // halo.
                BoxShadow(
                  color: IronColors.elevationShadow,
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              children: [
                // A vector icon, not an emoji — emoji render differently on
                // every platform and are announced literally by screen readers.
                Icon(
                  Icons.find_in_page_outlined,
                  size: SmartAlertTicker.iconSize,
                  color: accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary ?? l.smartAlertTitle,
                        style: IronTypography.labelSmall(
                          color: IronColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        // The document's own words. The keyword itself is
                        // never shown to anyone but its owner, and this is
                        // that owner's screen.
                        alert.matchedText ?? '',
                        style: IronTypography.bodyMedium(
                          color: IronColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _TickerAction(
                  icon: Icons.description_outlined,
                  tooltip: l.smartAlertOpenDocument,
                  onPressed: () {
                    context
                        .read<AlertBloc>()
                        .add(AlertDocumentOpened(alert.id));
                    widget.onOpenDocument?.call(alert);
                  },
                ),
                _TickerAction(
                  icon: _confirming ? Icons.check_circle : Icons.check,
                  tooltip: l.smartAlertAcknowledge,
                  color: _confirming ? IronColors.semanticSuccess : accent,
                  onPressed: _confirming ? null : _acknowledge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TickerAction extends StatelessWidget {
  const _TickerAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          // The floor is the target, not the glyph (§5.9).
          width: SmartAlertTicker.minTouchTarget,
          height: SmartAlertTicker.minTouchTarget,
          child: IconButton(
            icon: Icon(icon, size: SmartAlertTicker.iconSize),
            color: color ?? IronColors.accentText,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

/// §5.1.1 priority colours.
///
/// Critical and High get their own hues because they mean "act now"; Medium
/// and Low deliberately do not, because colouring everything is the same as
/// colouring nothing. Colour is never the only signal — the ticker also
/// orders by priority, and the screen-reader label states it.
Color priorityColor(KeywordPriority priority) => switch (priority) {
      KeywordPriority.critical => IronColors.semanticError,
      KeywordPriority.high => IronColors.semanticWarning,
      KeywordPriority.medium || KeywordPriority.low => IronColors.accentText,
    };
