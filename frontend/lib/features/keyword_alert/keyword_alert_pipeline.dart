import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'domain/keyword_alert.dart';
import 'domain/keyword_rule.dart';
import 'domain/processing_job.dart';
import 'local/alert_store.dart';
import 'matching/keyword_matcher.dart';
import 'ocr/extracted_document.dart';
import 'ocr/ocr_mode.dart';
import 'ocr/preflight.dart';
import 'ocr/text_extractor.dart';

/// One document, from bytes to alerts.
///
/// This is the only place the phases meet, and the order it runs them in is
/// the substance of the feature rather than plumbing:
///
///   pre-flight → already-processed? → extract → match → score → record
///
/// The cheap refusals come first. A document that pre-flight turns away never
/// reaches a decoder; a document already checked under this pipeline version
/// never reaches an OCR engine at all, which is where §8.2's "only once per
/// processing version" actually saves the battery it promises to.
///
/// Nothing here writes extracted text anywhere. It exists as a local variable
/// for the length of one matching pass and is then gone.

/// Bumped whenever extraction or matching changes in a way that could produce
/// a different result for the same bytes.
///
/// This is what makes reprocessing possible without duplicating alerts: a
/// document checked under version 1 is eligible for a second look under
/// version 2, and its old alerts remain distinct rather than colliding
/// (§3.5, §4.3).
const int keywordPipelineVersion = 1;

/// What running a document produced.
class PipelineOutcome {
  const PipelineOutcome({
    required this.job,
    this.alerts = const [],
    this.leadAlert,
    this.rejection,
  });

  final DocumentProcessingJob job;

  /// Every alert recorded, including any suppressed by a rule's daily cap.
  final List<KeywordAlert> alerts;

  /// The one that should interrupt, if any (§5.5).
  final KeywordAlert? leadAlert;

  /// Set when pre-flight refused the document.
  final PreflightRejection? rejection;

  bool get foundSomething => alerts.isNotEmpty;
}

class KeywordAlertPipeline {
  KeywordAlertPipeline({
    required this.store,
    required this.extractors,
    this.matcher = const KeywordMatcher(),
    this.preflight = const Preflight(),
    this.limits = PreflightLimits.standard,
    this.cloudEnabled = false,
    this.now,
  });

  final AlertStore store;
  final TextExtractorRegistry extractors;
  final KeywordMatcher matcher;
  final Preflight preflight;
  final PreflightLimits limits;

  /// Off unless the user turned it on. Passed in rather than read from a
  /// setting here, so the one place that reads the setting is the one place
  /// that can get it wrong.
  final bool cloudEnabled;

  /// Injectable clock. Retention, expiry, and the rolling daily cap are all
  /// time-dependent, and a pipeline that could only be tested in real time
  /// could not be tested at all.
  final DateTime Function()? now;

  DateTime get _now => (now?.call() ?? DateTime.now()).toUtc();

  /// Runs one attachment against the rules watching its conversation.
  ///
  /// [bytes] is the decrypted document. It arrives decrypted because the
  /// client has already decrypted it to render it — this pipeline never
  /// touches the network and never sees a key.
  Future<PipelineOutcome> process({
    required Uint8List bytes,
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String recipientUserId,
    String? declaredMimeType,
    bool networkAvailable = true,
  }) async {
    final startedAt = _now;
    final documentHash = hashDocument(bytes);

    DocumentProcessingJob job(JobStatus status, {String? failureReason}) =>
        DocumentProcessingJob(
          conversationId: conversationId,
          messageId: messageId,
          attachmentId: attachmentId,
          recipientUserId: recipientUserId,
          sourceDocumentHash: documentHash,
          processingVersion: keywordPipelineVersion,
          status: status,
          startedAt: startedAt,
          finishedAt: _now,
          failureReason: failureReason,
        );

    // Rules first, because the cheapest possible outcome is having nothing to
    // look for. Reading a document to discover no one asked to watch it is
    // pure waste, and on a low-tier phone it is waste the user can feel.
    final rules = await store.rulesFor(conversationId, onlyEnabled: true);
    if (rules.isEmpty) {
      return PipelineOutcome(job: job(JobStatus.skippedNoRules));
    }

    // Then the checks that cost a few dozen bytes of header (§3.4).
    final inspection =
        preflight.inspect(bytes, declaredMimeType: declaredMimeType);
    if (!inspection.accepted) {
      return PipelineOutcome(
        job: job(
          inspection.rejection == PreflightRejection.malformed ||
                  inspection.rejection == PreflightRejection.unsupportedType
              ? JobStatus.unsupportedDocument
              : JobStatus.failed,
          failureReason: inspection.rejection?.name,
        ),
        rejection: inspection.rejection,
      );
    }

    // Then the question that skips extraction entirely. Checked per rule,
    // because a rule added since the last pass genuinely has not seen this
    // document — only when every rule has already been applied is there
    // nothing left to do.
    final unprocessed = <KeywordRule>[];
    for (final rule in rules) {
      final seen = await store.alreadyProcessed(
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        keywordRuleId: rule.id,
        sourceDocumentHash: documentHash,
        processingVersion: keywordPipelineVersion,
      );
      if (!seen) unprocessed.add(rule);
    }
    if (unprocessed.isEmpty) {
      return PipelineOutcome(job: job(JobStatus.skippedAlreadyProcessed));
    }

    final extractor = extractors.forKind(inspection.kind);
    if (extractor == null) {
      final decision = OcrModeDecision.decide(
        cloudEnabled: cloudEnabled,
        localAvailable: false,
        localSucceeded: false,
        networkAvailable: networkAvailable,
      );
      return PipelineOutcome(
        job: job(
          decision.outcome == OcrModeOutcome.waitForNetwork
              ? JobStatus.waitingForNetwork
              : JobStatus.ocrUnavailable,
          failureReason: decision.reason,
        ),
      );
    }

    final ExtractedDocument document;
    try {
      document = await extractor.extract(
        bytes,
        preflight: inspection,
        limits: limits,
      );
    } on ExtractionException catch (e) {
      final decision = OcrModeDecision.decide(
        cloudEnabled: cloudEnabled,
        localAvailable: true,
        localSucceeded: false,
        networkAvailable: networkAvailable,
      );
      return PipelineOutcome(
        job: job(
          decision.outcome == OcrModeOutcome.waitForNetwork
              ? JobStatus.waitingForNetwork
              : JobStatus.failed,
          failureReason: e.failure.name,
        ),
      );
    } catch (_) {
      // An engine that threw something unexpected is a failure of the engine,
      // not of the document, and it must not take the app with it.
      return PipelineOutcome(
        job: job(JobStatus.failed, failureReason: 'engine_error'),
      );
    }

    if (document.isEmpty) {
      // A document with no text is not a failure. A photograph of a landscape
      // genuinely contains no words, and reporting that as an error would
      // teach the user to ignore real errors.
      return PipelineOutcome(job: job(JobStatus.completedNoMatch));
    }

    final matches = matcher.match(rules: unprocessed, document: document);
    // Only matches the user should actually be told about. §2.5: never alert
    // on LOW-CONFIDENCE without safeguards, and precision over volume.
    final worthAlerting = matches
        .where((m) => m.breakdown.level != ConfidenceLevel.low)
        .toList(growable: false);

    if (worthAlerting.isEmpty) {
      return PipelineOutcome(job: job(JobStatus.completedNoMatch));
    }

    final running = DocumentProcessingJob(
      conversationId: conversationId,
      messageId: messageId,
      attachmentId: attachmentId,
      recipientUserId: recipientUserId,
      sourceDocumentHash: documentHash,
      processingVersion: keywordPipelineVersion,
      status: JobStatus.running,
      startedAt: startedAt,
      processingSource: ProcessingSource.local,
    );

    final recorded = <KeywordAlert>[];
    for (final match in worthAlerting) {
      final raisedToday = await store.alertsInLastDay(match.rule.id, _now);
      final alert = running.alertFor(
        match.toDocumentMatch(),
        now: _now,
        alertsRaisedToday: raisedToday,
      );
      // record() returns whatever is stored, so a duplicate that slipped
      // through the check above — two passes racing on one document — yields
      // the original rather than a second alert.
      recorded.add(await store.record(alert));
    }

    return PipelineOutcome(
      job: job(JobStatus.completedWithMatches),
      alerts: recorded,
      leadAlert: DocumentProcessingJob.leadAlert(recorded),
    );
  }

  /// The content hash that gives an alert its identity.
  ///
  /// Of the bytes, not of the attachment identifier: two files with the same
  /// name are two documents, and the same file re-uploaded is one. That is
  /// what makes a re-upload safe to deduplicate while an edited document with
  /// a recycled identifier still gets re-checked.
  static String hashDocument(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  /// Convenience for a caller that has text rather than a file — a message
  /// body, say, rather than an attachment.
  static String hashText(String text) =>
      sha256.convert(utf8.encode(text)).toString();
}
