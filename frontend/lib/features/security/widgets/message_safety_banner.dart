import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/scam_signals.dart';

/// Assesses a message once, and remembers.
///
/// A bubble rebuilds constantly while a list scrolls, and running a dozen
/// regular expressions plus URL parsing on every frame for every visible
/// message is the kind of cost that shows up as jank on the devices this
/// product is most likely to be used on. The cache is keyed by message id
/// because a message's text does not change — an edited message would be a new
/// id, and a deleted one has no text to assess.
///
/// Bounded, because an unbounded cache over a long conversation is a leak that
/// holds decrypted message text. When it fills, it drops oldest-first; the cost
/// of a miss is one reassessment.
class MessageSafety {
  MessageSafety({ScamIntelligence? intelligence, this.maxEntries = 200})
      : _intelligence = intelligence ?? const ScamIntelligence();

  final ScamIntelligence _intelligence;
  final int maxEntries;

  final Map<String, ScamAssessment> _cache = {};

  ScamAssessment assess(String messageId, String text) {
    final cached = _cache[messageId];
    if (cached != null) return cached;

    final assessment = _intelligence.assess(text);
    if (_cache.length >= maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[messageId] = assessment;
    return assessment;
  }

  /// Called on sign-out, alongside the other stores. The cache holds
  /// assessments derived from decrypted text; it should not outlive the user.
  void clear() => _cache.clear();
}

/// The warning strip inside a message bubble.
///
/// WHAT IT IS NOT
///
/// It is not a block, an overlay, or a confirmation. The message is rendered
/// normally above it and the links remain tappable. A messenger that gets in
/// the way of reading messages is a messenger people work around, and a warning
/// that must be dismissed before continuing is one that gets dismissed
/// reflexively.
///
/// It is also not shown on the user's own messages. Warning someone that the
/// message they just wrote contains a payment request is noise, and worse, it
/// implies the app is grading their conversation.
class MessageSafetyBanner extends StatefulWidget {
  const MessageSafetyBanner({
    super.key,
    required this.assessment,
    required this.isMine,
  });

  final ScamAssessment assessment;
  final bool isMine;

  @override
  State<MessageSafetyBanner> createState() => _MessageSafetyBannerState();
}

class _MessageSafetyBannerState extends State<MessageSafetyBanner> {
  bool _explained = false;
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    // The sender's own message is never assessed for them, and a message with
    // nothing conclusive is left alone entirely — an unexplained icon on an
    // ordinary message is worse than silence.
    if (widget.isMine || !widget.assessment.shouldWarn || _dismissed) {
      return const SizedBox.shrink();
    }

    final t = L.of(context);
    final primary = widget.assessment.primary;
    if (primary == null) return const SizedBox.shrink();

    return Semantics(
      // Read as one statement. A screen reader user should learn what the
      // warning is without having to explore the strip's parts.
      label: '${t.safetyWarningTitle}. ${_headline(t, primary)}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            // Amber, not red. This is a caution about a possibility, and red
            // is the colour this product uses for things that are certainly
            // wrong — a failed decryption, a tampered attachment.
            color: IronColors.semanticWarning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: IronColors.semanticWarning.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: IronColors.semanticWarning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _headline(t, primary),
                      style: IronTypography.bodySmall(
                        color: IronColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (_explained) ...[
                const SizedBox(height: 6),
                Text(
                  _why(t, primary),
                  style: IronTypography.labelSmall(
                    color: IronColors.textSecondary,
                  ),
                ),
                // Naming the actual domain matters more than the category. A
                // user who is told "this link is deceptive" learns nothing; one
                // who is shown the host can check it against what they expected.
                for (final verdict in widget.assessment.linkVerdicts
                    .where((v) => v.shouldWarn))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _hostOf(verdict.url),
                      style: IronTypography.labelSmall(
                        color: IronColors.textTertiary,
                      ),
                    ),
                  ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _explained = !_explained),
                    child: Text(
                      t.securityWhyLabel,
                      style: IronTypography.labelSmall(
                        color: IronColors.accentText,
                      ),
                    ),
                  ),
                  TextButton(
                    // Dismissal is per message and lasts the session. Not
                    // persisted: if the user reopens the conversation later
                    // they have not re-read the message, and the warning is
                    // about the message rather than about their patience.
                    onPressed: () => setState(() => _dismissed = true),
                    child: Text(
                      t.safetyDismiss,
                      style: IronTypography.labelSmall(
                        color: IronColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _headline(L t, ScamSignal signal) => switch (signal) {
        ScamSignal.credentialRequest => t.safetyCredentialRequest,
        ScamSignal.suspiciousLink => t.safetySuspiciousLink,
        ScamSignal.paymentRequest => t.safetyPaymentRequest,
        ScamSignal.authorityClaim => t.safetyAuthorityClaim,
        ScamSignal.offPlatformMove => t.safetyOffPlatform,
        ScamSignal.urgency => t.safetyUrgency,
      };

  static String _why(L t, ScamSignal signal) => switch (signal) {
        ScamSignal.credentialRequest => t.safetyCredentialRequestWhy,
        ScamSignal.suspiciousLink => t.safetySuspiciousLinkWhy,
        ScamSignal.paymentRequest => t.safetyPaymentRequestWhy,
        ScamSignal.authorityClaim => t.safetyAuthorityClaimWhy,
        ScamSignal.offPlatformMove => t.safetyOffPlatformWhy,
        ScamSignal.urgency => t.safetyUrgencyWhy,
      };

  /// The host alone, which is the part that identifies where a link goes. A
  /// full URL in a warning is unreadable on a phone and hides the domain in
  /// the middle of a path.
  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    try {
      return Uri.decodeComponent(uri.host);
    } catch (_) {
      return uri.host;
    }
  }
}
