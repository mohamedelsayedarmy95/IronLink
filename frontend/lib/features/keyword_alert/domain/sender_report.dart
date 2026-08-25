import 'keyword_alert.dart';

/// What a sender may learn about a document they sent (§6.1, §1.4).
///
/// THE BOUNDARY IS THE TYPE
///
/// The rule is that the sender sees at most "a keyword alert was triggered for
/// this recipient", and never the keyword, the matched text, the context, or
/// the page. Enforcing that with a permission check inside a screen means the
/// rule holds until someone writes a second screen. Enforcing it with a type
/// that has nowhere to put a keyword means it holds by construction: there is
/// no field to fill in, so there is no version of this that leaks by accident.
///
/// The same reasoning covers group admins (§6.2). An admin is a sender with a
/// title; they get this object and nothing more. There is no
/// group-level view of who is watching for what, because such a view would be
/// surveillance of the members by the group, which §1.4 forbids outright.
class SenderReportEntry {
  const SenderReportEntry({
    required this.recipientUserId,
    required this.alertRaised,
    required this.acknowledged,
    this.sharedAt,
  });

  final String recipientUserId;

  /// Whether *an* alert fired. Not which, not why.
  final bool alertRaised;

  /// Whether the recipient explicitly acknowledged. Meaningful to a sender —
  /// it answers "did they actually deal with the thing I sent?" — and it
  /// reveals nothing about what was matched.
  final bool acknowledged;

  /// When the recipient permitted this to be shared. Null means they have not,
  /// and the sender sees nothing at all.
  final DateTime? sharedAt;

  bool get isVisibleToSender => sharedAt != null;

  /// Builds the sender's view of an alert.
  ///
  /// Takes the whole alert and deliberately discards nearly all of it. Written
  /// this way rather than as a constructor call at each site so that there is
  /// exactly one place where the boundary is crossed, and it is a place with
  /// a test on it.
  static SenderReportEntry from(
    KeywordAlert alert, {
    required bool recipientPermitsSharing,
    DateTime? sharedAt,
  }) =>
      SenderReportEntry(
        recipientUserId: alert.recipientUserId,
        alertRaised: alert.status.isMatch,
        acknowledged: alert.status == AlertStatus.acknowledged,
        sharedAt: recipientPermitsSharing ? (sharedAt ?? alert.detectedAt) : null,
      );

  /// The wire form, for the day this is synced between devices.
  ///
  /// Enumerated explicitly rather than serialized from the alert, so that
  /// adding a field to [KeywordAlert] cannot silently widen what a sender
  /// receives. A new leak would have to be typed out here on purpose.
  Map<String, Object?> toJson() => {
        'recipient_user_id': recipientUserId,
        'alert_raised': alertRaised,
        'acknowledged': acknowledged,
        'shared_at': sharedAt?.toUtc().millisecondsSinceEpoch,
      };
}
