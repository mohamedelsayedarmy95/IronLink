import 'dart:typed_data';

import 'extracted_document.dart';
import 'preflight.dart';

/// The contract every text source implements, from a PDF's own text layer to
/// an on-device OCR engine.
///
/// The engine is an implementation detail behind this interface, and §3.6 is
/// explicit that it never becomes a reason to weaken the transparency rules in
/// §3.3: whichever engine runs, the document does not leave the device unless
/// the user has separately and explicitly opted into cloud processing.

/// Why extraction failed. Distinct from a pre-flight rejection: pre-flight
/// refuses a document, whereas these are things that went wrong while reading
/// one that looked fine.
enum ExtractionFailure {
  /// No engine on this device can read this kind of file.
  engineUnavailable,

  /// The engine ran and could not make sense of the document.
  unreadable,

  /// The engine took too long and was abandoned. Bounded rather than allowed
  /// to run indefinitely — §8.2 forbids a permanent OCR daemon, and a wedged
  /// extraction is one by accident.
  timedOut,

  /// Cloud extraction was needed and there is no network (§8.5).
  networkUnavailable,
}

class ExtractionException implements Exception {
  const ExtractionException(this.failure, [this.detail]);

  final ExtractionFailure failure;
  final String? detail;

  @override
  String toString() => 'ExtractionException(${failure.name}): ${detail ?? ''}';
}

abstract interface class TextExtractor {
  /// A stable name, recorded on the document so the Security Center can say
  /// truthfully where a file was read (§7.2).
  String get name;

  /// Whether this extractor handles the given kind of document.
  bool handles(DocumentKind kind);

  /// Reads [bytes], or throws [ExtractionException].
  ///
  /// [preflight] carries what inspection already learned — dimensions, the
  /// real type — so the extractor does not re-derive it and cannot disagree
  /// with the checks that let the document through.
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits,
  });
}

/// Reads a text file, which needs no recognition at all.
///
/// Worth having as a real extractor rather than a special case: it exercises
/// the same path as everything else, and a `.txt` attachment is a document a
/// user can perfectly reasonably want watched.
class PlainTextExtractor implements TextExtractor {
  const PlainTextExtractor();

  @override
  String get name => 'plain-text';

  @override
  bool handles(DocumentKind kind) => kind == DocumentKind.plainText;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    // Decoded permissively: a text file with one bad byte is still a text
    // file, and refusing the whole document over it would lose real content.
    final text = String.fromCharCodes(bytes);

    final words = <RecognizedWord>[];
    for (final m in RegExp(r'\S+').allMatches(text)) {
      // Confidence 1.0 because nothing was recognized — the characters are
      // stated, not guessed. Claiming anything less would be inventing doubt.
      words.add(RecognizedWord(start: m.start, end: m.end, confidence: 1.0));
    }

    return ExtractedDocument(
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: text,
          words: words,
          source: PageTextSource.nativeTextLayer,
        ),
      ],
      engine: name,
    );
  }
}

/// Picks an extractor for a document, and reports honestly when there is none.
///
/// Registration order is preference order. Nothing here falls back to the
/// cloud: that decision belongs to [OcrModeDecision], which the caller applies
/// deliberately, because a silent fallback is exactly what §3.3 forbids.
class TextExtractorRegistry {
  const TextExtractorRegistry(this.extractors);

  final List<TextExtractor> extractors;

  /// The extractors that need no platform channel and no model download.
  ///
  /// The image engine registers on top of this at startup, where the platform
  /// is known — it is the only one whose availability depends on the device.
  static const minimal = TextExtractorRegistry([PlainTextExtractor()]);

  TextExtractor? forKind(DocumentKind kind) {
    for (final extractor in extractors) {
      if (extractor.handles(kind)) return extractor;
    }
    return null;
  }

  bool canHandle(DocumentKind kind) => forKind(kind) != null;

  TextExtractorRegistry withExtractor(TextExtractor extractor) =>
      TextExtractorRegistry([extractor, ...extractors]);
}
