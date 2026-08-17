import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/ocr/extracted_document.dart';
import 'package:ironlink/features/keyword_alert/ocr/image_text_extractor.dart';
import 'package:ironlink/features/keyword_alert/ocr/preflight.dart';
import 'package:ironlink/features/keyword_alert/ocr/text_extractor.dart';

/// How an image gets routed between OCR engines.
///
/// There is no second engine today — no Arabic OCR binding builds against this
/// project's Android Gradle Plugin, which CI established rather than assumed.
/// These tests cover the routing anyway, with fakes standing in for both
/// engines, because that routing is what a working Arabic engine plugs into and
/// it should be correct before it is needed rather than after.
void main() {
  const preflight = PreflightResult.accepted(
    kind: DocumentKind.image,
    width: 1000,
    height: 2000,
    detectedMimeType: 'image/jpeg',
  );

  group('which engine reads an image', () {
    Uint8List bytes() => Uint8List.fromList(List.filled(64, 7));

    test('the fast engine alone, when its result is usable', () async {
      // Running two OCR engines over every photograph doubles the most
      // expensive thing this feature does, to improve documents the first
      // engine already read.
      final latin = _FakeExtractor(text: 'please sign the contract today');
      final arabic = _FakeExtractor(text: 'unused');
      final composite = ImageTextExtractor(primary: latin, arabic: arabic);

      await composite.extract(bytes(), preflight: preflight);

      expect(latin.calls, 1);
      expect(arabic.calls, 0);
    });

    test('falls through to Arabic when the first pass reads almost nothing',
        () async {
      // ML Kit does not fail on an Arabic page — it succeeds and returns a
      // scattering of marks. So the trigger has to be the result, not an error.
      final latin = _FakeExtractor(text: 'i');
      final arabic = _FakeExtractor(text: 'تقرير المراجعة النهائي');
      final composite = ImageTextExtractor(primary: latin, arabic: arabic);

      final document = await composite.extract(bytes(), preflight: preflight);

      expect(arabic.calls, 1);
      expect(document.pages.single.text, contains('تقرير'));
    });

    test('falls through when the first pass was read unconfidently', () async {
      final latin =
          _FakeExtractor(text: 'a longer stretch of text', confidence: 0.2);
      final arabic = _FakeExtractor(text: 'تقرير المراجعة');
      final composite = ImageTextExtractor(primary: latin, arabic: arabic);

      await composite.extract(bytes(), preflight: preflight);
      expect(arabic.calls, 1);
    });

    test('keeps whichever engine read more of the page', () async {
      // Length rather than confidence: a Latin recognizer given Arabic is often
      // very sure about the few marks it did recognise, and that confidence is
      // about the wrong thing.
      final latin = _FakeExtractor(text: 'ii', confidence: 0.99);
      final arabic = _FakeExtractor(text: 'تقرير المراجعة النهائي', confidence: 0.7);
      final composite = ImageTextExtractor(primary: latin, arabic: arabic);

      final document = await composite.extract(bytes(), preflight: preflight);
      expect(document.pages.single.text, contains('تقرير'));
    });

    test('a failed first pass still reaches Arabic', () async {
      final latin = _FakeExtractor(failure: ExtractionFailure.unreadable);
      final arabic = _FakeExtractor(text: 'تقرير المراجعة النهائي');
      final composite = ImageTextExtractor(primary: latin, arabic: arabic);

      final document = await composite.extract(bytes(), preflight: preflight);
      expect(document.pages.single.text, contains('تقرير'));
    });

    test('with no Arabic engine, a weak result is returned rather than an error',
        () async {
      // A scattering of low-confidence words is still true, and the confidence
      // layer will decline to alert on it. An exception would be a stronger
      // claim than the situation supports.
      final latin = _FakeExtractor(text: 'i', confidence: 0.2);
      final composite = ImageTextExtractor(primary: latin, arabic: null);

      final document = await composite.extract(bytes(), preflight: preflight);
      expect(document.pages.single.text.trim(), 'i');
    });

    test('with no Arabic engine and a failed first pass, it says so', () async {
      final latin = _FakeExtractor(failure: ExtractionFailure.unreadable);
      final composite = ImageTextExtractor(primary: latin, arabic: null);

      expect(
        () => composite.extract(bytes(), preflight: preflight),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('the name reports which engines are actually present', () async {
      // The Security Center shows this, so it must not claim an engine the
      // installation does not have.
      final withArabic = ImageTextExtractor(
        primary: _FakeExtractor(text: 'x'),
        arabic: _FakeExtractor(text: 'y'),
      );
      final without = ImageTextExtractor(
        primary: _FakeExtractor(text: 'x'),
        arabic: null,
      );

      expect(withArabic.name, contains('+'));
      expect(without.name, isNot(contains('+')));
    });
  });
}

class _FakeExtractor implements TextExtractor {
  _FakeExtractor({this.text, this.failure, this.confidence = 0.95});

  final String? text;
  final ExtractionFailure? failure;
  final double confidence;
  int calls = 0;

  @override
  String get name => 'fake';

  @override
  bool handles(DocumentKind kind) => kind == DocumentKind.image;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    calls++;
    if (failure != null) throw ExtractionException(failure!);
    final body = text!;
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
