import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../domain/keyword_alert.dart' show DocumentRegion;
import 'extracted_document.dart';
import 'preflight.dart';
import 'text_extractor.dart';

/// Reads a PDF's own text layer.
///
/// §3.2 states the rule in capitals: NEVER OCR a text-native PDF
/// unnecessarily. The reason is not only speed, though the difference is
/// enormous — seconds of battery-burning recognition against milliseconds of
/// parsing. It is accuracy. A PDF's text layer *states* its characters; OCR
/// *guesses* at them from pixels. Running recognition over a document that
/// already told you what it says can only make the answer worse.
///
/// This matters more here than the spec's general case. ML Kit's on-device
/// recognizer has no Arabic script model, so for an Arabic document this is
/// not merely the faster path — it is currently the only one that reads Arabic
/// correctly at all. See docs/SMART_KEYWORD_ALERT_AUDIT.md.
class PdfNativeTextExtractor implements TextExtractor {
  const PdfNativeTextExtractor();

  @override
  String get name => 'pdf-text-layer';

  @override
  bool handles(DocumentKind kind) => kind == DocumentKind.pdf;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    sf.PdfDocument? document;
    try {
      document = sf.PdfDocument(inputBytes: bytes);
    } catch (e) {
      // Pre-flight verified the signature and the trailer, so a failure here
      // means the internal structure is damaged in a way cheap checks cannot
      // see. Fail into UNSUPPORTED_DOCUMENT rather than letting the parser's
      // exception escape (§3.4).
      throw ExtractionException(ExtractionFailure.unreadable, e.toString());
    }

    try {
      final totalPages = document.pages.count;
      final readable =
          totalPages > limits.maxPages ? limits.maxPages : totalPages;

      final extractor = sf.PdfTextExtractor(document);
      final pages = <ExtractedPage>[];

      for (var index = 0; index < readable; index++) {
        // Line by line rather than page-at-once, because the line bounds are
        // what let the viewer highlight a match, and a page-level string
        // throws that geometry away.
        final List<sf.TextLine> lines;
        try {
          lines = extractor.extractTextLines(
            startPageIndex: index,
            endPageIndex: index,
          );
        } catch (_) {
          // One damaged page costs that page, not the document. A scanned
          // report with a corrupt cover sheet still has its contents.
          continue;
        }

        if (lines.isEmpty) continue;

        final buffer = StringBuffer();
        final words = <RecognizedWord>[];
        final pageBounds = _pageBounds(document, index);

        for (final line in lines) {
          for (final word in line.wordCollection) {
            if (word.text.trim().isEmpty) continue;
            final start = buffer.length;
            buffer.write(word.text);
            words.add(RecognizedWord(
              start: start,
              end: buffer.length,
              // Stated, not recognized. Claiming less than certainty about a
              // character the document spells out would be inventing doubt.
              confidence: 1.0,
              region: _toRegion(word.bounds, pageBounds),
            ));
            buffer.write(' ');
          }
          buffer.write('\n');
        }

        pages.add(ExtractedPage(
          pageNumber: index + 1,
          text: buffer.toString(),
          words: words,
          source: PageTextSource.nativeTextLayer,
          // A text layer has no image to be blurred, skewed, or too small.
          quality: PageQuality.perfect,
        ));
      }

      return ExtractedDocument(
        pages: pages,
        engine: name,
        // Surfaced rather than silent: "nothing found" about a 500-page file
        // read to page 200 is a false assurance (§3.4).
        truncatedAtPage: totalPages > readable ? readable : null,
      );
    } finally {
      document.dispose();
    }
  }

  /// Whether a PDF has enough of a text layer to be worth trusting.
  ///
  /// A scanned document is a PDF full of images with no text at all, and one
  /// produced by a bad OCR tool can have a text layer that is mostly noise.
  /// Both need rasterizing and re-recognizing; a genuine text-native PDF must
  /// not be. The threshold is characters per page, because a title page with
  /// six words is normal and a hundred-page document with six words is a scan.
  static bool hasUsableTextLayer(ExtractedDocument document) {
    if (document.pages.isEmpty) return false;
    final characters =
        document.pages.fold<int>(0, (sum, p) => sum + p.text.trim().length);
    return characters >= document.pages.length * 24;
  }

  static Size? _pageBounds(sf.PdfDocument document, int index) {
    try {
      final size = document.pages[index].size;
      return size.width > 0 && size.height > 0 ? size : null;
    } catch (_) {
      return null;
    }
  }

  /// Converts PDF points to fractions of the page.
  ///
  /// Points are unusable once the viewer scales a page to the screen, and
  /// storing the scale alongside them would mean two facts that can disagree.
  static DocumentRegion? _toRegion(Rect bounds, Size? page) {
    if (page == null) return null;
    return DocumentRegion(
      left: (bounds.left / page.width).clamp(0.0, 1.0),
      top: (bounds.top / page.height).clamp(0.0, 1.0),
      width: (bounds.width / page.width).clamp(0.0, 1.0),
      height: (bounds.height / page.height).clamp(0.0, 1.0),
    );
  }
}
