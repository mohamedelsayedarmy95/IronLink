import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/keyword_alert.dart' show DocumentRegion;
import 'extracted_document.dart';
import 'preflight.dart';
import 'text_extractor.dart';

/// Arabic text recognition for images, via Tesseract.
///
/// WHY THIS EXISTS AT ALL
///
/// ML Kit Text Recognition v2 ships five script models — latin, chinese,
/// devanagari, japanese, korean — and no Arabic. The master prompt's §3.6
/// recommends "ML Kit + Arabic model"; that model does not exist. In an
/// Arabic-first product, shipping ML Kit alone would have reproduced the exact
/// defect the Phase 0 audit opened with: a keyword feature that silently never
/// matches the primary language.
///
/// WHY TESSERACT AND NOT SOMETHING BETTER
///
/// Because the alternatives are worse here. Apple Vision handles Arabic well
/// and exists only on iOS. Google Cloud Vision handles it well and is a cloud
/// service, which §3.3 puts behind explicit consent and §10.3 treats a high
/// opt-in rate for as a privacy failure rather than adoption. Tesseract is the
/// only option that reads Arabic on an Android device without the document
/// leaving it.
///
/// WHAT IT COSTS, MEASURED RATHER THAN GUESSED
///
/// `tessdata_fast/ara.traineddata` is 1,432,056 bytes — 1.37 MB, bundled. The
/// standard variant is 2.38 MB and the best is 12 MB. Only Arabic is shipped:
/// ML Kit already covers Latin, and Tesseract's own English data is 22 MB for
/// no benefit.
///
/// The fast variant is integer-quantized, which matters more on a phone than
/// the accuracy it gives up — and what it gives up is recall, not precision,
/// because a weak reading arrives with low confidence and the pipeline drops
/// anything below MEDIUM before it can become an alert. If device measurement
/// shows recall short of target, swapping in the 2.38 MB standard model is a
/// one-file change. That is the tuning lever.
///
/// HONEST LIMITS
///
/// Tesseract reads printed Arabic on a reasonable scan competently and a
/// hand-held photograph of cursive text poorly. That is a property of the
/// engine, not of this wiring, and it is why the confidence layer exists: the
/// bad cases arrive as low-confidence output and are discarded rather than
/// surfaced. The failure mode is a missed match, which is the right direction
/// to fail in (P-2, precision over volume).
class TesseractTextExtractor implements TextExtractor {
  const TesseractTextExtractor({
    this.timeout = const Duration(seconds: 45),
  });

  /// Longer than ML Kit's ceiling because Tesseract is slower, and still
  /// bounded: §8.2 forbids a permanent OCR daemon, and a wedged extraction is
  /// one by accident.
  final Duration timeout;

  /// The language code, which is also the asset filename stem.
  static const language = 'ara';

  @override
  String get name => 'tesseract-$language';

  @override
  bool handles(DocumentKind kind) => kind == DocumentKind.image;

  /// Whether the model is actually present and usable on this device.
  ///
  /// Checked rather than assumed, and this is why the extractor needs no
  /// feature flag. A flag would be a claim about the build; this is a fact
  /// about the installation. If the asset failed to unpack, the registry
  /// reports no Arabic engine and the pipeline records OCR_UNAVAILABLE —
  /// which is true — instead of a stub returning empty text, which would tell
  /// the user a document was checked when it was not.
  static Future<bool> isAvailable() async {
    try {
      final path = await FlutterTesseractOcr.getTessdataPath();
      final model = File('$path/$language.traineddata');
      if (!await model.exists()) return false;
      // A truncated copy is worse than a missing one: it loads and then fails
      // mid-page. The real file is ~1.4 MB, so anything tiny is a bad unpack.
      return await model.length() > 500 * 1024;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/kw_ara_${DateTime.now().microsecondsSinceEpoch}.img',
    );

    try {
      await file.writeAsBytes(bytes, flush: true);

      final String hocr;
      try {
        // hOCR rather than plain text, because it carries a bounding box and a
        // per-word confidence for every word. Plain text would leave every
        // Arabic alert without a highlight and force the confidence score to
        // fall back to page quality — an Arabic match would be scored more
        // crudely than a Latin one, for no reason but the output format.
        hocr = await FlutterTesseractOcr.extractHocr(
          file.path,
          language: language,
          args: const {
            // Keep spacing between words, which the matcher tokenizes on.
            'preserve_interword_spaces': '1',
          },
        ).timeout(timeout);
      } on Object catch (e) {
        throw ExtractionException(
          e.toString().contains('TimeoutException')
              ? ExtractionFailure.timedOut
              : ExtractionFailure.unreadable,
          e.toString(),
        );
      }

      return _parseHocr(hocr, preflight);
    } finally {
      // Deleted whatever happened. The alternative is a plaintext copy of
      // someone's document left in a cache directory after an exception.
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {
        // Not worth failing the pass over; the OS clears this directory.
      }
    }
  }

  /// Word elements from hOCR.
  ///
  /// Matches `<span class='ocrx_word' ... title='bbox 1 2 3 4; x_wconf 96'>w</span>`,
  /// tolerating either quote style and any attribute order. Parsed with a
  /// regular expression rather than an XML parser on purpose: hOCR from
  /// Tesseract is machine-generated and regular, an XML parse of a large page
  /// costs a full tree, and a malformed fragment should cost that word rather
  /// than the document.
  static final _wordPattern = RegExp(
    r"""<span[^>]*class=['"]ocrx_word['"][^>]*title=['"]([^'"]*)['"][^>]*>(.*?)</span>""",
    dotAll: true,
  );
  static final _bboxPattern =
      RegExp(r'bbox\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)');
  static final _confPattern = RegExp(r'x_wconf\s+(\d+)');
  static final _tagPattern = RegExp(r'<[^>]*>');

  ExtractedDocument _parseHocr(String hocr, PreflightResult preflight) {
    final buffer = StringBuffer();
    final words = <RecognizedWord>[];

    final width = (preflight.width ?? 0).toDouble();
    final height = (preflight.height ?? 0).toDouble();
    final canPlace = width > 0 && height > 0;

    var confidenceCount = 0;
    var confidenceTotal = 0.0;

    for (final match in _wordPattern.allMatches(hocr)) {
      final title = match.group(1) ?? '';
      final text = _unescape(match.group(2) ?? '').trim();
      if (text.isEmpty) continue;

      final conf = _confPattern.firstMatch(title);
      // Tesseract reports 0–100. A word with no confidence at all is treated
      // as doubtful rather than certain — inventing certainty is the one thing
      // this layer must not do.
      final confidence =
          conf == null ? 0.5 : (int.parse(conf.group(1)!) / 100).clamp(0.0, 1.0);

      DocumentRegion? region;
      final bbox = _bboxPattern.firstMatch(title);
      if (bbox != null && canPlace) {
        final left = int.parse(bbox.group(1)!).toDouble();
        final top = int.parse(bbox.group(2)!).toDouble();
        final right = int.parse(bbox.group(3)!).toDouble();
        final bottom = int.parse(bbox.group(4)!).toDouble();
        region = DocumentRegion(
          left: (left / width).clamp(0.0, 1.0),
          top: (top / height).clamp(0.0, 1.0),
          width: ((right - left) / width).clamp(0.0, 1.0),
          height: ((bottom - top) / height).clamp(0.0, 1.0),
        );
      }

      final start = buffer.length;
      buffer.write(text);
      words.add(RecognizedWord(
        start: start,
        end: buffer.length,
        confidence: confidence.toDouble(),
        region: region,
      ));
      buffer.write(' ');

      confidenceTotal += confidence;
      confidenceCount++;
    }

    return ExtractedDocument(
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: buffer.toString(),
          words: words,
          source: PageTextSource.opticalRecognition,
          quality: _quality(
            preflight: preflight,
            meanConfidence:
                confidenceCount == 0 ? 1.0 : confidenceTotal / confidenceCount,
          ),
        ),
      ],
      engine: name,
    );
  }

  /// Readability, from what is already known rather than a second image pass.
  ///
  /// Tesseract reports no skew angle, so that factor stays neutral rather than
  /// being guessed at — a fabricated penalty is no better than a fabricated
  /// reassurance.
  static PageQuality _quality({
    required PreflightResult preflight,
    required double meanConfidence,
  }) {
    var resolution = 1.0;
    final width = preflight.width;
    final height = preflight.height;
    if (width != null && height != null) {
      final shortEdge = width < height ? width : height;
      // Tesseract wants more pixels than ML Kit does for cursive script, so
      // the bar is higher: roughly 300 DPI over a page's short edge.
      resolution = (shortEdge / 1200).clamp(0.3, 1.0);
    }

    return PageQuality(
      resolution: resolution,
      sharpness: meanConfidence.clamp(0.3, 1.0).toDouble(),
    );
  }

  /// The handful of entities Tesseract emits in hOCR.
  static String _unescape(String raw) => raw
      .replaceAll(_tagPattern, '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');

  /// Exposed so the hOCR parsing can be tested without a device: everything
  /// interesting here is string handling, and only the engine call is native.
  @visibleForTesting
  ExtractedDocument parseHocrForTest(String hocr, PreflightResult preflight) =>
      _parseHocr(hocr, preflight);
}
