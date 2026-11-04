import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/processing_job.dart';
import 'package:ironlink/features/keyword_alert/keyword_feature_flags.dart';
import 'package:ironlink/features/keyword_alert/keyword_telemetry.dart';
import 'package:ironlink/features/keyword_alert/matching/keyword_matcher.dart';
import 'package:ironlink/features/keyword_alert/ocr/extracted_document.dart';

/// §10.2 forbids document contents, OCR plaintext, private keywords and
/// message text in telemetry. That is easy to state and easy to break: one
/// well-meaning debugging line ships a watchlist to an analytics vendor and
/// looks unremarkable in review. These tests hold the shape of the events
/// rather than trusting the discipline.
void main() {
  group('telemetry cannot describe what it read', () {
    test('a processing event carries counts and codes, never text', () {
      const event = DocumentProcessedEvent(
        outcome: JobStatus.completedWithMatches,
        source: ProcessingSource.local,
        textSource: PageTextSource.nativeTextLayer,
        duration: Duration(milliseconds: 820),
        pageCount: 12,
        matchCount: 2,
        deviceClass: TelemetryDeviceClass.high,
        retryCount: 0,
      );

      final json = event.toJson();
      for (final value in json.values) {
        expect(
          value,
          anyOf(isA<int>(), isA<String>(), isA<bool>()),
        );
      }
      // Every string present is an enum name, never free text.
      const enumerated = {
        'outcome',
        'source',
        'text_source',
        'device_class',
        'failure_reason',
      };
      for (final entry in json.entries) {
        if (entry.value is String) {
          expect(enumerated, contains(entry.key));
        }
      }
    });

    test('it counts matches without naming them', () {
      // The count is a performance signal; the identity would be the user's
      // watchlist.
      const event = DocumentProcessedEvent(
        outcome: JobStatus.completedWithMatches,
        source: ProcessingSource.local,
        textSource: PageTextSource.opticalRecognition,
        duration: Duration(seconds: 3),
        pageCount: 1,
        matchCount: 4,
        deviceClass: TelemetryDeviceClass.low,
        retryCount: 1,
      );

      expect(event.toJson()['match_count'], 4);
      expect(event.toJson().containsKey('matched_text'), isFalse);
      expect(event.toJson().containsKey('keyword'), isFalse);
      expect(event.toJson().containsKey('context'), isFalse);
    });

    test('there is no free-form payload to slip a string into', () {
      const event = DocumentProcessedEvent(
        outcome: JobStatus.failed,
        source: ProcessingSource.local,
        textSource: PageTextSource.opticalRecognition,
        duration: Duration(seconds: 1),
        pageCount: 1,
        matchCount: 0,
        deviceClass: TelemetryDeviceClass.medium,
        retryCount: 0,
        failureReason: 'unreadable',
      );

      for (final value in event.toJson().values) {
        expect(value, isNot(isA<Map>()));
        expect(value, isNot(isA<List>()));
      }
    });

    test('confidence is reported as a band, not a score', () {
      // The exact number is meaningless on a dashboard, and shipping it
      // invites tuning against a population average instead of measured
      // precision.
      expect(AlertLifecycleEvent.bandFor(0.97), 'high');
      expect(AlertLifecycleEvent.bandFor(0.60), 'medium');
      expect(AlertLifecycleEvent.bandFor(0.20), 'low');
      expect(AlertLifecycleEvent.bandFor(null), 'unknown');

      const event = AlertLifecycleEvent(
        status: AlertStatus.acknowledged,
        priority: 'high',
        matchType: MatchType.exact,
        confidenceBand: 'high',
      );
      expect(event.toJson()['confidence_band'], 'high');
      expect(event.toJson().containsKey('confidence'), isFalse);
    });

    test('feedback reports correctness without the match', () {
      const event = MatchFeedbackEvent(
        wasCorrect: false,
        matchType: MatchType.fuzzy,
        confidenceBand: 'medium',
      );
      final json = event.toJson();
      expect(json['was_correct'], isFalse);
      expect(json.keys.toSet(),
          {'was_correct', 'match_type', 'confidence_band'});
    });

    test('the default sink emits nothing', () {
      // Telemetry nobody configured should be absent, not buffered.
      const sink = NullTelemetrySink();
      expect(
        () => sink.documentProcessed(const DocumentProcessedEvent(
          outcome: JobStatus.completedNoMatch,
          source: ProcessingSource.local,
          textSource: PageTextSource.nativeTextLayer,
          duration: Duration.zero,
          pageCount: 1,
          matchCount: 0,
          deviceClass: TelemetryDeviceClass.medium,
          retryCount: 0,
        )),
        returnsNormally,
      );
    });

    test('a recording sink keeps only what the events allow', () {
      final sink = RecordingTelemetrySink();
      sink.matchFeedback(const MatchFeedbackEvent(
        wasCorrect: true,
        matchType: MatchType.exact,
        confidenceBand: 'high',
      ));

      expect(sink.events.single['event'], 'match_feedback');
      expect(sink.events.single.containsKey('keyword'), isFalse);
    });
  });

  group('guardrails halt a rollout by themselves (§10.4)', () {
    const healthy = GuardrailCheck(
      falsePositiveRate: 0.01,
      dismissalRate: 0.05,
      crashFreeRate: 0.999,
      p95ProcessingSeconds: 12,
    );

    test('a healthy release passes', () {
      expect(healthy.passes, isTrue);
      expect(healthy.breaches, isEmpty);
    });

    test('too many false positives is a breach', () {
      const check = GuardrailCheck(
        falsePositiveRate: 0.05,
        dismissalRate: 0.05,
        crashFreeRate: 0.999,
        p95ProcessingSeconds: 12,
      );
      expect(check.passes, isFalse);
      expect(check.breaches, contains('false_positive_rate'));
    });

    test('a high dismissal rate is a breach, because it means noise', () {
      const check = GuardrailCheck(
        falsePositiveRate: 0.01,
        dismissalRate: 0.4,
        crashFreeRate: 0.999,
        p95ProcessingSeconds: 12,
      );
      expect(check.breaches, contains('dismissal_rate'));
    });

    test('crashes and slow processing are breaches too', () {
      const check = GuardrailCheck(
        falsePositiveRate: 0.01,
        dismissalRate: 0.05,
        crashFreeRate: 0.97,
        p95ProcessingSeconds: 90,
      );
      expect(check.breaches, containsAll(['crash_free_rate', 'processing_p95']));
    });

    test('the thresholds match §10.3', () {
      expect(GuardrailCheck.maxFalsePositiveRate, 0.02);
      expect(GuardrailCheck.maxDismissalRate, 0.10);
      expect(GuardrailCheck.minCrashFreeRate, 0.995);
      expect(GuardrailCheck.maxP95Seconds, 30.0);
    });
  });

  group('feature flags (§9.4)', () {
    test('everything unfinished ships off', () {
      // A flag that defaults on is not a flag, it is a release.
      const flags = KeywordFeatureFlags.production;
      expect(flags.asMap().values.any((on) => on), isFalse);
      expect(flags.anyExperimentalEnabled, isFalse);
    });

    test('the registry lists every flag the class defines', () {
      // Otherwise a new capability could be added without appearing in the
      // inventory the Security Center reads.
      expect(
        KeywordFeatureFlags.production.asMap().keys.toSet(),
        KeywordFeatureFlags.experimental,
      );
    });

    test('fuzzy matching is off in the matcher by default', () {
      // The flag and the default have to agree; two sources of truth about
      // whether an experimental path is live is one too many.
      expect(const KeywordMatcher().fuzzyEnabled, isFalse);
      expect(KeywordFeatureFlags.production.fuzzyMatching, isFalse);
    });

    test('turning a flag on changes nothing that has to be unwound (R12)', () {
      // No flag here controls storage. Disabling fuzzy stops new fuzzy
      // matches; the alerts it already raised remain valid alerts about real
      // documents, so there is no half-migrated state to revert.
      const on = KeywordFeatureFlags(fuzzyMatching: true);
      final off = on.copyWith(fuzzyMatching: false);

      expect(off.asMap(), KeywordFeatureFlags.production.asMap());
    });

    test('an enabled experimental capability is reported honestly', () {
      const flags = KeywordFeatureFlags(cloudOcr: true);
      expect(flags.anyExperimentalEnabled, isTrue);
    });
  });
}
