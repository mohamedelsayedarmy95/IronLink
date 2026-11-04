import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';

/// An alert's value comes from the fact that its lifecycle is enforced rather
/// than merely intended. These pin the transitions that must not happen —
/// resurrecting an acknowledged alert, un-expiring an expired one — because
/// those are what a duplicate push or a replayed WebSocket frame would do.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  KeywordAlert alertAt(AlertStatus status, {DateTime? detected}) => KeywordAlert(
        id: 'al_test',
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'u1',
        keywordRuleId: 'kw_1',
        sourceDocumentHash: 'h1',
        processingVersion: 1,
        status: status,
        priorityLevel: KeywordPriority.medium,
        detectedAt: detected ?? t0,
        createdAt: detected ?? t0,
        updatedAt: detected ?? t0,
        expiresAt: (detected ?? t0).add(KeywordAlert.retentionWindow),
      );

  group('the happy path', () {
    test('runs from pending through to acknowledged', () {
      var alert = alertAt(AlertStatus.pendingProcessing);
      for (final next in [
        AlertStatus.processing,
        AlertStatus.matchDetected,
        AlertStatus.alertCreated,
        AlertStatus.alertPresented,
        AlertStatus.documentOpened,
        AlertStatus.acknowledged,
      ]) {
        alert = alert.transitionTo(next, now: t0);
        expect(alert.status, next);
      }
      expect(alert.acknowledgedAt, isNotNull);
      expect(alert.status.isTerminal, isTrue);
    });

    test('a document with nothing in it ends at noMatch, not silence', () {
      final alert = alertAt(AlertStatus.processing)
          .transitionTo(AlertStatus.noMatch, now: t0);
      expect(alert.status.isTerminal, isTrue);
      expect(alert.status.isMatch, isFalse);
    });

    test('acknowledgement straight from a push skips the ticker', () {
      // The user can act on a notification without the ticker ever drawing a
      // frame, so alertCreated → acknowledged has to be legal.
      final alert = alertAt(AlertStatus.alertCreated)
          .transitionTo(AlertStatus.acknowledged, now: t0);
      expect(alert.status, AlertStatus.acknowledged);
    });
  });

  group('transitions that must be impossible', () {
    test('an acknowledged alert cannot become outstanding again', () {
      final acked = alertAt(AlertStatus.acknowledged);
      for (final next in [
        AlertStatus.alertCreated,
        AlertStatus.alertPresented,
        AlertStatus.documentOpened,
        AlertStatus.processing,
      ]) {
        expect(
          () => acked.transitionTo(next, now: t0),
          throwsA(isA<IllegalAlertTransition>()),
          reason: 'acknowledged → ${next.name} would resurrect a handled alert',
        );
      }
    });

    test('an expired alert cannot come back', () {
      final expired = alertAt(AlertStatus.expired);
      for (final next in AlertStatus.values) {
        if (next == AlertStatus.expired) continue;
        expect(
          () => expired.transitionTo(next, now: t0),
          throwsA(isA<IllegalAlertTransition>()),
        );
      }
    });

    test('an alert cannot be created before anything was detected', () {
      expect(
        () => alertAt(AlertStatus.processing)
            .transitionTo(AlertStatus.alertCreated, now: t0),
        throwsA(isA<IllegalAlertTransition>()),
      );
    });

    test('a dismissed alert stays dismissed', () {
      expect(alertAt(AlertStatus.dismissed).status.isTerminal, isTrue);
    });

    test('every terminal state really is terminal', () {
      const terminal = {
        AlertStatus.acknowledged,
        AlertStatus.dismissed,
        AlertStatus.noMatch,
        AlertStatus.unsupportedDocument,
        AlertStatus.expired,
      };
      for (final status in AlertStatus.values) {
        expect(status.isTerminal, terminal.contains(status),
            reason: '${status.name} terminality');
      }
    });

    test('re-entering the same state is a no-op, not a throw', () {
      // Two surfaces can present the same alert; the second should not crash.
      final alert = alertAt(AlertStatus.alertPresented);
      expect(
        alert.transitionTo(AlertStatus.alertPresented, now: t0).status,
        AlertStatus.alertPresented,
      );
    });
  });

  group('failure and retry', () {
    test('a failed extraction is retried until the cap, then stops', () {
      var alert = alertAt(AlertStatus.processing);
      var attempts = 0;

      // Drive the loop off canRetry rather than a counted range, so the test
      // measures the property the pipeline will actually branch on.
      while (true) {
        alert = alert.transitionTo(
          AlertStatus.processingFailed,
          now: t0,
          failureReason: 'decode_failed',
          incrementRetry: true,
        );
        attempts++;
        if (!alert.canRetry) break;
        alert = alert.transitionTo(AlertStatus.processing, now: t0);
        expect(attempts, lessThanOrEqualTo(KeywordAlert.maxRetries),
            reason: 'the loop must terminate');
      }

      expect(attempts, KeywordAlert.maxRetries);
      expect(alert.retryCount, KeywordAlert.maxRetries);
      expect(alert.failureReason, 'decode_failed');
    });

    test('starting a retry clears the reason the last attempt gave', () {
      final failed = alertAt(AlertStatus.processing).transitionTo(
        AlertStatus.processingFailed,
        now: t0,
        failureReason: 'ocr_unavailable',
      );
      expect(failed.failureReason, 'ocr_unavailable');
      expect(
        failed.transitionTo(AlertStatus.processing, now: t0).failureReason,
        isNull,
      );
    });

    test('an unsupported document is not retried', () {
      expect(alertAt(AlertStatus.unsupportedDocument).canRetry, isFalse);
      expect(alertAt(AlertStatus.unsupportedDocument).status.isTerminal, isTrue);
    });

    test('a low-confidence result is recorded but never presented', () {
      final low = alertAt(AlertStatus.processing)
          .transitionTo(AlertStatus.lowConfidence, now: t0);
      expect(low.status.isMatch, isFalse);
      expect(
        () => low.transitionTo(AlertStatus.alertCreated, now: t0),
        throwsA(isA<IllegalAlertTransition>()),
      );
    });
  });

  group('expiry', () {
    test('expires exactly 48 hours after detection', () {
      final alert = alertAt(AlertStatus.alertPresented);
      expect(alert.expiresAt.difference(alert.detectedAt),
          const Duration(hours: 48));

      expect(
        alert.expireIfDue(t0.add(const Duration(hours: 47, minutes: 59))).status,
        AlertStatus.alertPresented,
      );
      expect(
        alert.expireIfDue(t0.add(const Duration(hours: 48, minutes: 1))).status,
        AlertStatus.expired,
      );
    });

    test('an already-acknowledged alert is not expired out from under itself', () {
      final acked = alertAt(AlertStatus.acknowledged);
      expect(
        acked.expireIfDue(t0.add(const Duration(days: 30))).status,
        AlertStatus.acknowledged,
      );
    });
  });

  group('presentation ordering (§4.6)', () {
    KeywordAlert withPriority(KeywordPriority p, DateTime at) =>
        alertAt(AlertStatus.alertCreated, detected: at)
            .copyWith(priorityLevel: p);

    test('critical outranks a more recent lower-priority alert', () {
      final critical = withPriority(KeywordPriority.critical, t0);
      final recentLow = withPriority(
        KeywordPriority.low,
        t0.add(const Duration(hours: 5)),
      );
      final ordered = [recentLow, critical]..sort(compareAlertsForPresentation);
      expect(ordered.first.priorityLevel, KeywordPriority.critical);
    });

    test('within one priority, newest leads', () {
      final older = withPriority(KeywordPriority.high, t0);
      final newer = withPriority(
        KeywordPriority.high,
        t0.add(const Duration(hours: 1)),
      );
      final ordered = [older, newer]..sort(compareAlertsForPresentation);
      expect(ordered.first.detectedAt, newer.detectedAt);
    });

    test('priority never changes what counts as a match', () {
      // Ordering only — §4.6 is explicit that priority must not lower the
      // confidence bar or widen visibility.
      for (final p in KeywordPriority.values) {
        expect(alertAt(AlertStatus.lowConfidence).copyWith(priorityLevel: p)
            .status.isMatch, isFalse);
      }
    });
  });
}
