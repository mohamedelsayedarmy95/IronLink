import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/domain/processing_job.dart';

/// The job is where a document turns into alerts. What it does with a rule
/// that is over its daily cap, and which of several matches gets to interrupt,
/// are decisions the user feels directly — so they are pinned here rather than
/// left to whichever screen happens to render the result.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  String normalize(String s) => s.trim().toLowerCase();

  KeywordRule ruleFor(
    String keyword, {
    KeywordPriority priority = KeywordPriority.medium,
    int? cap,
  }) =>
      KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: keyword,
        normalize: normalize,
        now: t0,
        priority: priority,
        maxAlertsPerDay: cap,
      );

  DocumentProcessingJob job({String documentHash = 'h1'}) =>
      DocumentProcessingJob(
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'u1',
        sourceDocumentHash: documentHash,
        processingVersion: 1,
        status: JobStatus.running,
        startedAt: t0,
      );

  DocumentMatch matchOn(KeywordRule rule, {double confidence = 0.97}) =>
      DocumentMatch(
        rule: rule,
        matchType: MatchType.exact,
        confidence: confidence,
        matchedText: rule.displayRepresentation,
        contextText: 'the ${rule.displayRepresentation} is attached',
        documentPage: 2,
      );

  group('turning a match into an alert', () {
    test('carries the context the alert needs to be legible', () {
      // §4.4: never just "Keyword found."
      final alert = job().alertFor(
        matchOn(ruleFor('contract')),
        now: t0,
        alertsRaisedToday: 0,
      );

      expect(alert.status, AlertStatus.alertCreated);
      expect(alert.matchedText, 'contract');
      expect(alert.contextText, contains('contract'));
      expect(alert.documentPage, 2);
      expect(alert.confidence, 0.97);
    });

    test('freezes the rule priority at detection time', () {
      // The user may re-prioritise the rule tomorrow; this alert keeps the
      // urgency it was actually raised with.
      final alert = job().alertFor(
        matchOn(ruleFor('contract', priority: KeywordPriority.critical)),
        now: t0,
        alertsRaisedToday: 0,
      );
      expect(alert.priorityLevel, KeywordPriority.critical);
    });

    test('expires 48 hours from detection, not from upload', () {
      final detected = t0.add(const Duration(hours: 6));
      final alert = job().alertFor(
        matchOn(ruleFor('contract')),
        now: detected,
        alertsRaisedToday: 0,
      );
      expect(alert.expiresAt, detected.add(const Duration(hours: 48)));
    });

    test('records where the processing happened', () {
      // §7.2: the user is entitled to know where *this* document was read,
      // and the setting can change afterwards.
      final alert = job().alertFor(
        matchOn(ruleFor('contract')),
        now: t0,
        alertsRaisedToday: 0,
      );
      expect(alert.processingSource, ProcessingSource.local);
    });
  });

  group('the daily cap', () {
    test('marks an over-cap match instead of discarding it', () {
      // §1.3: excess matches are logged, not thrown away — otherwise history
      // quietly lies about what was in a document.
      final alert = job().alertFor(
        matchOn(ruleFor('contract', cap: 5)),
        now: t0,
        alertsRaisedToday: 5,
      );
      expect(alert.suppressedByDailyCap, isTrue);
      expect(alert.status, AlertStatus.alertCreated);
    });

    test('leaves a match under the cap alone', () {
      final alert = job().alertFor(
        matchOn(ruleFor('contract', cap: 5)),
        now: t0,
        alertsRaisedToday: 4,
      );
      expect(alert.suppressedByDailyCap, isFalse);
    });

    test('a rule with no cap is never suppressed', () {
      final alert = job().alertFor(
        matchOn(ruleFor('contract')),
        now: t0,
        alertsRaisedToday: 9999,
      );
      expect(alert.suppressedByDailyCap, isFalse);
    });
  });

  group('which alert interrupts (§5.5)', () {
    KeywordAlert alertFrom(KeywordRule rule, {int today = 0}) =>
        job(documentHash: rule.id).alertFor(
          matchOn(rule),
          now: t0,
          alertsRaisedToday: today,
        );

    test('the highest priority match leads', () {
      final lead = DocumentProcessingJob.leadAlert([
        alertFrom(ruleFor('invoice', priority: KeywordPriority.low)),
        alertFrom(ruleFor('contract', priority: KeywordPriority.critical)),
        alertFrom(ruleFor('receipt', priority: KeywordPriority.medium)),
      ]);
      expect(lead!.matchedText, 'contract');
    });

    test('a suppressed alert never leads', () {
      final lead = DocumentProcessingJob.leadAlert([
        alertFrom(ruleFor('contract', priority: KeywordPriority.critical, cap: 1),
            today: 5),
        alertFrom(ruleFor('invoice', priority: KeywordPriority.low)),
      ]);
      expect(lead!.matchedText, 'invoice');
    });

    test('nothing leads when every match is suppressed', () {
      final lead = DocumentProcessingJob.leadAlert([
        alertFrom(ruleFor('contract', cap: 1), today: 5),
      ]);
      expect(lead, isNull);
    });

    test('nothing leads when nothing matched', () {
      expect(DocumentProcessingJob.leadAlert(const []), isNull);
    });
  });

  group('job outcomes', () {
    test('a clean document is a distinct outcome from an unchecked one', () {
      final done = job().to(JobStatus.completedNoMatch, now: t0);
      expect(done.status.isTerminal, isTrue);
      expect(done.finishedAt, t0);
      expect(JobStatus.pending.isTerminal, isFalse);
    });

    test('a failure keeps its reason and is not terminal', () {
      // Not terminal, because §8.4 allows bounded retries.
      final failed =
          job().to(JobStatus.failed, now: t0, failureReason: 'decode_failed');
      expect(failed.status.isTerminal, isFalse);
      expect(failed.failureReason, 'decode_failed');
      expect(failed.finishedAt, t0);
    });

    test('an already-processed document is skipped, not re-extracted', () {
      // §8.2: only once per processing version. The saving is the extraction,
      // which is the expensive part.
      expect(JobStatus.skippedAlreadyProcessed.isTerminal, isTrue);
    });

    test('active states are the ones worth showing progress for', () {
      // §8.3: "Checking document…" must be honest about when it is true.
      expect(JobStatus.running.isActive, isTrue);
      expect(JobStatus.waitingForNetwork.isActive, isTrue);
      expect(JobStatus.completedNoMatch.isActive, isFalse);
      expect(JobStatus.failed.isActive, isFalse);
    });
  });
}
