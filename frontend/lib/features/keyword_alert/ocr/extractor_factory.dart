import 'dart:io' show Platform;

import 'image_text_extractor.dart';
import 'tesseract_text_extractor.dart';
import 'pdf_text_extractor.dart';
import 'text_extractor.dart';

/// Builds the extractor set for the device the app is actually running on.
///
/// Registration order is preference order, and the order here is the §3.2 rule
/// made structural: the PDF text layer is consulted before anything that
/// recognizes pixels, so a text-native PDF cannot be sent to OCR by accident.
/// A rule enforced by which object answers first is harder to break than one
/// enforced by a comment.
class KeywordExtractors {
  const KeywordExtractors._();

  /// The set for this platform.
  ///
  /// Async because whether Arabic recognition is available is a question about
  /// the installation — is the model on disk and not truncated — rather than
  /// about the build. Asking it here means the answer is settled once, at
  /// startup, instead of being guessed at per document.
  ///
  /// Image recognition registers only where a native engine exists. Elsewhere —
  /// desktop, tests, a platform channel that failed to attach — the registry
  /// reports it cannot handle images and the pipeline records OCR_UNAVAILABLE.
  /// That is an honest answer; a stub returning empty text would be a silent
  /// one, and the user would be told a document was checked when it was not.
  static Future<TextExtractorRegistry> forPlatform({
    TextExtractor? imageEngine,
  }) async {
    final extractors = <TextExtractor>[
      const PdfNativeTextExtractor(),
      const PlainTextExtractor(),
    ];

    final image = imageEngine ?? await _defaultImageEngine();
    if (image != null) extractors.insert(0, image);

    return TextExtractorRegistry(extractors);
  }

  static Future<TextExtractor?> _defaultImageEngine() async {
    // Platform.isAndroid throws on web, which this app does not target, but
    // the guard costs nothing and the failure mode would be a blank screen.
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return null;
    } catch (_) {
      return null;
    }

    // Arabic is the primary language of this product, so its engine is not an
    // optional extra — but it is also not something to claim without checking.
    // If the bundled model did not unpack, the composite falls back to ML Kit
    // alone, Arabic images are not read, and the pipeline says so.
    final arabicReady = await TesseractTextExtractor.isAvailable();

    return ImageTextExtractor(
      arabic: arabicReady ? const TesseractTextExtractor() : null,
    );
  }
}
