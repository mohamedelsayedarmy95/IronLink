import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/ocr/preflight.dart';

/// Pre-flight is the only thing standing between an attacker-supplied file and
/// a large body of native decoding code. Its whole value is that it refuses
/// before anything expands, parses, or allocates — so these tests care as much
/// about what it declines to do as about what it accepts.
void main() {
  const preflight = Preflight();

  /// A minimal but structurally real PNG header: signature, then IHDR with the
  /// given dimensions. Enough for header-only inspection, which is all
  /// pre-flight is allowed to need.
  Uint8List png(int width, int height, {int padding = 4096}) {
    final b = BytesBuilder();
    b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    b.add([0x00, 0x00, 0x00, 0x0D]); // IHDR length
    b.add([0x49, 0x48, 0x44, 0x52]); // "IHDR"
    b.add([
      (width >> 24) & 0xFF,
      (width >> 16) & 0xFF,
      (width >> 8) & 0xFF,
      width & 0xFF,
    ]);
    b.add([
      (height >> 24) & 0xFF,
      (height >> 16) & 0xFF,
      (height >> 8) & 0xFF,
      height & 0xFF,
    ]);
    b.add(List.filled(padding, 0x42));
    return b.toBytes();
  }

  Uint8List jpeg(int width, int height, {int padding = 4096}) {
    final b = BytesBuilder();
    b.add([0xFF, 0xD8]); // SOI
    b.add([0xFF, 0xE0, 0x00, 0x10]); // APP0, length 16
    b.add(List.filled(14, 0x00));
    b.add([0xFF, 0xC0, 0x00, 0x11, 0x08]); // SOF0, length 17, precision 8
    b.add([(height >> 8) & 0xFF, height & 0xFF]);
    b.add([(width >> 8) & 0xFF, width & 0xFF]);
    b.add(List.filled(padding, 0x42));
    return b.toBytes();
  }

  Uint8List pdf({bool complete = true, int padding = 2048}) {
    final b = BytesBuilder();
    b.add('%PDF-1.7\n'.codeUnits);
    b.add(List.filled(padding, 0x20));
    if (complete) b.add('\n%%EOF\n'.codeUnits);
    return b.toBytes();
  }

  group('signature verification (§7.4)', () {
    test('identifies a file by its bytes, not its label', () {
      final result = preflight.inspect(png(800, 600));
      expect(result.detectedMimeType, 'image/png');
      expect(result.kind, DocumentKind.image);
    });

    test('refuses a file whose bytes contradict its declared type', () {
      // A JPEG labelled as a PDF is not a mislabelling to tolerate; it is the
      // shape of an attempt to route bytes to a parser not expecting them.
      final result = preflight.inspect(
        jpeg(800, 600),
        declaredMimeType: 'application/pdf',
      );
      expect(result.accepted, isFalse);
      expect(result.rejection, PreflightRejection.signatureMismatch);
      expect(result.detectedMimeType, 'image/jpeg');
    });

    test('tolerates the labels that genuinely vary', () {
      expect(
        preflight.inspect(jpeg(800, 600), declaredMimeType: 'image/jpg').accepted,
        isTrue,
      );
      expect(
        preflight
            .inspect(jpeg(800, 600), declaredMimeType: 'image/jpeg; charset=binary')
            .accepted,
        isTrue,
      );
    });

    test('a generic label conflicts with nothing', () {
      expect(
        preflight
            .inspect(png(800, 600), declaredMimeType: 'application/octet-stream')
            .accepted,
        isTrue,
      );
    });

    test('refuses a format nothing here can read', () {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...List.filled(100, 0)]);
      final result = preflight.inspect(zip);
      expect(result.rejection, PreflightRejection.unsupportedType);
    });

    test('refuses an empty file', () {
      expect(
        preflight.inspect(Uint8List(0)).rejection,
        PreflightRejection.empty,
      );
    });
  });

  group('dimensions read from headers only', () {
    test('PNG', () {
      final result = preflight.inspect(png(1024, 768));
      expect(result.width, 1024);
      expect(result.height, 768);
    });

    test('JPEG, by walking to the start-of-frame', () {
      // Padded to a plausible size for its dimensions: 1600×1200 in four
      // kilobytes is bomb-shaped, and the guard would refuse it before the
      // header parser's answer ever surfaced.
      final result = preflight.inspect(jpeg(1600, 1200, padding: 300 * 1024));
      expect(result.width, 1600);
      expect(result.height, 1200);
    });

    test('GIF', () {
      final gif = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
        0x20, 0x03, // 800 little-endian
        0x58, 0x02, // 600
        ...List.filled(2048, 0x00),
      ]);
      final result = preflight.inspect(gif);
      expect((result.width, result.height), (800, 600));
    });

    test('an unreadable header is not a rejection', () {
      // HEIC geometry needs box parsing, which is not cheap enough for
      // pre-flight. Unknown size means the bomb guard cannot run — the decoder
      // downstream carries its own limits — not that the file is refused.
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x68, 0x65, 0x69, 0x63, // heic
        ...List.filled(2048, 0x00),
      ]);
      final result = preflight.inspect(heic);
      expect(result.accepted, isTrue);
      expect(result.width, isNull);
    });
  });

  group('size and resolution', () {
    test('refuses an oversized image', () {
      const tight = Preflight(limits: PreflightLimits(maxImageBytes: 1024));
      expect(
        tight.inspect(png(800, 600)).rejection,
        PreflightRejection.tooLarge,
      );
    });

    test('refuses an image too small to read text from', () {
      // A LOW-CONFIDENCE alert from an unreadable scan is worse than an honest
      // "this image is too small to analyze".
      final result = preflight.inspect(png(120, 90));
      expect(result.rejection, PreflightRejection.tooLowResolution);
    });

    test('judges resolution on the short edge', () {
      // A wide, shallow strip is unreadable however wide it is.
      expect(
        preflight.inspect(png(4000, 40)).rejection,
        PreflightRejection.tooLowResolution,
      );
    });

    test('accepts an ordinary phone photo', () {
      final result = preflight.inspect(jpeg(3024, 4032, padding: 2 * 1024 * 1024));
      expect(result.accepted, isTrue);
    });
  });

  group('decompression bombs (§7.3)', () {
    test('refuses a file whose declared pixels dwarf its compressed size', () {
      // 30000×30000 in a few kilobytes: nine hundred million pixels that would
      // become gigabytes the instant a decoder touched them.
      final bomb = png(30000, 30000, padding: 512);
      final result = preflight.inspect(bomb);
      expect(result.rejection, PreflightRejection.decompressionBomb);
    });

    test('refuses an absurd pixel count even at a plausible ratio', () {
      final huge = png(20000, 20000, padding: 20 * 1024 * 1024);
      expect(
        preflight.inspect(huge).rejection,
        PreflightRejection.decompressionBomb,
      );
    });

    test('does not refuse a legitimately flat, well-compressed scan', () {
      // A page of mostly white compresses far better than a photograph, and
      // refusing it would reject exactly the documents this feature is for.
      final scan = png(2480, 3508, padding: 120 * 1024);
      expect(preflight.inspect(scan).accepted, isTrue);
    });

    test('rejects the bomb before anything could decode it', () {
      // The guard reads the header and compares two numbers. If it ever needed
      // to decode to decide, it would be the vulnerability instead of the fix.
      final stopwatch = Stopwatch()..start();
      preflight.inspect(png(30000, 30000, padding: 512));
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('PDFs', () {
    test('accepts a complete document', () {
      final result = preflight.inspect(pdf());
      expect(result.accepted, isTrue);
      expect(result.kind, DocumentKind.pdf);
    });

    test('refuses one truncated in transit', () {
      // Feeding half a file to a parser finds the parser's bugs, not the
      // document's contents.
      expect(
        preflight.inspect(pdf(complete: false)).rejection,
        PreflightRejection.malformed,
      );
    });

    test('refuses an oversized document', () {
      const tight = Preflight(limits: PreflightLimits(maxPdfBytes: 512));
      expect(
        tight.inspect(pdf()).rejection,
        PreflightRejection.tooLarge,
      );
    });

    test('gets its own size ceiling, higher than an image', () {
      const limits = PreflightLimits();
      expect(limits.maxPdfBytes, greaterThan(limits.maxImageBytes));
    });
  });

  group('plain text', () {
    test('is recognised by the absence of anything binary', () {
      final text = Uint8List.fromList('Contract for أحمد, signed.'.codeUnits);
      final result = preflight.inspect(text);
      expect(result.kind, DocumentKind.plainText);
    });

    test('is decided last, so binary is never mistaken for it', () {
      expect(preflight.inspect(png(800, 600)).kind, DocumentKind.image);
      expect(preflight.inspect(pdf()).kind, DocumentKind.pdf);
    });

    test('has its own, much lower ceiling', () {
      const tight = Preflight(limits: PreflightLimits(maxTextBytes: 8));
      final text = Uint8List.fromList('a much longer body of text'.codeUnits);
      expect(tight.inspect(text).rejection, PreflightRejection.tooLarge);
    });
  });

  group('malformed input', () {
    test('a truncated PNG header yields no dimensions rather than a crash', () {
      final stub = Uint8List.fromList(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
      expect(() => preflight.inspect(stub), returnsNormally);
    });

    test('a JPEG with no start-of-frame does not loop forever', () {
      final noSof = Uint8List.fromList([0xFF, 0xD8, ...List.filled(5000, 0xFF)]);
      expect(() => preflight.inspect(noSof), returnsNormally);
    });

    test('a zero-dimension image is malformed', () {
      expect(
        preflight.inspect(png(0, 0)).rejection,
        PreflightRejection.malformed,
      );
    });

    test('random bytes never throw', () {
      for (var seed = 0; seed < 64; seed++) {
        final noise = Uint8List.fromList(
          List.generate(300, (i) => (i * 37 + seed * 101) % 256),
        );
        expect(() => preflight.inspect(noise), returnsNormally, reason: 'seed $seed');
      }
    });
  });

  test('the page ceiling is stated, for the extractor to honour', () {
    // Enforced where pages are actually counted; declared here so both halves
    // read the same number, and surfaced as a truncation notice rather than
    // silently — "nothing found" about a 500-page file read to page 200 is a
    // false assurance.
    expect(PreflightLimits.standard.maxPages, 200);
  });
}
