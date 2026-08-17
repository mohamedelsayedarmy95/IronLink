import 'dart:io' show Platform;

import 'mlkit_text_extractor.dart';
import 'pdf_text_extractor.dart';
import 'text_extractor.dart';

/// Builds the extractor set for the device the app is actually running on.
///
/// Registration order is preference order, and the order here is the §3.2
/// rule made structural: the PDF text layer is consulted before anything that
/// recognizes pixels, so a text-native PDF cannot be sent to OCR by accident.
/// A rule enforced by which object answers first is harder to break than one
/// enforced by a comment.
class KeywordExtractors {
  const KeywordExtractors._();

  /// The set for this platform.
  ///
  /// Image recognition is registered only where a native engine exists.
  /// Elsewhere — desktop, tests, a platform channel that failed to attach —
  /// the registry simply reports it cannot handle images, and the pipeline
  /// records OCR_UNAVAILABLE. That is an honest answer; a stub that returned
  /// empty text would be a silent one, and the user would be told a document
  /// was checked when it was not.
  static TextExtractorRegistry forPlatform({MlKitTextExtractor? imageEngine}) {
    final extractors = <TextExtractor>[
      const PdfNativeTextExtractor(),
      const PlainTextExtractor(),
    ];

    final image = imageEngine ?? _defaultImageEngine();
    if (image != null) extractors.insert(0, image);

    return TextExtractorRegistry(extractors);
  }

  static MlKitTextExtractor? _defaultImageEngine() {
    // Platform.isAndroid throws on web, which this app does not target, but
    // the guard costs nothing and the failure mode would be a blank screen.
    try {
      if (Platform.isAndroid || Platform.isIOS) return MlKitTextExtractor();
    } catch (_) {
      return null;
    }
    return null;
  }
}
