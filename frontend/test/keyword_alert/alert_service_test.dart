import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/bloc/alert_bloc.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/keyword_alert_pipeline.dart';
import 'package:ironlink/features/keyword_alert/keyword_alert_service.dart';
import 'package:ironlink/features/keyword_alert/local/alert_store.dart';
import 'package:ironlink/features/keyword_alert/ocr/extracted_document.dart';
import 'package:ironlink/features/keyword_alert/ocr/preflight.dart';
import 'package:ironlink/features/keyword_alert/ocr/text_extractor.dart';
import 'package:ironlink/features/keyword_alert/text/text_normalizer.dart';

/// The service exists because the widget cannot be trusted with the decision.
/// A list of photographs rebuilds constantly as it scrolls, and every rebuild
/// hands over the same bytes again — so what matters here is what the service
/// declines to do.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  late InMemoryAlertStore store;
  late AlertBloc bloc;
  late _CountingExtractor extractor;

  KeywordAlertService serviceFor({int maxQueueDepth = 32}) {
    return KeywordAlertService(
      store: store,
      bloc: bloc,
      maxQueueDepth: maxQueueDepth,
      pipeline: KeywordAlertPipeline(
        store: store,
        extractors: TextExtractorRegistry([extractor]),
        now: () => t0,
      ),
    );
  }

  KeywordRule ruleFor(String keyword, {String scope = 'c1'}) =>
      KeywordRule.create(
        ownerUserId: 'me',
        conversationScope: scope,
        displayRepresentation: keyword,
        normalize: const TextNormalizer().normalizeToString,
        now: t0,
      );

  Uint8List doc(String body) => Uint8List.fromList(body.codeUnits);

  setUp(() {
    store = InMemoryAlertStore();
    bloc = AlertBloc(store, now: () => t0);
    extractor = _CountingExtractor();
  });

  /// Lets the serial queue drain. The service returns immediately by design,
  /// so a test that asserted straight away would be asserting about nothing.
  Future<void> drain(KeywordAlertService service) async {
    for (var i = 0; i < 200 && !service.isIdle; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('what it refuses to read', () {
    test('a document the user sent themselves', () async {
      // They chose its contents; bringing it to their attention is noise.
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor();

      service.offer(
        bytes: doc('the contract is attached'),
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'me',
        isMine: true,
      );
      await drain(service);

      expect(extractor.calls, 0);
      expect(await store.alertCount(), 0);
    });

    test('anything in a secret chat', () async {
      // Nothing from a secret chat is written to this device, and an alert
      // about one would outlive the message it describes by 48 hours.
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor();

      service.offer(
        bytes: doc('the contract is attached'),
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'me',
        isSecret: true,
      );
      await drain(service);

      expect(extractor.calls, 0);
      expect(await store.alertCount(), 0);
    });

    test('the same attachment offered again by the next rebuild', () async {
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor();

      for (var i = 0; i < 10; i++) {
        service.offer(
          bytes: doc('the contract is attached'),
          conversationId: 'c1',
          messageId: 'm1',
          attachmentId: 'a1',
          recipientUserId: 'me',
        );
      }
      await drain(service);

      expect(extractor.calls, 1);
      expect(await store.alertCount(), 1);
    });
  });

  group('what it does read', () {
    test('a document from someone else, once', () async {
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor();

      service.offer(
        bytes: doc('please sign the contract today'),
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'me',
      );
      await drain(service);

      expect(extractor.calls, 1);
      final alerts = await store.history(now: t0);
      expect(alerts, hasLength(1));
      expect(alerts.single.matchedText, 'contract');
    });

    test('several distinct attachments, one at a time', () async {
      // Twenty concurrent OCR jobs on a phone is not a feature, it is a
      // thermal event. The counter proves they were serialized.
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor();

      for (var i = 0; i < 5; i++) {
        service.offer(
          bytes: doc('contract number $i'),
          conversationId: 'c1',
          messageId: 'm$i',
          attachmentId: 'a$i',
          recipientUserId: 'me',
        );
      }
      await drain(service);

      expect(extractor.calls, 5);
      expect(extractor.maxConcurrent, 1);
    });

    test('it tells the bloc, which re-reads rather than being told what',
        () async {
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor();

      service.offer(
        bytes: doc('the contract is attached'),
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'me',
      );
      await drain(service);
      // Polled rather than awaited on the stream: the bloc may well have
      // emitted before this line ran, and firstWhere would then wait for an
      // emission that already happened.
      for (var i = 0; i < 200 && bloc.state.outstanding.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(bloc.state.leadAlert?.matchedText, 'contract');
    });
  });

  group('back pressure', () {
    test('a runaway queue drops the oldest, not the newest', () async {
      // The document the user just scrolled to is the one they are looking
      // at. And an unbounded queue is a memory leak holding decrypted
      // documents.
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor(maxQueueDepth: 3);

      for (var i = 0; i < 20; i++) {
        service.offer(
          bytes: doc('contract $i'),
          conversationId: 'c1',
          messageId: 'm$i',
          attachmentId: 'a$i',
          recipientUserId: 'me',
        );
      }

      expect(service.queueDepth, lessThanOrEqualTo(3));
      await drain(service);
      expect(extractor.calls, lessThanOrEqualTo(5));
    });

    test('a dropped document can be offered again', () async {
      // Dropped is not the same as done — scrolling back to it must work.
      // Which ones got dropped depends on timing, so the test re-offers all
      // of them: the ones that were processed stay refused, and at least one
      // that was dropped must be accepted.
      await store.saveRule(ruleFor('contract'));
      final service = serviceFor(maxQueueDepth: 1);

      void offerAll() {
        for (var i = 0; i < 5; i++) {
          service.offer(
            bytes: doc('contract $i'),
            conversationId: 'c1',
            messageId: 'm$i',
            attachmentId: 'a$i',
            recipientUserId: 'me',
          );
        }
      }

      offerAll();
      await drain(service);
      final afterFirstPass = extractor.calls;
      expect(afterFirstPass, lessThan(5), reason: 'some must have been dropped');

      offerAll();
      await drain(service);

      expect(extractor.calls, greaterThan(afterFirstPass));
    });
  });

  group('failure is contained', () {
    test('an engine that throws does not take the chat with it', () async {
      await store.saveRule(ruleFor('contract'));
      final service = KeywordAlertService(
        store: store,
        bloc: bloc,
        pipeline: KeywordAlertPipeline(
          store: store,
          extractors: const TextExtractorRegistry([_ExplodingExtractor()]),
          now: () => t0,
        ),
      );

      expect(
        () => service.offer(
          bytes: doc('the contract is attached'),
          conversationId: 'c1',
          messageId: 'm1',
          attachmentId: 'a1',
          recipientUserId: 'me',
        ),
        returnsNormally,
      );
      await drain(service);
      expect(await store.alertCount(), 0);
    });

    test('a document that failed can be tried again when it is looked at',
        () async {
      // The bounded retry §8.4 asks for, driven by the user rather than a
      // timer — which is what keeps it from becoming the daemon §8.2 bans.
      await store.saveRule(ruleFor('contract'));
      final failing = _FlakyExtractor();
      final service = KeywordAlertService(
        store: store,
        bloc: bloc,
        pipeline: KeywordAlertPipeline(
          store: store,
          extractors: TextExtractorRegistry([failing]),
          now: () => t0,
        ),
      );

      void offer() => service.offer(
            bytes: doc('the contract is attached'),
            conversationId: 'c1',
            messageId: 'm1',
            attachmentId: 'a1',
            recipientUserId: 'me',
          );

      offer();
      await drain(service);
      expect(await store.alertCount(), 0);

      failing.shouldFail = false;
      offer();
      await drain(service);
      expect(await store.alertCount(), 1);
    });
  });

  test('signing out forgets what this session checked', () async {
    // The store is wiped elsewhere; without this the service would keep
    // claiming documents were handled for a user who has left.
    await store.saveRule(ruleFor('contract'));
    final service = serviceFor();

    service.offer(
      bytes: doc('the contract is attached'),
      conversationId: 'c1',
      messageId: 'm1',
      attachmentId: 'a1',
      recipientUserId: 'me',
    );
    await drain(service);
    expect(extractor.calls, 1);

    service.reset();
    await store.clear();
    await store.saveRule(ruleFor('contract'));

    service.offer(
      bytes: doc('the contract is attached'),
      conversationId: 'c1',
      messageId: 'm1',
      attachmentId: 'a1',
      recipientUserId: 'me',
    );
    await drain(service);
    expect(extractor.calls, 2);
  });
}

class _CountingExtractor implements TextExtractor {
  int calls = 0;
  int _active = 0;
  int maxConcurrent = 0;

  @override
  String get name => 'counting';

  @override
  bool handles(DocumentKind kind) => true;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    calls++;
    _active++;
    if (_active > maxConcurrent) maxConcurrent = _active;
    // A turn of the event loop, so overlapping calls would actually overlap
    // and the concurrency counter would notice.
    await Future<void>.delayed(Duration.zero);
    _active--;

    final body = String.fromCharCodes(bytes);
    return ExtractedDocument(
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: body,
          source: PageTextSource.nativeTextLayer,
          words: [
            for (final m in RegExp(r'\S+').allMatches(body))
              RecognizedWord(start: m.start, end: m.end, confidence: 1.0),
          ],
        ),
      ],
      engine: name,
    );
  }
}

class _ExplodingExtractor implements TextExtractor {
  const _ExplodingExtractor();

  @override
  String get name => 'exploding';

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

class _FlakyExtractor implements TextExtractor {
  bool shouldFail = true;

  @override
  String get name => 'flaky';

  @override
  bool handles(DocumentKind kind) => true;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    if (shouldFail) {
      throw const ExtractionException(ExtractionFailure.unreadable);
    }
    final body = String.fromCharCodes(bytes);
    return ExtractedDocument(
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: body,
          source: PageTextSource.nativeTextLayer,
          words: [
            for (final m in RegExp(r'\S+').allMatches(body))
              RecognizedWord(start: m.start, end: m.end, confidence: 1.0),
          ],
        ),
      ],
      engine: name,
    );
  }
}
