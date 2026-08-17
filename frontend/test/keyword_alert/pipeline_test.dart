import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/domain/processing_job.dart';
import 'package:ironlink/features/keyword_alert/keyword_alert_pipeline.dart';
import 'package:ironlink/features/keyword_alert/local/alert_store.dart';
import 'package:ironlink/features/keyword_alert/matching/keyword_matcher.dart';
import 'package:ironlink/features/keyword_alert/ocr/extracted_document.dart';
import 'package:ironlink/features/keyword_alert/ocr/ocr_mode.dart';
import 'package:ironlink/features/keyword_alert/ocr/preflight.dart';
import 'package:ironlink/features/keyword_alert/ocr/text_extractor.dart';
import 'package:ironlink/features/keyword_alert/text/text_normalizer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The pipeline is where the cheap refusals have to come before the expensive
/// work, or none of the performance promises in §8 mean anything. These tests
/// check the ordering as directly as the outcomes — an extractor that counts
/// its own invocations is the only honest way to prove a document never
/// reached it.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final t0 = DateTime.utc(2026, 8, 16, 10);

  late AlertStore store;
  late _CountingExtractor extractor;

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    store = await AlertStore.open(path: '${await getDatabasesPath()}/test_pipeline.db');
    await store.clear();
    extractor = _CountingExtractor();
  });

  tearDown(() async => store.close());

  KeywordRule rule(String keyword, {String scope = 'c1', int? cap}) =>
      KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: scope,
        displayRepresentation: keyword,
        normalize: const TextNormalizer().normalizeToString,
        now: t0,
        maxAlertsPerDay: cap,
      );

  KeywordAlertPipeline pipeline({
    bool cloudEnabled = false,
    TextExtractor? using,
    DateTime? clock,
  }) =>
      KeywordAlertPipeline(
        store: store,
        extractors: TextExtractorRegistry([using ?? extractor]),
        cloudEnabled: cloudEnabled,
        now: () => clock ?? t0,
      );

  Uint8List text(String body) => Uint8List.fromList(body.codeUnits);

  Future<PipelineOutcome> run(
    KeywordAlertPipeline p,
    String body, {
    String messageId = 'm1',
    String attachmentId = 'a1',
    bool networkAvailable = true,
  }) =>
      p.process(
        bytes: text(body),
        conversationId: 'c1',
        messageId: messageId,
        attachmentId: attachmentId,
        recipientUserId: 'u1',
        networkAvailable: networkAvailable,
      );

  group('cheap refusals come first', () {
    test('no rules means the document is never read', () {
      // Reading a document to discover nobody asked to watch it is pure
      // waste, and on a low-tier phone it is waste the user can feel.
      return run(pipeline(), 'the contract is attached').then((outcome) {
        expect(outcome.job.status, JobStatus.skippedNoRules);
        expect(extractor.calls, 0);
      });
    });

    test('a document pre-flight refuses never reaches a decoder', () async {
      await store.saveRule(rule('contract'));
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 0)]);

      final outcome = await pipeline().process(
        bytes: zip,
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'u1',
      );

      expect(outcome.job.status, JobStatus.unsupportedDocument);
      expect(outcome.rejection, PreflightRejection.unsupportedType);
      expect(extractor.calls, 0);
    });

    test('an already-processed document is not extracted again', () async {
      // This is where §8.2 saves the battery it promises — skipping the
      // insert would still have paid for the OCR.
      await store.saveRule(rule('contract'));
      await run(pipeline(), 'the contract is attached');
      expect(extractor.calls, 1);

      await run(pipeline(), 'the contract is attached');
      expect(extractor.calls, 1);
    });

    test('a rule added after the first pass gets its own look', () async {
      // It genuinely has not seen this document, so skipping would mean the
      // new rule silently never applies to anything already received.
      await store.saveRule(rule('contract'));
      await run(pipeline(), 'the contract and the invoice');
      await store.saveRule(rule('invoice'));

      final outcome = await run(pipeline(), 'the contract and the invoice');
      expect(extractor.calls, 2);
      expect(outcome.alerts, hasLength(1));
      expect(outcome.alerts.single.matchedText, 'invoice');
    });
  });

  group('a document that matches', () {
    setUp(() async => store.saveRule(rule('contract')));

    test('produces a recorded, outstanding alert', () async {
      final outcome = await run(pipeline(), 'please sign the contract today');

      expect(outcome.job.status, JobStatus.completedWithMatches);
      expect(outcome.alerts, hasLength(1));
      expect(outcome.alerts.single.status, AlertStatus.alertCreated);
      expect(await store.outstanding(now: t0), hasLength(1));
    });

    test('carries context, not just the keyword', () async {
      final outcome = await run(pipeline(), 'please sign the contract today');
      final alert = outcome.alerts.single;

      expect(alert.matchedText, 'contract');
      expect(alert.contextText, contains('sign'));
      expect(alert.confidence, greaterThan(0.85));
    });

    test('names the pipeline version that produced it', () async {
      final outcome = await run(pipeline(), 'the contract');
      expect(outcome.alerts.single.processingVersion, keywordPipelineVersion);
    });

    test('records that it was processed locally', () async {
      final outcome = await run(pipeline(), 'the contract');
      expect(outcome.alerts.single.processingSource, ProcessingSource.local);
    });
  });

  group('a document that does not match', () {
    test('is a clean result, not a failure', () async {
      // "Checked, nothing found" is a more reassuring fact than "never
      // checked", and the two must not look the same.
      await store.saveRule(rule('contract'));
      final outcome = await run(pipeline(), 'lunch tomorrow at one');

      expect(outcome.job.status, JobStatus.completedNoMatch);
      expect(outcome.foundSomething, isFalse);
    });

    test('a photograph with no words is not an error either', () async {
      await store.saveRule(rule('contract'));
      final outcome = await run(pipeline(), '   ');
      expect(outcome.job.status, JobStatus.completedNoMatch);
    });
  });

  group('confidence gating (§2.5)', () {
    test('a low-confidence reading raises no alert', () async {
      // Precision over volume: a filter the user learns to ignore has failed
      // completely.
      await store.saveRule(rule('contract'));
      final outcome = await run(
        pipeline(using: _CountingExtractor(confidence: 0.2)),
        'the contract is attached',
      );

      expect(outcome.job.status, JobStatus.completedNoMatch);
      expect(await store.alertCount(), 0);
    });

    test('a confident reading does', () async {
      await store.saveRule(rule('contract'));
      final outcome = await run(
        pipeline(using: _CountingExtractor(confidence: 0.95)),
        'the contract is attached',
      );
      expect(outcome.alerts, hasLength(1));
    });
  });

  group('several rules on one document', () {
    test('each gets its own alert', () async {
      await store.saveRule(rule('contract'));
      await store.saveRule(rule('invoice'));

      final outcome = await run(pipeline(), 'the contract and the invoice');
      expect(outcome.alerts, hasLength(2));
    });

    test('only one of them leads', () async {
      await store.saveRule(rule('contract'));
      await store.saveRule(rule('invoice'));

      final outcome = await run(pipeline(), 'the contract and the invoice');
      expect(outcome.leadAlert, isNotNull);
      expect(outcome.alerts, contains(outcome.leadAlert));
    });

    test('a capped rule still records but does not lead', () async {
      await store.saveRule(rule('contract', cap: 1));
      await run(pipeline(), 'contract one', attachmentId: 'a1');
      final second = await run(pipeline(), 'contract two', attachmentId: 'a2');

      expect(second.alerts.single.suppressedByDailyCap, isTrue);
      expect(second.leadAlert, isNull);
    });
  });

  group('extraction failures', () {
    setUp(() async => store.saveRule(rule('contract')));

    test('a failed local read does not reach for the cloud', () async {
      // §3.3: no automatic cloud upload. A slow or broken local engine is not
      // consent to send the document somewhere else.
      final outcome = await run(
        pipeline(using: const _FailingExtractor(ExtractionFailure.unreadable)),
        'the contract',
      );
      expect(outcome.job.status, JobStatus.failed);
      expect(outcome.job.processingSource, ProcessingSource.local);
    });

    test('waits for a network only when cloud is enabled and offline',
        () async {
      final outcome = await run(
        pipeline(
          cloudEnabled: true,
          using: const _FailingExtractor(ExtractionFailure.unreadable),
        ),
        'the contract',
        networkAvailable: false,
      );
      expect(outcome.job.status, JobStatus.waitingForNetwork);
    });

    test('with cloud off, being offline changes nothing', () async {
      final outcome = await run(
        pipeline(using: const _FailingExtractor(ExtractionFailure.unreadable)),
        'the contract',
        networkAvailable: false,
      );
      expect(outcome.job.status, JobStatus.failed);
    });

    test('an engine that throws something unexpected does not crash the app',
        () async {
      final outcome = await run(
        pipeline(using: const _ExplodingExtractor()),
        'the contract',
      );
      expect(outcome.job.status, JobStatus.failed);
      expect(outcome.job.failureReason, 'engine_error');
    });

    test('no engine for this kind of document is reported honestly', () async {
      final outcome = await KeywordAlertPipeline(
        store: store,
        extractors: const TextExtractorRegistry([]),
        now: () => t0,
      ).process(
        bytes: text('the contract'),
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'u1',
      );
      expect(outcome.job.status, JobStatus.ocrUnavailable);
    });
  });

  group('document identity', () {
    test('the same bytes hash the same however they arrived', () {
      expect(
        KeywordAlertPipeline.hashDocument(text('hello')),
        KeywordAlertPipeline.hashDocument(text('hello')),
      );
    });

    test('different bytes hash differently', () {
      expect(
        KeywordAlertPipeline.hashDocument(text('hello')),
        isNot(KeywordAlertPipeline.hashDocument(text('hellp'))),
      );
    });

    test('a re-upload under a new attachment id is still one alert', () async {
      // Same bytes, same message, new identifier — the hash is what makes
      // that recognisable.
      await store.saveRule(rule('contract'));
      await run(pipeline(), 'the contract', attachmentId: 'a1');
      await run(pipeline(), 'the contract', attachmentId: 'a1');

      expect(await store.alertCount(), 1);
    });
  });

  group('what an alert is allowed to keep (§4.5, P-6)', () {
    test('a real document leaves only a bounded snippet behind', () async {
      // The promise is boundedness: whatever the document's size, what
      // survives into storage is a short window around the match. Without
      // that, forty alerts would reconstruct the file.
      await store.saveRule(rule('contract'));
      // The distinctive words sit far from the match on purpose. Text
      // immediately beside a hit is context, and keeping it is the point;
      // text at the other end of the document is what must not survive.
      final body = 'OPENING_MARKER ${'filler ' * 60}'
          'the contract is attached. '
          '${'filler ' * 60} CLOSING_MARKER';
      await run(pipeline(), body);

      final stored = (await store.history(now: t0)).single;
      expect(stored.contextText, isNotNull);
      expect(stored.contextText, contains('contract'));
      expect(stored.contextText, isNot(contains('OPENING_MARKER')));
      expect(stored.contextText, isNot(contains('CLOSING_MARKER')));
      expect(stored.contextText!.length, lessThan(body.length / 5));
    });

    test('the snippet is capped in absolute terms, not relative ones', () async {
      // A ratio would let a large document keep a large snippet. The cap is a
      // number of characters, so the ceiling is the same for a note and for a
      // hundred-page report.
      await store.saveRule(rule('contract'));
      await run(pipeline(), '${'word ' * 500}contract${' word' * 500}');

      final stored = (await store.history(now: t0)).single;
      expect(stored.contextText!.length,
          lessThanOrEqualTo(const KeywordMatcher().maxContextLength + 2));
    });

    test('nothing but the snippet and the match reaches the database', () async {
      // The extracted text exists as a local variable for one matching pass.
      // If it were persisted anywhere, this row would be where it showed up.
      await store.saveRule(rule('contract'));
      const marker = 'ZZUNIQUEMARKERZZ';
      await run(pipeline(), '$marker ${'filler ' * 60}contract here');

      final stored = (await store.history(now: t0)).single;
      final everythingStored = stored.toRow().values.join(' ');
      expect(everythingStored, isNot(contains(marker)));
    });
  });

  group('the local/cloud decision matrix (§3.3)', () {
    test('cloud disabled means local only, always', () {
      for (final network in [true, false]) {
        for (final local in [true, false]) {
          final decision = OcrModeDecision.decide(
            cloudEnabled: false,
            localAvailable: local,
            localSucceeded: false,
            networkAvailable: network,
          );
          expect(decision.outcome, isNot(OcrModeOutcome.cloud));
        }
      }
    });

    test('a successful local read never invokes the cloud', () {
      // Not to save money — to avoid a transmission that turned out to be
      // unnecessary.
      final decision = OcrModeDecision.decide(
        cloudEnabled: true,
        localAvailable: true,
        localSucceeded: true,
        networkAvailable: true,
      );
      expect(decision.outcome, OcrModeOutcome.local);
    });

    test('cloud is reached only after local failed, with consent and network',
        () {
      final decision = OcrModeDecision.decide(
        cloudEnabled: true,
        localAvailable: true,
        localSucceeded: false,
        networkAvailable: true,
      );
      expect(decision.outcome, OcrModeOutcome.cloud);
      expect(decision.source, ProcessingSource.cloud);
    });

    test('offline with cloud enabled waits rather than dropping the request',
        () {
      final decision = OcrModeDecision.decide(
        cloudEnabled: true,
        localAvailable: true,
        localSucceeded: false,
        networkAvailable: false,
      );
      expect(decision.outcome, OcrModeOutcome.waitForNetwork);
    });

    test('the retry ladder is finite and ends in an admission', () {
      var step = LocalRetryStep.first;
      var count = 1;
      while (step.next != null) {
        step = step.next!;
        count++;
      }
      expect(count, 3);
      expect(step, LocalRetryStep.alternateConfiguration);
    });
  });
}

/// An extractor that reads plain text and counts how often it was asked to.
///
/// The count is the point: proving a document never reached the engine cannot
/// be done by looking at the result, only by asking the engine.
class _CountingExtractor implements TextExtractor {
  _CountingExtractor({this.confidence = 1.0});

  final double confidence;
  int calls = 0;

  @override
  String get name => 'counting-test-extractor';

  @override
  bool handles(DocumentKind kind) => true;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    calls++;
    final body = String.fromCharCodes(bytes);
    return ExtractedDocument(
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: body,
          source: PageTextSource.opticalRecognition,
          words: [
            for (final m in RegExp(r'\S+').allMatches(body))
              RecognizedWord(
                start: m.start,
                end: m.end,
                confidence: confidence,
              ),
          ],
        ),
      ],
      engine: name,
    );
  }
}

class _FailingExtractor implements TextExtractor {
  const _FailingExtractor(this.failure);

  final ExtractionFailure failure;

  @override
  String get name => 'failing-test-extractor';

  @override
  bool handles(DocumentKind kind) => true;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async =>
      throw ExtractionException(failure);
}

class _ExplodingExtractor implements TextExtractor {
  const _ExplodingExtractor();

  @override
  String get name => 'exploding-test-extractor';

  @override
  bool handles(DocumentKind kind) => true;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async =>
      throw StateError('the engine fell over');
}
