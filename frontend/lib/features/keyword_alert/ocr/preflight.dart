import 'dart:typed_data';

/// Cheap, deterministic checks run before a document is allowed near a decoder
/// (§3.4).
///
/// WHY THIS EXISTS
///
/// Everything downstream — the image decoder, the PDF parser, the OCR engine —
/// is a large body of native code parsing a file that arrived from someone
/// else. Handing it whatever turned up is how a malicious attachment becomes a
/// crashed app at best. The old server path did exactly that: `extract_text`
/// opened whatever it was given, with no size limit, no page limit, and no
/// check that the bytes matched the type they claimed to be.
///
/// So these checks are deliberately dumb. They read a few dozen bytes of
/// header, compare numbers, and decide. Nothing here decompresses anything,
/// which is the point — a decompression bomb has to be refused *before* the
/// thing that would expand it ever sees it.

enum DocumentKind {
  image,
  pdf,
  plainText,
  unsupported;

  bool get isSupported => this != DocumentKind.unsupported;
}

/// Why a document was refused. A code rather than a sentence, so the UI can
/// localize it and §5.8 can explain the failure honestly.
enum PreflightRejection {
  /// The bytes do not match the type the file claims to be.
  signatureMismatch,

  /// Nothing here recognises this format.
  unsupportedType,

  tooLarge,

  /// Too few pixels to read reliably. Refused rather than run, because a
  /// LOW-CONFIDENCE alert from an unreadable scan is worse than an honest
  /// "this image is too small to analyze".
  tooLowResolution,

  /// The declared pixel count is wildly out of proportion to the compressed
  /// size — the shape of a decompression bomb (§7.3).
  decompressionBomb,

  /// Header truncated, or structurally impossible.
  malformed,

  empty,
}

class PreflightResult {
  const PreflightResult._({
    required this.kind,
    required this.accepted,
    this.rejection,
    this.width,
    this.height,
    this.detectedMimeType,
  });

  const PreflightResult.accepted({
    required DocumentKind kind,
    int? width,
    int? height,
    String? detectedMimeType,
  }) : this._(
          kind: kind,
          accepted: true,
          width: width,
          height: height,
          detectedMimeType: detectedMimeType,
        );

  const PreflightResult.rejected(
    PreflightRejection rejection, {
    DocumentKind kind = DocumentKind.unsupported,
    String? detectedMimeType,
  }) : this._(
          kind: kind,
          accepted: false,
          rejection: rejection,
          detectedMimeType: detectedMimeType,
        );

  final DocumentKind kind;
  final bool accepted;
  final PreflightRejection? rejection;

  /// Read from the header without decoding the image.
  final int? width;
  final int? height;

  /// What the bytes actually are, which is not necessarily what they claimed.
  final String? detectedMimeType;
}

class PreflightLimits {
  const PreflightLimits({
    this.maxImageBytes = 25 * 1024 * 1024,
    this.maxPdfBytes = 50 * 1024 * 1024,
    this.maxTextBytes = 5 * 1024 * 1024,
    this.maxPages = 200,
    this.minImageDimension = 200,
    this.maxPixels = 80 * 1000 * 1000,
    this.maxPixelsPerCompressedByte = 400,
  });

  final int maxImageBytes;
  final int maxPdfBytes;
  final int maxTextBytes;

  /// Documents beyond this are processed *up to* it, with the truncation made
  /// visible — never silently, because "nothing found" about a 500-page file
  /// read to page 200 is a false assurance.
  final int maxPages;

  /// Below this on the short edge, text is not reliably recoverable.
  final int minImageDimension;

  /// A ceiling on decoded size regardless of ratio: 80 megapixels is far
  /// beyond any camera a phone user is sending from, and decoding it would
  /// cost hundreds of megabytes.
  final int maxPixels;

  /// The bomb ratio. A dense photograph runs about 5–15 pixels per compressed
  /// byte; a page of flat colour can legitimately reach a few hundred. Well
  /// past that is a file built to expand rather than to be looked at.
  final int maxPixelsPerCompressedByte;

  static const standard = PreflightLimits();
}

class Preflight {
  const Preflight({this.limits = PreflightLimits.standard});

  final PreflightLimits limits;

  /// Inspects [bytes], which must be the whole file.
  ///
  /// [declaredMimeType] is what the sender said. It is used only to detect a
  /// mismatch — never trusted, per §7.4. What the file *is* comes from its
  /// signature.
  PreflightResult inspect(Uint8List bytes, {String? declaredMimeType}) {
    if (bytes.isEmpty) {
      return const PreflightResult.rejected(PreflightRejection.empty);
    }

    final detected = _detectMimeType(bytes);
    if (detected == null) {
      return const PreflightResult.rejected(PreflightRejection.unsupportedType);
    }

    // A JPEG arriving labelled as a PDF is not a mislabelling to be tolerated;
    // it is the shape of an attempt to route bytes to a parser that was not
    // expecting them.
    if (declaredMimeType != null &&
        declaredMimeType.isNotEmpty &&
        !_typesAgree(declaredMimeType, detected)) {
      return PreflightResult.rejected(
        PreflightRejection.signatureMismatch,
        detectedMimeType: detected,
      );
    }

    if (detected == 'application/pdf') {
      if (bytes.length > limits.maxPdfBytes) {
        return const PreflightResult.rejected(
          PreflightRejection.tooLarge,
          kind: DocumentKind.pdf,
        );
      }
      if (!_looksLikeCompletePdf(bytes)) {
        return const PreflightResult.rejected(
          PreflightRejection.malformed,
          kind: DocumentKind.pdf,
        );
      }
      return const PreflightResult.accepted(
        kind: DocumentKind.pdf,
        detectedMimeType: 'application/pdf',
      );
    }

    if (detected.startsWith('text/')) {
      if (bytes.length > limits.maxTextBytes) {
        return const PreflightResult.rejected(
          PreflightRejection.tooLarge,
          kind: DocumentKind.plainText,
        );
      }
      return PreflightResult.accepted(
        kind: DocumentKind.plainText,
        detectedMimeType: detected,
      );
    }

    // Images.
    if (bytes.length > limits.maxImageBytes) {
      return PreflightResult.rejected(
        PreflightRejection.tooLarge,
        kind: DocumentKind.image,
        detectedMimeType: detected,
      );
    }

    final size = _imageDimensions(bytes, detected);
    if (size == null) {
      // The header did not yield dimensions. For a format whose geometry we
      // cannot read cheaply (HEIC, say) that is expected, so it is not a
      // rejection — but the bomb guard cannot run either, and the decoder
      // downstream carries its own limits.
      return PreflightResult.accepted(
        kind: DocumentKind.image,
        detectedMimeType: detected,
      );
    }

    final (width, height) = size;
    if (width <= 0 || height <= 0) {
      return PreflightResult.rejected(
        PreflightRejection.malformed,
        kind: DocumentKind.image,
        detectedMimeType: detected,
      );
    }

    final pixels = width * height;
    if (pixels > limits.maxPixels ||
        pixels > bytes.length * limits.maxPixelsPerCompressedByte) {
      return PreflightResult.rejected(
        PreflightRejection.decompressionBomb,
        kind: DocumentKind.image,
        detectedMimeType: detected,
      );
    }

    final shortEdge = width < height ? width : height;
    if (shortEdge < limits.minImageDimension) {
      return PreflightResult.rejected(
        PreflightRejection.tooLowResolution,
        kind: DocumentKind.image,
        detectedMimeType: detected,
      );
    }

    return PreflightResult.accepted(
      kind: DocumentKind.image,
      width: width,
      height: height,
      detectedMimeType: detected,
    );
  }

  // ── Signatures ─────────────────────────────────────────────────────────────

  static String? _detectMimeType(Uint8List b) {
    bool at(int offset, List<int> magic) {
      if (b.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif'; // GIF8
    if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp'; // RIFF....WEBP
    }
    if (at(0, [0x42, 0x4D])) return 'image/bmp';
    if (at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A])) {
      return 'image/tiff';
    }
    // HEIC/HEIF: a 'ftyp' box at offset 4 with a heic-family brand.
    if (at(4, [0x66, 0x74, 0x79, 0x70])) {
      final brand = String.fromCharCodes(b.sublist(8, b.length < 12 ? b.length : 12));
      if (const {'heic', 'heix', 'hevc', 'mif1', 'msf1'}.contains(brand)) {
        return 'image/heic';
      }
    }
    if (at(0, [0x25, 0x50, 0x44, 0x46, 0x2D])) return 'application/pdf'; // %PDF-

    // Plain text is defined by what it is not: no signature, and no bytes that
    // could not be text. Checked last so a binary format is never mistaken for
    // it, and over a prefix, because scanning a five-megabyte file byte by
    // byte is exactly the expense pre-flight exists to avoid.
    final probe = b.length < 1024 ? b.length : 1024;
    var plausible = true;
    for (var i = 0; i < probe; i++) {
      final c = b[i];
      final isControl = c < 0x09 || (c > 0x0D && c < 0x20);
      if (isControl) {
        plausible = false;
        break;
      }
    }
    if (plausible) return 'text/plain';

    return null;
  }

  /// Whether a declared type and a detected one describe the same thing.
  ///
  /// Tolerant about the families where several labels are genuinely in use —
  /// image/jpg for image/jpeg, text/csv for text/plain — and strict about
  /// everything else.
  static bool _typesAgree(String declared, String detected) {
    String canonical(String type) {
      final t = type.split(';').first.trim().toLowerCase();
      if (t == 'image/jpg') return 'image/jpeg';
      if (t.startsWith('text/')) return 'text/plain';
      if (t == 'image/heif') return 'image/heic';
      return t;
    }

    final d = canonical(declared);
    final f = canonical(detected);
    if (d == f) return true;
    // A generic label is a claim about nothing in particular, so it cannot
    // conflict with what the bytes say.
    return d == 'application/octet-stream' || d.isEmpty;
  }

  /// A PDF ends with %%EOF. Its absence means the file was truncated in
  /// transit, and feeding a half-file to a parser is how you find the parser's
  /// bugs rather than the document's contents.
  static bool _looksLikeCompletePdf(Uint8List b) {
    const eof = [0x25, 0x25, 0x45, 0x4F, 0x46]; // %%EOF
    // The marker is followed by optional whitespace, so search the tail rather
    // than requiring it at the very last byte.
    final from = b.length > 2048 ? b.length - 2048 : 0;
    for (var i = b.length - eof.length; i >= from; i--) {
      var hit = true;
      for (var j = 0; j < eof.length; j++) {
        if (b[i + j] != eof[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return true;
    }
    return false;
  }

  // ── Dimensions, from headers only ──────────────────────────────────────────

  static (int, int)? _imageDimensions(Uint8List b, String mimeType) {
    switch (mimeType) {
      case 'image/png':
        // IHDR is always the first chunk: width and height are big-endian
        // 32-bit at offsets 16 and 20.
        if (b.length < 24) return null;
        return (_u32be(b, 16), _u32be(b, 20));

      case 'image/gif':
        if (b.length < 10) return null;
        return (_u16le(b, 6), _u16le(b, 8));

      case 'image/bmp':
        if (b.length < 26) return null;
        return (_u32le(b, 18), _u32le(b, 22).abs());

      case 'image/webp':
        return _webpDimensions(b);

      case 'image/jpeg':
        return _jpegDimensions(b);
    }
    return null;
  }

  /// Walks JPEG markers to the start-of-frame, which is the only place the
  /// image's real size is stated.
  static (int, int)? _jpegDimensions(Uint8List b) {
    var i = 2; // past SOI
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++; // resynchronise rather than give up on one stray byte
        continue;
      }
      final marker = b[i + 1];
      // Standalone markers carry no length.
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = _u16be(b, i + 2);
      if (length < 2) return null; // malformed segment
      // SOF0..SOF15, excluding the DHT/JPG/DAC markers that share the range.
      final isStartOfFrame = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame) {
        if (i + 9 >= b.length) return null;
        return (_u16be(b, i + 7), _u16be(b, i + 5)); // width, height
      }
      i += 2 + length;
    }
    return null;
  }

  static (int, int)? _webpDimensions(Uint8List b) {
    if (b.length < 30) return null;
    final format = String.fromCharCodes(b.sublist(12, 16));
    switch (format) {
      case 'VP8 ':
        // Lossy: 14-bit dimensions after the 3-byte start code.
        return (_u16le(b, 26) & 0x3FFF, _u16le(b, 28) & 0x3FFF);
      case 'VP8L':
        // Lossless: 14 bits each, packed across four bytes.
        final bits = _u32le(b, 21);
        return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
      case 'VP8X':
        // Extended: 24-bit dimensions minus one.
        final w = b[24] | (b[25] << 8) | (b[26] << 16);
        final h = b[27] | (b[28] << 8) | (b[29] << 16);
        return (w + 1, h + 1);
    }
    return null;
  }

  static int _u16be(Uint8List b, int i) => (b[i] << 8) | b[i + 1];
  static int _u16le(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
  static int _u32be(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  static int _u32le(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
}
