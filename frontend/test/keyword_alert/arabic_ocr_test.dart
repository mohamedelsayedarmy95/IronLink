import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/matching/keyword_matcher.dart';
import 'package:ironlink/features/keyword_alert/ocr/extracted_document.dart';
import 'package:ironlink/features/keyword_alert/ocr/image_text_extractor.dart';
import 'package:ironlink/features/keyword_alert/ocr/preflight.dart';
import 'package:ironlink/features/keyword_alert/ocr/tesseract_text_extractor.dart';
import 'package:ironlink/features/keyword_alert/ocr/text_extractor.dart';
import 'package:ironlink/features/keyword_alert/text/text_normalizer.dart';

/// Arabic image OCR, which ML Kit cannot do at all.
///
/// The engine call itself is native and needs a device. Everything around it is
/// string handling and routing, and that is what these cover: parsing hOCR into
/// the same shape ML Kit produces, and the decision about which engine reads a
/// given image. Both are where a mistake would be silent.
void main() {
  const preflight = PreflightResult.accepted(
    kind: DocumentKind.image,
    width: 1000,
    height: 2000,
    detectedMimeType: 'image/jpeg',
  );

  /// A realistic hOCR fragment. Tesseract emits single quotes, this order of
  /// attributes, and `x_wconf` on a 0–100 scale.
  String hocrPage(List<(String, int, int, int, int, int)> words) {
    final spans = words.map((w) {
      final (text, left, top, right, bottom, conf) = w;
      return "<span class='ocrx_word' id='word_1_1' "
          "title='bbox $left $top $right $bottom; x_wconf $conf'>$text</span>";
    }).join('\n');
    return '''
<div class='ocr_page' id='page_1' title='image "x"; bbox 0 0 1000 2000'>
 <div class='ocr_carea' id='block_1_1'>
  <p class='ocr_par' dir='rtl'>
   <span class='ocr_line' id='line_1_1'>
$spans
   </span>
  </p>
 </div>
</div>''';
  }

  group('hOCR parsing', () {
    test('recovers Arabic words, in order', () {
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        hocrPage([
          ('تقرير', 700, 100, 900, 140, 91),
          ('المراجعة', 450, 100, 690, 140, 88),
          ('النهائي', 250, 100, 440, 140, 94),
        ]),
        preflight,
      );

      expect(document.pages, hasLength(1));
      expect(document.pages.single.text.trim(), 'تقرير المراجعة النهائي');
      expect(document.pages.single.words, hasLength(3));
    });

    test('carries the per-word confidence Tesseract reported', () {
      // Plain-text extraction would have thrown this away, and the confidence
      // score would have fallen back to page quality — scoring an Arabic match
      // more crudely than a Latin one for no reason but the output format.
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        hocrPage([('عقد', 700, 100, 900, 140, 42)]),
        preflight,
      );

      expect(document.pages.single.words.single.confidence, closeTo(0.42, 0.001));
    });

    test('a word with no reported confidence is treated as doubtful', () {
      // Inventing certainty is the one thing this layer must not do.
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        "<span class='ocrx_word' title='bbox 10 10 90 40'>عقد</span>",
        preflight,
      );
      expect(document.pages.single.words.single.confidence, 0.5);
    });

    test('converts bounding boxes to fractions of the page', () {
      // Pixels are unusable once the viewer scales the page to the screen.
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        hocrPage([('عقد', 250, 400, 750, 600, 90)]),
        preflight,
      );

      final region = document.pages.single.words.single.region!;
      expect(region.left, closeTo(0.25, 0.001));
      expect(region.top, closeTo(0.20, 0.001));
      expect(region.width, closeTo(0.50, 0.001));
      expect(region.height, closeTo(0.10, 0.001));
    });

    test('marks the page as optically recognised, not stated', () {
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        hocrPage([('عقد', 10, 10, 90, 40, 90)]),
        preflight,
      );
      expect(document.pages.single.source, PageTextSource.opticalRecognition);
      expect(document.engine, 'tesseract-ara');
    });

    test('low mean confidence lowers the page quality signal', () {
      const extractor = TesseractTextExtractor();
      final clean = extractor.parseHocrForTest(
        hocrPage([('عقد', 10, 10, 90, 40, 95)]),
        preflight,
      );
      final noisy = extractor.parseHocrForTest(
        hocrPage([('عقد', 10, 10, 90, 40, 35)]),
        preflight,
      );
      expect(noisy.pages.single.quality.score,
          lessThan(clean.pages.single.quality.score));
    });

    test('survives malformed markup without losing the page', () {
      // A regex over machine-generated hOCR should cost a bad word, not the
      // document.
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        "<span class='ocrx_word' title='bbox oops; x_wconf'>?</span>"
        "<span class='ocrx_word' title='bbox 10 10 90 40; x_wconf 90'>عقد</span>"
        '<span class=broken>',
        preflight,
      );
      expect(document.pages.single.text, contains('عقد'));
    });

    test('empty output is an empty document, not a crash', () {
      const extractor = TesseractTextExtractor();
      expect(
        extractor.parseHocrForTest('', preflight).isEmpty,
        isTrue,
      );
    });

    test('unescapes the entities Tesseract emits', () {
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        "<span class='ocrx_word' title='bbox 10 10 90 40; x_wconf 90'>"
        'R&amp;D</span>',
        preflight,
      );
      expect(document.pages.single.text.trim(), 'R&D');
    });
  });

  group('an Arabic document read this way still matches', () {
    test('end to end, from hOCR to a scored match', () {
      // The point of the whole exercise: an Arabic keyword matching an Arabic
      // document that arrived as a photograph. Before this engine existed, this
      // produced nothing at all.
      const extractor = TesseractTextExtractor();
      final document = extractor.parseHocrForTest(
        hocrPage([
          ('وقّع', 800, 100, 900, 140, 89),
          ('أحمد', 600, 100, 790, 140, 92),
          ('الشريف', 380, 100, 590, 140, 90),
        ]),
        preflight,
      );

      final rule = KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        // Typed with hamza; the document has it bare. Normalization is what
        // bridges that, and it only gets the chance because the text exists.
        displayRepresentation: 'أحمد',
        normalize: const TextNormalizer().normalizeToString,
        now: DateTime.utc(2026, 8, 17),
      );

      final hits = const KeywordMatcher()
          .match(rules: [rule], document: document);

      expect(hits, hasLength(1));
      expect(hits.single.matchedText, 'أحمد');
      expect(hits.single.region, isNotNull);
      expect(hits.single.breakdown.level, isNot(ConfidenceLevel.low));
    });
  });

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
