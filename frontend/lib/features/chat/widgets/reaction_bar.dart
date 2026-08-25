import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// The reactions shown under a message, and the picker used to add one.
///
/// A FIXED SET, NOT A KEYBOARD
///
/// Six emoji, not a full picker. The point of a reaction is that it costs one
/// tap — a picker turns it into a search, at which point people type a message
/// instead and the feature has failed at the only thing it was for. This is
/// also why the set is the same six everywhere and not a most-recently-used
/// list: a control whose contents move is a control you have to read before
/// pressing, and that is the same cost as searching.
///
/// WHAT THE COUNT MEANS
///
/// Each chip shows one emoji and how many people chose it. The number is
/// computed on this device from individually encrypted reactions; the server
/// holds neither the emoji nor the total, only a set of messages it cannot
/// read.
class ReactionBar extends StatelessWidget {
  const ReactionBar({
    super.key,
    required this.reactions,
    required this.myId,
    required this.onToggle,
  });

  /// Sender id → emoji.
  final Map<String, String> reactions;

  final String myId;

  final void Function(String emoji) onToggle;

  /// The six. Chosen to cover the distinct things a reaction is usually doing
  /// — agreeing, appreciating, laughing, being surprised, being sorry, and
  /// disagreeing — rather than six shades of approval.
  static const quickSet = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Grouped by emoji, in a stable order, so a chip does not jump position
    // when somebody else reacts.
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final mine = reactions[myId];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final emoji in quickSet.where(counts.containsKey))
            _Chip(
              emoji: emoji,
              count: counts[emoji]!,
              isMine: mine == emoji,
              onTap: () => onToggle(emoji),
            ),
          // Anything outside the quick set — a reaction from a future build
          // with a wider palette. Rendered rather than dropped: an unknown
          // emoji is still something a person said.
          for (final emoji in counts.keys.where((e) => !quickSet.contains(e)))
            _Chip(
              emoji: emoji,
              count: counts[emoji]!,
              isMine: mine == emoji,
              onTap: () => onToggle(emoji),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Reads as a sentence rather than as "thumbs up 3", and says what
      // pressing it does — which differs depending on whether this person
      // already reacted.
      label: isMine
          ? '$emoji, $count, including you. Activate to remove yours.'
          : '$emoji, $count. Activate to add yours.',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isMine
                  ? IronColors.accentText.withValues(alpha: 0.18)
                  : IronColors.navyDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              // The outline is what marks your own reaction, not colour alone.
              border: Border.all(
                color: isMine
                    ? IronColors.accentText
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 12)),
                if (count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    style: IronTypography.labelSmall(
                      color: IronColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The row of six, shown above the message options sheet.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({
    super.key,
    required this.selected,
    required this.onPick,
  });

  /// This device's current reaction, so it can be shown as chosen and tapping
  /// it again reads as taking it back.
  final String? selected;

  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in ReactionBar.quickSet)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(emoji);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected == emoji
                      ? IronColors.accentText.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
        ],
      ),
    );
  }
}
