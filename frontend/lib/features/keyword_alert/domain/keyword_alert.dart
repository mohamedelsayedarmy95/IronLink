import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'keyword_rule.dart';

/// An alert is a domain object with a lifecycle, not a notification that was
/// shown once and forgotten.
///
/// The distinction is the whole point. A notification that scrolls past while
/// the phone is in a pocket is indistinguishable, afterwards, from one that
/// never fired — which is useless for the thing this feature is for. An alert
/// here is created, presented, opened, and explicitly acknowledged, and every
/// one of those is recorded, so "did I deal with that?" has an answer.

/// How the rule's text was found in the document. Ordered from strongest to
/// weakest evidence; the ordering is used when several rules match the same
/// document and only the best match should lead.
enum MatchType {
  exact,
  normalized,
  phrase,
  regex,
  fuzzy,
  lowConfidence,

  /// Meaning-based rather than surface matching. Phase 5, EXPERIMENTAL, and
  /// never reachable while its feature flag is off.
  semantic;

  static MatchType fromName(String? name) => MatchType.values
      .firstWhere((m) => m.name == name, orElse: () => MatchType.normalized);
}

/// Where the text extraction actually ran. Recorded per alert rather than read
/// from a setting, because the setting can change afterwards and the user is
/// entitled to know where *this* document was processed (§7.2).
enum ProcessingSource {
  local,
  cloud,
  hybrid;

  static ProcessingSource fromName(String? name) => ProcessingSource.values
      .firstWhere((s) => s.name == name, orElse: () => ProcessingSource.local);
}

/// §4.2. Every state the pipeline can be observed in, including the ones where
/// nothing was found — a document that was checked and came back clean is a
/// different, and more reassuring, fact than one that was never checked.
enum AlertStatus {
  pendingProcessing,
  waitingForNetwork,
  processing,
  noMatch,
  matchDetected,
  alertCreated,
  alertPresented,
  documentOpened,
  acknowledged,

  /// Not in §4.2's list, but §4.1 carries `dismissedAt` and §10.3 tracks a
  /// Dismissal Rate — both of which need a state that is neither acknowledged
  /// nor still outstanding.
  dismissed,

  processingFailed,
  ocrUnavailable,
  unsupportedDocument,
  lowConfidence,
  expired;

  static AlertStatus fromName(String? name) => AlertStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => AlertStatus.pendingProcessing,
      );

  /// Nothing follows a terminal state. Reaching one is how the pipeline knows
  /// it may stop spending battery on this document.
  bool get isTerminal => _transitions[this]!.isEmpty;

  /// Whether the user still owes this alert an answer. Drives the ticker, the
  /// unread count, and the acknowledgement-completion metric.
  bool get isOutstanding => const {
        AlertStatus.alertCreated,
        AlertStatus.alertPresented,
        AlertStatus.documentOpened,
      }.contains(this);

  /// Whether this state represents a match the user should be told about.
  bool get isMatch => const {
        AlertStatus.matchDetected,
        AlertStatus.alertCreated,
        AlertStatus.alertPresented,
        AlertStatus.documentOpened,
        AlertStatus.acknowledged,
        AlertStatus.dismissed,
      }.contains(this);

  bool canTransitionTo(AlertStatus next) => _transitions[this]!.contains(next);
}

/// The transition table, written out rather than inferred.
///
/// An explicit table is what makes the illegal transitions testable: it is the
/// difference between "we never wrote code that does that" and "that cannot
/// happen". In particular an acknowledged alert can never go back to
/// outstanding, and an expired one can never come back at all — otherwise a
/// duplicate WebSocket frame or a replayed push could resurrect an alert the
/// user already dealt with.
const Map<AlertStatus, Set<AlertStatus>> _transitions = {
  AlertStatus.pendingProcessing: {
    AlertStatus.processing,
    AlertStatus.waitingForNetwork,
    AlertStatus.unsupportedDocument,
    AlertStatus.ocrUnavailable,
    AlertStatus.expired,
  },
  // Cloud processing only (§8.5). Local extraction never waits for a network.
  AlertStatus.waitingForNetwork: {
    AlertStatus.processing,
    AlertStatus.pendingProcessing,
    AlertStatus.processingFailed,
    AlertStatus.expired,
  },
  AlertStatus.processing: {
    AlertStatus.noMatch,
    AlertStatus.matchDetected,
    AlertStatus.lowConfidence,
    AlertStatus.processingFailed,
    AlertStatus.ocrUnavailable,
    AlertStatus.unsupportedDocument,
    AlertStatus.expired,
  },
  AlertStatus.matchDetected: {
    AlertStatus.alertCreated,
    AlertStatus.expired,
  },
  // Acknowledgement straight from alertCreated is legal: the user can act on a
  // push notification without the ticker ever having drawn a frame.
  AlertStatus.alertCreated: {
    AlertStatus.alertPresented,
    AlertStatus.documentOpened,
    AlertStatus.acknowledged,
    AlertStatus.dismissed,
    AlertStatus.expired,
  },
  AlertStatus.alertPresented: {
    AlertStatus.documentOpened,
    AlertStatus.acknowledged,
    AlertStatus.dismissed,
    AlertStatus.expired,
  },
  AlertStatus.documentOpened: {
    AlertStatus.acknowledged,
    AlertStatus.dismissed,
    AlertStatus.expired,
  },
  // Retryable failures. The retry cap lives on the alert, not here, because
  // the legality of retrying and the wisdom of it are different questions.
  AlertStatus.processingFailed: {
    AlertStatus.processing,
    AlertStatus.expired,
  },
  AlertStatus.ocrUnavailable: {
    AlertStatus.processing,
    AlertStatus.expired,
  },
  AlertStatus.lowConfidence: {
    AlertStatus.expired,
  },
  AlertStatus.acknowledged: {},
  AlertStatus.dismissed: {},
  AlertStatus.noMatch: {},
  AlertStatus.unsupportedDocument: {},
  AlertStatus.expired: {},
};

class IllegalAlertTransition implements Exception {
  const IllegalAlertTransition(this.from, this.to);

  final AlertStatus from;
  final AlertStatus to;

  @override
  String toString() =>
      'IllegalAlertTransition: ${from.name} cannot become ${to.name}';
}

/// Where in the document the match was found, for the viewer to highlight.
class DocumentRegion {
  const DocumentRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Fractions of the page, not pixels. A bounding box in pixels is unusable
  /// after the viewer scales the page to the screen, and storing the scale
  /// alongside it would mean two facts that can disagree.
  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, double> toJson() =>
      {'l': left, 't': top, 'w': width, 'h': height};

  static DocumentRegion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final l = (raw['l'] as num?)?.toDouble();
    final t = (raw['t'] as num?)?.toDouble();
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    if (l == null || t == null || w == null || h == null) return null;
    return DocumentRegion(left: l, top: t, width: w, height: h);
  }
}

class KeywordAlert {
  const KeywordAlert({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.attachmentId,
    required this.recipientUserId,
    required this.keywordRuleId,
    required this.sourceDocumentHash,
    required this.processingVersion,
    required this.status,
    required this.priorityLevel,
    required this.detectedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.matchType,
    this.confidence,
    this.matchedText,
    this.contextText,
    this.documentPage,
    this.documentRegion,
    this.processingSource = ProcessingSource.local,
    this.retryCount = 0,
    this.acknowledgedAt,
    this.dismissedAt,
    this.failureReason,
    this.suppressedByDailyCap = false,
  });

  /// Derived from the alert's identity, so it is the same id every time the
  /// same document is processed against the same rule. See [deriveId].
  final String id;

  final String conversationId;
  final String messageId;
  final String attachmentId;
  final String recipientUserId;
  final String keywordRuleId;

  /// Content hash of the document version that was processed. Two purposes:
  /// it makes the identity above deterministic, and it detects the case where
  /// the same attachment id now points at different bytes, which should be
  /// re-processed rather than deduplicated away.
  final String sourceDocumentHash;

  /// Bumped when the extraction or matching pipeline changes in a way that
  /// could produce a different result. A document processed under an older
  /// version is eligible for reprocessing; one processed under this version is
  /// not (§3.5, §8.2 "only once per processing version").
  final int processingVersion;

  final AlertStatus status;

  /// Copied from the rule at detection time rather than read through the rule
  /// later, because the user may re-prioritise a rule afterwards and the alert
  /// should keep the urgency it was raised with.
  final KeywordPriority priorityLevel;

  final MatchType? matchType;
  final double? confidence;

  /// The literal text from the document that matched — not the rule's keyword.
  /// They differ under fuzzy and regex matching, and the document's own words
  /// are what make the alert legible.
  final String? matchedText;

  /// A short window of surrounding text. Deliberately short: §4.5 says store
  /// minimal derived metadata, never the full extracted text, and a snippet
  /// wide enough to be useful is also wide enough to leak the document.
  final String? contextText;

  final int? documentPage;
  final DocumentRegion? documentRegion;
  final ProcessingSource processingSource;
  final int retryCount;

  final DateTime detectedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 48 hours after detection (§4.5). History is a working memory, not an
  /// archive — an alert nobody acted on in two days is stale, and keeping
  /// derived document metadata indefinitely is exactly the accumulation the
  /// data-minimisation principle forbids.
  final DateTime expiresAt;

  final DateTime? acknowledgedAt;
  final DateTime? dismissedAt;

  /// Why processing failed, for the failure UX (§5.8). A code, not a sentence,
  /// so it can be localized.
  final String? failureReason;

  /// The rule's daily cap was already spent when this fired. The alert is
  /// still recorded — §1.3 says excess matches are logged, not discarded —
  /// it simply does not interrupt.
  final bool suppressedByDailyCap;

  static const retentionWindow = Duration(hours: 48);
  static const maxRetries = 3;

  /// Deterministic identity (§4.3).
  ///
  /// Every duplicate-alert path the spec lists — WebSocket reconnect, retry,
  /// duplicate push, restart, worker retry, timeout, re-upload — collapses to
  /// the same question: is this the same rule, applied to the same bytes, by
  /// the same pipeline? If so it is the same alert, and writing it twice is a
  /// primary-key conflict rather than a second row.
  ///
  /// The document hash is what makes re-upload safe: the same file uploaded
  /// again gets a new attachment id but the same bytes, and the conversation
  /// and message pin it to one place in one thread.
  static String deriveId({
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String keywordRuleId,
    required String sourceDocumentHash,
    required int processingVersion,
  }) {
    final material = [
      conversationId,
      messageId,
      attachmentId,
      keywordRuleId,
      sourceDocumentHash,
      processingVersion.toString(),
    ].join('|');
    return 'al_${sha256.convert(utf8.encode(material)).toString().substring(0, 32)}';
  }

  bool get isExpired => status == AlertStatus.expired;

  bool get canRetry =>
      retryCount < maxRetries &&
      (status == AlertStatus.processingFailed ||
          status == AlertStatus.ocrUnavailable);

  /// Moves to [next], or throws [IllegalAlertTransition].
  ///
  /// Throwing rather than returning null is deliberate: an illegal transition
  /// is a bug in the caller, and a silently ignored one leaves an alert
  /// wedged in a state the UI will keep showing.
  KeywordAlert transitionTo(
    AlertStatus next, {
    required DateTime now,
    String? failureReason,
    bool incrementRetry = false,
  }) {
    if (status == next) return this;
    if (!status.canTransitionTo(next)) {
      throw IllegalAlertTransition(status, next);
    }
    return copyWith(
      status: next,
      updatedAt: now,
      acknowledgedAt:
          next == AlertStatus.acknowledged ? (acknowledgedAt ?? now) : null,
      dismissedAt: next == AlertStatus.dismissed ? (dismissedAt ?? now) : null,
      failureReason: failureReason,
      // A retry that gets under way clears the reason the last attempt gave.
      // Leaving it would make a document currently being processed still
      // report the error it has moved past.
      clearFailureReason: next == AlertStatus.processing,
      retryCount: incrementRetry ? retryCount + 1 : null,
    );
  }

  /// Expires the alert if its retention window has passed, otherwise returns
  /// it unchanged.
  ///
  /// Applied on read as well as by the sweeper, so an alert cannot be shown
  /// past its expiry just because the app was closed when the sweep was due.
  KeywordAlert expireIfDue(DateTime now) {
    if (status.isTerminal || !now.isAfter(expiresAt)) return this;
    return transitionTo(AlertStatus.expired, now: now);
  }

  KeywordAlert copyWith({
    AlertStatus? status,
    KeywordPriority? priorityLevel,
    MatchType? matchType,
    double? confidence,
    String? matchedText,
    String? contextText,
    int? documentPage,
    DocumentRegion? documentRegion,
    ProcessingSource? processingSource,
    int? retryCount,
    DateTime? updatedAt,
    DateTime? acknowledgedAt,
    DateTime? dismissedAt,
    String? failureReason,
    bool clearFailureReason = false,
    bool? suppressedByDailyCap,
  }) =>
      KeywordAlert(
        id: id,
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        recipientUserId: recipientUserId,
        keywordRuleId: keywordRuleId,
        sourceDocumentHash: sourceDocumentHash,
        processingVersion: processingVersion,
        status: status ?? this.status,
        priorityLevel: priorityLevel ?? this.priorityLevel,
        matchType: matchType ?? this.matchType,
        confidence: confidence ?? this.confidence,
        matchedText: matchedText ?? this.matchedText,
        contextText: contextText ?? this.contextText,
        documentPage: documentPage ?? this.documentPage,
        documentRegion: documentRegion ?? this.documentRegion,
        processingSource: processingSource ?? this.processingSource,
        retryCount: retryCount ?? this.retryCount,
        detectedAt: detectedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        expiresAt: expiresAt,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
        dismissedAt: dismissedAt ?? this.dismissedAt,
        failureReason:
            clearFailureReason ? null : (failureReason ?? this.failureReason),
        suppressedByDailyCap: suppressedByDailyCap ?? this.suppressedByDailyCap,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'conversation_id': conversationId,
        'message_id': messageId,
        'attachment_id': attachmentId,
        'recipient_user_id': recipientUserId,
        'keyword_rule_id': keywordRuleId,
        'source_document_hash': sourceDocumentHash,
        'processing_version': processingVersion,
        'status': status.name,
        'priority_level': priorityLevel.name,
        'match_type': matchType?.name,
        'confidence': confidence,
        'matched_text': matchedText,
        'context_text': contextText,
        'document_page': documentPage,
        'document_region':
            documentRegion == null ? null : jsonEncode(documentRegion!.toJson()),
        'processing_source': processingSource.name,
        'retry_count': retryCount,
        'detected_at': detectedAt.toUtc().millisecondsSinceEpoch,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
        'acknowledged_at': acknowledgedAt?.toUtc().millisecondsSinceEpoch,
        'dismissed_at': dismissedAt?.toUtc().millisecondsSinceEpoch,
        'failure_reason': failureReason,
        'suppressed_by_cap': suppressedByDailyCap ? 1 : 0,
      };

  static KeywordAlert fromRow(Map<String, Object?> r) {
    DateTime at(String key) => DateTime.fromMillisecondsSinceEpoch(
          r[key] as int,
          isUtc: true,
        );
    DateTime? maybeAt(String key) => r[key] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r[key] as int, isUtc: true);

    Object? region;
    final rawRegion = r['document_region'];
    if (rawRegion is String && rawRegion.isNotEmpty) {
      try {
        region = jsonDecode(rawRegion);
      } catch (_) {
        // A corrupt box costs the highlight, not the alert.
        region = null;
      }
    }

    return KeywordAlert(
      id: r['id'] as String,
      conversationId: r['conversation_id'] as String,
      messageId: r['message_id'] as String,
      attachmentId: r['attachment_id'] as String,
      recipientUserId: r['recipient_user_id'] as String,
      keywordRuleId: r['keyword_rule_id'] as String,
      sourceDocumentHash: r['source_document_hash'] as String,
      processingVersion: r['processing_version'] as int? ?? 1,
      status: AlertStatus.fromName(r['status'] as String?),
      priorityLevel: KeywordPriority.fromName(r['priority_level'] as String?),
      matchType: r['match_type'] == null
          ? null
          : MatchType.fromName(r['match_type'] as String?),
      confidence: (r['confidence'] as num?)?.toDouble(),
      matchedText: r['matched_text'] as String?,
      contextText: r['context_text'] as String?,
      documentPage: r['document_page'] as int?,
      documentRegion: DocumentRegion.fromJson(region),
      processingSource:
          ProcessingSource.fromName(r['processing_source'] as String?),
      retryCount: r['retry_count'] as int? ?? 0,
      detectedAt: at('detected_at'),
      createdAt: at('created_at'),
      updatedAt: at('updated_at'),
      expiresAt: at('expires_at'),
      acknowledgedAt: maybeAt('acknowledged_at'),
      dismissedAt: maybeAt('dismissed_at'),
      failureReason: r['failure_reason'] as String?,
      suppressedByDailyCap: (r['suppressed_by_cap'] as int? ?? 0) == 1,
    );
  }

  @override
  bool operator ==(Object other) => other is KeywordAlert && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ticker and history ordering (§4.6).
///
/// Critical first regardless of age, then priority, then newest. Ordering is
/// the *only* thing priority does — it never lowers the confidence needed to
/// alert and never widens who can see a rule.
int compareAlertsForPresentation(KeywordAlert a, KeywordAlert b) {
  final byPriority = b.priorityLevel.rank.compareTo(a.priorityLevel.rank);
  if (byPriority != 0) return byPriority;
  return b.detectedAt.compareTo(a.detectedAt);
}
