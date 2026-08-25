import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/keyword_alert.dart' show DocumentRegion;
import 'extracted_document.dart';
import 'preflight.dart';
import 'text_extractor.dart';

/// On-device text recognition for images, via Google ML Kit.
///
/// LOCAL, AND MEANT LITERALLY
///
/// ML Kit's text recognizer runs entirely on the device. Nothing about this
/// path touches a network, which is what makes it the default (P-4) and what
/// lets the Security Center say "processed on this device" without an
/// asterisk.
///
/// WHAT IT CANNOT DO, STATED PLAINLY
///
/// ML Kit Text Recognition v2 ships five script models: latin, chinese,
/// devanagari, japanese, korean. **There is no Arabic recognizer.** The
/// master prompt's §3.6 says Arabic "requires the ML Kit Arabic model (v2)";
/// no such model exists in this plugin, and the enum in the package confirms
/// it.
///
/// That matters more here than it would almost anywhere else, because this is
/// an Arabic-first product. Shipping this engine alone and calling the feature
/// done would reproduce exactly the defect the Phase 0 audit found: a keyword
/// feature that silently never matches Arabic. So:
///
/// * Arabic in a **PDF text layer** works today, and well — see
///   [PdfNativeTextExtractor], which reads stated characters rather than
///   guessing at pixels.
/// * Arabic in a **photograph or a scan** does not work with this engine, and
///   this class does not pretend otherwise: [handles] refuses nothing, but the
///   result carries the engine's real confidence, and Arabic text simply is
///   not returned. Closing that gap needs Apple Vision on iOS (which does
///   support Arabic) and a Tesseract `ara` binding on Android.
///
/// This is recorded as a known limitation rather than papered over, because a
/// feature that quietly fails for the primary language is worse than one that
/// says what it cannot do.
class MlKitTextExtractor implements TextExtractor {
  MlKitTextExtractor({TextRecognizer? recognizer, this.timeout = const Duration(seconds: 30)})
      : _recognizer =
            recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  /// Recognition is bounded rather than allowed to run indefinitely. §8.2
  /// forbids a permanent OCR daemon, and a wedged extraction is one by
  /// accident — it would hold a wake lock and a large bitmap for as long as it
  /// took the user to notice.
  final Duration timeout;

  @override
  String get name => 'mlkit-text-recognition-v2';

  @override
  bool handles(DocumentKind kind) => kind == DocumentKind.image;

  @override
  Future<ExtractedDocument> extract(
    Uint8List bytes, {
    required PreflightResult preflight,
    PreflightLimits limits = PreflightLimits.standard,
  }) async {
    // ML Kit takes a file path or a platform buffer with full metadata. A
    // temp file is the reliable route for an arbitrary decoded attachment,
    // and it is deleted in the finally below — a decrypted document must not
    // outlive the pass that read it.
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/kw_ocr_${DateTime.now().microsecondsSinceEpoch}.img',
    );

    try {
      await file.writeAsBytes(bytes, flush: true);

      final RecognizedText recognized;
      try {
        recognized = await _recognizer
            .processImage(InputImage.fromFilePath(file.path))
            .timeout(timeout);
      } on Object catch (e) {
        throw ExtractionException(
          e.toString().contains('TimeoutException')
              ? ExtractionFailure.timedOut
              : ExtractionFailure.unreadable,
          e.toString(),
        );
      }

      return _toDocument(recognized, preflight);
    } finally {
      // Deleted whatever happened. The alternative is a plaintext copy of
      // someone's document sitting in a cache directory after an exception.
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {
        // A temp file we could not remove is not worth failing the pass over,
        // but it is worth not hiding: the OS clears this directory anyway.
      }
    }
  }

  ExtractedDocument _toDocument(
    RecognizedText recognized,
    PreflightResult preflight,
  ) {
    final buffer = StringBuffer();
    final words = <RecognizedWord>[];

    final width = (preflight.width ?? 0).toDouble();
    final height = (preflight.height ?? 0).toDouble();
    final canPlace = width > 0 && height > 0;

    // Rebuilt from elements rather than taking `recognized.text`, because the
    // offsets have to line up with the string the matcher will search. Taking
    // the engine's own concatenation and then guessing where each word landed
    // in it is how a highlight ends up one word to the left.
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          if (element.text.trim().isEmpty) continue;
          final start = buffer.length;
          buffer.write(element.text);
          words.add(RecognizedWord(
            start: start,
            end: buffer.length,
            // Null on iOS, where the platform reports no per-element score.
            // Falling back to the line, then to a deliberately unflattering
            // default, rather than assuming certainty the engine never
            // claimed.
            confidence: element.confidence ?? line.confidence ?? 0.80,
            region: canPlace ? _toRegion(element.boundingBox, width, height) : null,
          ));
          buffer.write(' ');
        }
        buffer.write('\n');
      }
    }

    return ExtractedDocument(
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: buffer.toString(),
          words: words,
          source: PageTextSource.opticalRecognition,
          quality: _quality(recognized, preflight),
        ),
      ],
      engine: name,
    );
  }

  /// Readability signals derived from what the engine and pre-flight already
  /// know, rather than a second image analysis pass.
  ///
  /// Nothing here decodes the image again: the point of the quality factor is
  /// to down-weight a doubtful match, and paying for a blur detector to
  /// discount a result would cost more than the result is worth.
  static PageQuality _quality(RecognizedText recognized, PreflightResult preflight) {
    final width = preflight.width;
    final height = preflight.height;

    // Resolution, relative to roughly what a legible photograph of a page
    // needs. Capped at 1 — extra pixels past that buy nothing.
    var resolution = 1.0;
    if (width != null && height != null) {
      final shortEdge = width < height ? width : height;
      resolution = (shortEdge / 1000).clamp(0.3, 1.0);
    }

    // Sharpness stands in for how sure the engine was overall. A blurred page
    // shows up as uniformly mediocre confidence across every element.
    var total = 0.0;
    var count = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final c = line.confidence;
        if (c == null) continue;
        total += c;
        count++;
      }
    }
    final sharpness = count == 0 ? 1.0 : (total / count).clamp(0.3, 1.0);

    // Skew, from the rotation angle ML Kit reports per element on Android.
    var worstAngle = 0.0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final angle = element.angle?.abs() ?? 0;
          if (angle > worstAngle) worstAngle = angle;
        }
      }
    }
    // Up to about ten degrees is ordinary hand-held tilt and costs nothing;
    // past forty-five the page is effectively sideways.
    final skew = worstAngle <= 10
        ? 1.0
        : (1.0 - (worstAngle - 10) / 45).clamp(0.3, 1.0);

    return PageQuality(
      resolution: resolution,
      sharpness: sharpness.toDouble(),
      skew: skew.toDouble(),
    );
  }

  static DocumentRegion _toRegion(Object box, double width, double height) {
    // boundingBox is a dart:ui Rect in image pixel coordinates. Stored as
    // fractions of the page so the viewer can scale freely.
    final rect = box as dynamic;
    return DocumentRegion(
      left: ((rect.left as num) / width).clamp(0.0, 1.0),
      top: ((rect.top as num) / height).clamp(0.0, 1.0),
      width: ((rect.width as num) / width).clamp(0.0, 1.0),
      height: ((rect.height as num) / height).clamp(0.0, 1.0),
    );
  }

  /// Releases the native recognizer. Held open across documents on purpose —
  /// constructing one per page would reload the model each time — so it has to
  /// be closed deliberately when the feature is torn down.
  Future<void> dispose() => _recognizer.close();
}
