import '../domain/keyword_alert.dart';

/// What a text extractor hands back, whatever engine produced it.
///
/// Engines differ in what they can tell you. ML Kit and Apple Vision give
/// per-word confidence and bounding boxes; a PDF's own text layer gives
/// neither, because there is nothing uncertain about it — the characters are
/// stated, not guessed. This shape holds both without pretending they are the
/// same: a word from a text layer carries confidence 1.0 and no box, and the
/// matcher can tell the difference and score accordingly.
///
/// Nothing here is persisted. §4.5 and P-6 allow the matched fragment and a
/// short window of context to survive into an alert, and nothing more, so this
/// lives only as long as the matching pass that consumes it.

/// One word as the engine saw it.
class RecognizedWord {
  const RecognizedWord({
    required this.start,
    required this.end,
    required this.confidence,
    this.region,
  });

  /// Indices into the page's [ExtractedPage.text]. Held as offsets rather than
  /// a copy of the word so that the page text remains the single source of
  /// truth about what was read.
  final int start;
  final int end;

  /// The engine's own certainty, 0..1. A text layer states 1.0 because it is
  /// not recognizing anything.
  final double confidence;

  /// Where the word sits on the page, for highlighting. Null when the engine
  /// does not report geometry.
  final DocumentRegion? region;
}

/// How readable the page was, which down-weights matches found on a bad scan.
///
/// A confident match on a blurred, skewed photograph deserves less trust than
/// the same match on a clean one, and §2.5 makes that an explicit factor
/// rather than something buried in the engine's own number.
class PageQuality {
  const PageQuality({
    this.resolution = 1.0,
    this.sharpness = 1.0,
    this.skew = 1.0,
  });

  /// Pixels available relative to what the engine wants, capped at 1.
  final double resolution;

  /// 1 for crisp, approaching 0 for blurred.
  final double sharpness;

  /// 1 for square to the page, approaching 0 for badly rotated.
  final double skew;

  /// A text layer has no image to be bad.
  static const perfect = PageQuality();

  /// The weakest of the three rather than their average: a page can be sharp,
  /// square, and still too small to read, and averaging would hide that.
  double get score => [resolution, sharpness, skew].reduce((a, b) => a < b ? a : b);
}

/// Where a page's text came from. Recorded because §3.2 forbids OCR-ing a
/// text-native PDF, and the only way to hold that line is to be able to say,
/// per page, which happened.
enum PageTextSource {
  /// The PDF's own text layer. Exact, free, and instant.
  nativeTextLayer,

  /// Optical recognition of a rendered page or a photograph.
  opticalRecognition,
}

class ExtractedPage {
  const ExtractedPage({
    required this.pageNumber,
    required this.text,
    required this.words,
    required this.source,
    this.quality = PageQuality.perfect,
  });

  /// 1-based, because it is shown to the user (§4.4).
  final int pageNumber;

  /// The page's text as extracted, before normalization. Kept unnormalized so
  /// an alert can quote the document's own words (§2.3).
  final String text;

  final List<RecognizedWord> words;
  final PageTextSource source;
  final PageQuality quality;

  bool get isEmpty => text.trim().isEmpty;

  /// The engine's confidence over a span of the page, as the weakest word the
  /// span touches.
  ///
  /// The weakest rather than the average because a keyword is only as reliable
  /// as its least certain character: "contract" read as "contract" with one
  /// shaky letter is a misread, and averaging seven confident letters against
  /// one doubtful one would hide exactly the case worth catching.
  double confidenceOver(int start, int end) {
    var weakest = 1.0;
    var touched = false;
    for (final word in words) {
      if (word.end <= start || word.start >= end) continue;
      touched = true;
      if (word.confidence < weakest) weakest = word.confidence;
    }
    // An engine that reported no word geometry at all leaves the span
    // unjudged; treating that as certainty would be an invention, so it falls
    // back to the page's readability instead.
    return touched ? weakest : quality.score;
  }

  /// The bounding box covering a span, for the viewer to highlight.
  DocumentRegion? regionOver(int start, int end) {
    double? left, top, right, bottom;
    for (final word in words) {
      if (word.end <= start || word.start >= end) continue;
      final r = word.region;
      if (r == null) continue;
      left = left == null || r.left < left ? r.left : left;
      top = top == null || r.top < top ? r.top : top;
      final wordRight = r.left + r.width;
      final wordBottom = r.top + r.height;
      right = right == null || wordRight > right ? wordRight : right;
      bottom = bottom == null || wordBottom > bottom ? wordBottom : bottom;
    }
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    return DocumentRegion(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }
}

class ExtractedDocument {
  const ExtractedDocument({
    required this.pages,
    required this.engine,
    this.truncatedAtPage,
  });

  final List<ExtractedPage> pages;

  /// Which engine ran, for the Security Center's honesty about where a
  /// document was read (§7.2).
  final String engine;

  /// Set when a document exceeded the page ceiling and was processed only up
  /// to it. §3.4 requires this be visible rather than silent — a user told
  /// "nothing found" about a 500-page file that was read to page 200 has been
  /// misled.
  final int? truncatedAtPage;

  bool get isEmpty => pages.every((p) => p.isEmpty);

  bool get wasTruncated => truncatedAtPage != null;

  /// True when no page needed optical recognition — the whole document came
  /// from text layers.
  bool get isFullyNative =>
      pages.every((p) => p.source == PageTextSource.nativeTextLayer);
}
