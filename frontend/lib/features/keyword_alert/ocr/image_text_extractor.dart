import 'dart:typed_data';

import 'extracted_document.dart';
import 'mlkit_text_extractor.dart';
import 'preflight.dart';
import 'tesseract_text_extractor.dart';
import 'text_extractor.dart';

/// Reads an image with whichever engine can actually read it.
///
/// Two engines, because neither is sufficient alone. ML Kit is fast, ships with
/// the app, and handles Latin script well — and has no Arabic model at all.
/// Tesseract reads Arabic and is slower and weaker on everything else. In an
/// Arabic-first product, either one on its own leaves a language unreadable.
///
/// THE ORDER IS THE §3.3 LADDER, NOT A PREFERENCE
///
/// §3.3 specifies "Local Fail → Retry with Preprocessing → Retry Alternate
/// Config → Unable to read", deterministically. That is what this is: ML Kit
/// first because it is cheaper, Tesseract as the alternate configuration when
/// the first pass comes back with nothing usable.
///
/// It is a fallback rather than "run both and merge" for a reason that matters
/// on a phone: running two OCR engines over every photograph doubles the most
/// expensive thing this feature does, to improve results on documents the
/// first engine already read correctly.
///
/// WHAT COUNTS AS "NOTHING USABLE"
///
/// Not an exception — ML Kit succeeds on an Arabic document, and returns almost
/// no words. So the trigger is the result, not the error: too little text, or
/// text the engine was not confident about. An Arabic page put through a
/// Latin-only recognizer produces exactly that signature.
class ImageTextExtractor implements TextExtractor {
  ImageTextExtractor({
    TextExtractor? primary,
    TextExtractor? arabic,
    this.minimumUsableCharacters = 12,
    this.minimumUsableConfidence = 0.55,
  })  : _primary = primary ?? MlKitTextExtractor(),
        _arabic = arabic;

  final TextExtractor _primary;

  /// Null where the Arabic model is not present on this device. Checked at
  /// startup rather than assumed — see [TesseractTextExtractor.isAvailable].
  final TextExtractor? _arabic;

  /// Below this many characters, a page is treated as unread rather than empty.
  ///
  /// A photograph of a landscape genuinely contains no words and must not
  /// trigger a second expensive pass; a page of Arabic through a Latin
  /// recognizer returns a scattering of stray marks. Both are short, so this
  /// threshold accepts the cost of one wasted Tesseract pass on a wordless
  /// photo in exchange for never missing an Arabic document. Given the choice,
  /// wasting work is better than not doing it.
  final int minimumUsableCharacters;

  /// And below this mean confidence, whatever was read is not worth trusting
  /// enough to skip the second engine.
  final double minimumUsableConfidence;

  @override
  String get name => _arabic == null
      ? _primary.name
      : '${_primary.name}+${_arabic.name}';

  @override
  bool handles(DocumentKind kind) => kind == DocumentKind.image;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    ExtractedDocument? first;
    Object? firstFailure;

    try {
      first = await _primary.extract(bytes, preflight: preflight, limits: limits);
      if (_isUsable(first)) return first;
    } on ExtractionException catch (e) {
      firstFailure = e;
    }

    final arabic = _arabic;
    if (arabic == null) {
      // Nothing else to try. Return the weak result rather than an error if
      // there is one — a scattering of low-confidence words is still true, and
      // the confidence layer will decline to alert on it.
      if (first != null) return first;
      throw firstFailure ??
          const ExtractionException(ExtractionFailure.unreadable);
    }

    try {
      final second =
          await arabic.extract(bytes, preflight: preflight, limits: limits);
      // Whichever read more of the page wins. Comparing length rather than
      // confidence on purpose: a Latin recognizer given Arabic is often very
      // confident about the handful of marks it did recognise, and that
      // confidence is about the wrong thing.
      if (first == null) return second;
      return _textLength(second) > _textLength(first) ? second : first;
    } on ExtractionException {
      if (first != null) return first;
      rethrow;
    }
  }

  bool _isUsable(ExtractedDocument document) {
    if (_textLength(document) < minimumUsableCharacters) return false;

    var total = 0.0;
    var count = 0;
    for (final page in document.pages) {
      for (final word in page.words) {
        total += word.confidence;
        count++;
      }
    }
    if (count == 0) return false;
    return total / count >= minimumUsableConfidence;
  }

  static int _textLength(ExtractedDocument document) => document.pages
      .fold<int>(0, (sum, page) => sum + page.text.trim().length);
}
