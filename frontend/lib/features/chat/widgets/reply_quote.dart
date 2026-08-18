import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../chat_repository.dart';

/// The quoted message shown above a reply, and in the composer while writing
/// one.
///
/// WHY THE QUOTATION IS RESOLVED HERE AND NOT SENT BY THE SERVER
///
/// Every other messenger can attach the quoted text to the reply, because the
/// server has both. This one cannot: `content_ciphertext` is ciphertext and
/// there is no key on the server, so a reply carries an id and nothing more.
///
/// That has a consequence worth being honest about rather than hiding. If this
/// device does not hold the original — a fresh install, a conversation whose
/// history has not been fetched, a message that was retracted — there is no
/// way to obtain it. Not from the server, not from anywhere. So the quote says
/// so, in the same shape as a real one, instead of rendering an empty block
/// that reads as a bug.
///
/// The alternative designs are both worse. Sending the quoted text inside the
/// encrypted envelope would work, and would mean the same sentence is stored
/// twice under two different keys — so retracting the original would leave
/// copies of it inside every reply, which is a deletion that does not delete.
/// Sending it in the clear alongside the ciphertext would simply hand the
/// server the message.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.original,
    required this.myId,
    this.onDismiss,
    this.onTap,
  });

  /// The message being answered, or null when this device does not have it.
  final ChatMessage? original;

  final String myId;

  /// Shown as a close button when present — used by the composer preview.
  final VoidCallback? onDismiss;

  /// Jumps to the original. Absent when there is nothing to jump to.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final missing = original == null;
    final mine = original?.isMine ?? false;

    return InkWell(
      onTap: missing ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsetsDirectional.only(
          start: 8,
          end: 6,
          top: 6,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color: IronColors.navyDeep.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          // A leading bar rather than a full border: it reads as a quotation
          // at a glance and costs less width, which matters inside a bubble
          // that is already indented.
          border: BorderDirectional(
            start: BorderSide(
              color: missing
                  ? IronColors.textTertiary
                  : (mine ? IronColors.gold : IronColors.accentText),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    missing
                        ? t.replyUnavailableTitle
                        : (mine ? t.replyToYou : t.replyToThem),
                    style: IronTypography.labelSmall(
                      color: missing
                          ? IronColors.textTertiary
                          : (mine ? IronColors.gold : IronColors.accentText),
                    ),
                  ),
                ),
                if (onDismiss != null)
                  GestureDetector(
                    onTap: onDismiss,
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: IronColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              missing ? t.replyUnavailableBody : _preview(t, original!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IronTypography.labelSmall(
                color: missing
                    ? IronColors.textTertiary
                    : IronColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One line describing the original.
  ///
  /// A retracted message is named as retracted rather than quoted: the whole
  /// point of retracting it is that it stops being readable, and a reply that
  /// preserved the text would undo that for every reader.
  static String _preview(L t, ChatMessage message) {
    if (message.deleted) return t.replyOriginalDeleted;
    final content = message.content?.trim();
    if (content != null && content.isNotEmpty) return content;
    return switch (message.kind) {
      'image' => t.replyKindImage,
      'voice' => t.replyKindVoice,
      _ => t.replyKindAttachment,
    };
  }
}
