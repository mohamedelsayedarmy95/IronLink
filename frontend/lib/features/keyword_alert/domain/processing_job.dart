import 'keyword_alert.dart';
import 'keyword_rule.dart';

/// One document, checked once, against every rule that watches its
/// conversation.
///
/// The alert state machine tracks what happened to a single match. This tracks
/// what happened to the document — which is a different question, and the one
/// the UI actually asks when it shows "Checking document…" (§8.3) or has to
/// explain that a file could not be read (§5.8). A document with no matches
/// produces no alerts at all, so without a job there would be nothing to
/// record the fact that it was checked and came back clean.
///
/// The extraction engine is deliberately absent. This file decides *whether*
/// to process, and turns matches into alerts; Phase 2 supplies the text.

enum JobStatus {
  pending,

  /// Cloud extraction only (§8.5). Local processing never waits for a network,
  /// and switching silently between the two is forbidden.
  waitingForNetwork,
  running,

  /// Checked, nothing matched. A distinct and more reassuring fact than
  /// "never checked".
  completedNoMatch,
  completedWithMatches,

  /// This exact document was already checked under this pipeline version, so
  /// the expensive part was skipped (§8.2).
  skippedAlreadyProcessed,

  /// No rule watches this conversation, so there was nothing to look for.
  skippedNoRules,

  failed,
  unsupportedDocument,
  ocrUnavailable;

  bool get isTerminal => const {
        JobStatus.completedNoMatch,
        JobStatus.completedWithMatches,
        JobStatus.skippedAlreadyProcessed,
        JobStatus.skippedNoRules,
        JobStatus.unsupportedDocument,
      }.contains(this);

  /// Whether the user should be shown honest in-progress feedback.
  bool get isActive =>
      this == JobStatus.pending ||
      this == JobStatus.running ||
      this == JobStatus.waitingForNetwork;
}

/// What the extractor found, before anything is persisted.
///
/// A value object on purpose: §4.5 and P-6 forbid storing the extracted text,
/// so this exists only long enough to be turned into alerts and then dropped.
/// Giving it a `toRow` would be the easiest possible way to accidentally build
/// a searchable archive of everyone's documents on the device.
class DocumentMatch {
  const DocumentMatch({
    required this.rule,
    required this.matchType,
    required this.confidence,
    required this.matchedText,
    required this.contextText,
    this.documentPage,
    this.documentRegion,
  });

  final KeywordRule rule;
  final MatchType matchType;
  final double confidence;
  final String matchedText;
  final String contextText;
  final int? documentPage;
  final DocumentRegion? documentRegion;
}

/// A document being considered, and the decisions made about it.
class DocumentProcessingJob {
  const DocumentProcessingJob({
    required this.conversationId,
    required this.messageId,
    required this.attachmentId,
    required this.recipientUserId,
    required this.sourceDocumentHash,
    required this.processingVersion,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.failureReason,
    this.processingSource = ProcessingSource.local,
  });

  final String conversationId;
  final String messageId;
  final String attachmentId;
  final String recipientUserId;

  /// Content hash of the bytes actually examined — not of the attachment
  /// identifier. Two files with the same name are two documents; the same file
  /// re-uploaded is one.
  final String sourceDocumentHash;

  final int processingVersion;
  final JobStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? failureReason;
  final ProcessingSource processingSource;

  DocumentProcessingJob to(
    JobStatus next, {
    required DateTime now,
    String? failureReason,
  }) =>
      DocumentProcessingJob(
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        recipientUserId: recipientUserId,
        sourceDocumentHash: sourceDocumentHash,
        processingVersion: processingVersion,
        status: next,
        startedAt: startedAt,
        finishedAt: next.isTerminal || next == JobStatus.failed ? now : null,
        failureReason: failureReason ?? this.failureReason,
        processingSource: processingSource,
      );

  /// Turns one match into the alert it warrants.
  ///
  /// [alertsRaisedToday] is the count for this rule over the last rolling 24
  /// hours, supplied by the store. A rule over its cap still produces an
  /// alert — §1.3 says excess matches are logged, not discarded — it is simply
  /// marked so the ticker and the notification layer leave it alone. Dropping
  /// it instead would mean the history quietly lies about what was in a
  /// document.
  KeywordAlert alertFor(
    DocumentMatch match, {
    required DateTime now,
    required int alertsRaisedToday,
  }) {
    final capped = match.rule.maxAlertsPerDay;
    return KeywordAlert(
      id: KeywordAlert.deriveId(
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        keywordRuleId: match.rule.id,
        sourceDocumentHash: sourceDocumentHash,
        processingVersion: processingVersion,
      ),
      conversationId: conversationId,
      messageId: messageId,
      attachmentId: attachmentId,
      recipientUserId: recipientUserId,
      keywordRuleId: match.rule.id,
      sourceDocumentHash: sourceDocumentHash,
      processingVersion: processingVersion,
      status: AlertStatus.alertCreated,
      priorityLevel: match.rule.priority,
      matchType: match.matchType,
      confidence: match.confidence,
      matchedText: match.matchedText,
      contextText: match.contextText,
      documentPage: match.documentPage,
      documentRegion: match.documentRegion,
      processingSource: processingSource,
      detectedAt: now,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(KeywordAlert.retentionWindow),
      suppressedByDailyCap: capped != null && alertsRaisedToday >= capped,
    );
  }

  /// The single alert that should lead, when one document trips several rules
  /// (§5.5). The rest stay in history; only one of them interrupts.
  static KeywordAlert? leadAlert(List<KeywordAlert> alerts) {
    final surfaceable =
        alerts.where((a) => !a.suppressedByDailyCap).toList(growable: false);
    if (surfaceable.isEmpty) return null;
    final sorted = [...surfaceable]..sort(compareAlertsForPresentation);
    return sorted.first;
  }
}
