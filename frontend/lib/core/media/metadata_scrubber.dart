/// Strips identifying metadata from media before it leaves the device.
///
/// WHY THIS HAS TO EXIST, AND WHY ON THE DEVICE
///
/// A photograph taken on a phone carries the GPS coordinates where it was
/// taken, the camera's serial number, the lens's serial number, the owner name
/// configured on the device, and the exact second the shutter fired. For most
/// products that is a footnote. For this one it is the whole threat model: a
/// user who trusts an encrypted messenger with a photograph of a location has
/// not agreed to publish that location, and coordinates in an EXIF header are
/// the same disclosure as typing them out.
///
/// It cannot be done on the server. Attachment bodies are encrypted on this
/// device before upload, so the server holds ciphertext and could not read the
/// header even if it were asked to. The choice is on-device or not at all.
///
/// WHY `imageQuality` WAS NOT ALREADY DOING THIS
///
/// The attach flow picks images with `imageQuality: 92`, which re-encodes them
/// and would plausibly be assumed to drop the metadata with everything else.
/// It does the opposite. `image_picker_android`'s `ExifDataCopier` copies the
/// old header onto the resized copy, and its explicit list of attributes
/// includes `TAG_GPS_LATITUDE`, `TAG_GPS_LONGITUDE`, `TAG_GPS_ALTITUDE`,
/// `TAG_GPS_TIMESTAMP`, `TAG_CAMERA_OWNER_NAME`, `TAG_BODY_SERIAL_NUMBER` and
/// `TAG_LENS_SERIAL_NUMBER`. The re-encode is exactly the step that made this
/// look handled.
///
/// WHY IT REWRITES CONTAINERS INSTEAD OF RE-ENCODING PIXELS
///
/// Decoding and re-encoding an image would drop metadata as a side effect, but
/// it costs a full bitmap in memory, seconds of CPU on a large photograph, and
/// a generation of quality. This walks the container's segment structure and
/// removes the segments that carry metadata, leaving the compressed image data
/// untouched. The output is byte-identical to the input in every part that
/// carries picture rather than provenance.
///
/// WHAT IT DELIBERATELY KEEPS
///
/// Orientation, and colour. Everything else in an EXIF header describes the
/// photographer; orientation describes which way is up, takes one of eight
/// values, and identifies nobody. Dropping it turns every portrait photograph
/// taken on Android sideways, because the picker's resize writes pixels in
/// sensor order and relies on the tag. So the tag is read out and re-emitted
/// on its own, in a freshly built header that contains nothing else.
library;

import 'dart:typed_data';

/// Raised when the bytes are not a format this can strip.
///
/// This is deliberately fatal to the upload rather than a warning. A scrubber
/// that passes unknown formats through untouched is a scrubber that does
/// nothing the first time it meets a format nobody tested, and it would do it
/// silently.
class UnscrubbableMedia implements Exception {
  const UnscrubbableMedia(this.reason);
  final String reason;

  @override
  String toString() => 'UnscrubbableMedia: $reason';
}

class MetadataScrubber {
  const MetadataScrubber();

  /// Returns [bytes] with identifying metadata removed.
  ///
  /// Pure, and dispatches on the actual magic bytes rather than on a declared
  /// MIME type. A caller that mislabels a JPEG as `application/octet-stream`
  /// must not thereby skip the strip, and the declared type is the one piece
  /// of information here that an attacker upstream could choose.
  Uint8List scrub(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const UnscrubbableMedia('too short to identify');
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _jpeg(bytes);
    if (_startsWith(bytes, _pngSignature)) return _png(bytes);
    if (_isFourCc(bytes, 4, 'ftyp')) return _isoBmff(bytes);
    throw const UnscrubbableMedia('unrecognised container');
  }

  // ---------------------------------------------------------------- JPEG

  /// Rebuilds a JPEG from its segments, keeping an allowlist.
  ///
  /// An allowlist rather than a blocklist: JPEG lets an encoder put anything
  /// in any of the sixteen APPn slots, and a rule that named the bad ones
  /// would need editing every time a vendor invented another.
  static Uint8List _jpeg(Uint8List b) {
    final kept = BytesBuilder();
    var orientation = 1;
    var i = 2;

    while (i + 1 < b.length) {
      if (b[i] != 0xFF) {
        throw const UnscrubbableMedia('malformed JPEG: expected a marker');
      }
      final marker = b[i + 1];

      // Standalone markers carry no length.
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9) break;
      if (i + 3 >= b.length) {
        throw const UnscrubbableMedia('malformed JPEG: truncated segment');
      }

      final length = (b[i + 2] << 8) | b[i + 3];
      final end = i + 2 + length;
      if (length < 2 || end > b.length) {
        throw const UnscrubbableMedia('malformed JPEG: bad segment length');
      }

      // Start of scan. Everything from here to the end is entropy-coded
      // image data, which has no segment structure worth walking and carries
      // no metadata. Copied wholesale.
      if (marker == 0xDA) {
        kept.add(Uint8List.sublistView(b, i));
        i = b.length;
        break;
      }

      final payload = i + 4;
      if (marker == 0xE1) {
        // Read the orientation out before discarding the header it lives in.
        orientation = _orientationIn(b, payload, end) ?? orientation;
      }
      if (_keepsJpegSegment(marker, b, payload, end)) {
        kept.add(Uint8List.sublistView(b, i, end));
      }
      i = end;
    }

    final out = BytesBuilder()..add(const [0xFF, 0xD8]);
    // Re-emitted first, so it is found by decoders that stop at the first
    // APP1 they see. Built from scratch, not copied: the point is that the
    // output header contains this value and nothing else.
    if (orientation != 1) out.add(_orientationOnlyExif(orientation));
    out.add(kept.takeBytes());
    return out.takeBytes();
  }

  static bool _keepsJpegSegment(int marker, Uint8List b, int start, int end) {
    // Comments are free text an encoder or an editor may have written.
    if (marker == 0xFE) return false;

    // Not an application segment: quantisation tables, Huffman tables, frame
    // headers. Structure, not provenance.
    if (marker < 0xE0 || marker > 0xEF) return true;

    // APP0 holds the JFIF density header, which is fine, but the JFXX variant
    // holds an embedded thumbnail — a second copy of the picture that this
    // pass would not otherwise inspect.
    if (marker == 0xE0) return _payloadStartsWith(b, start, end, 'JFIF\x00');

    // APP2 is usually an ICC colour profile, which is worth keeping for
    // colour accuracy and describes the device's colour space rather than the
    // device. It is also where Multi-Picture Format hides a whole second
    // image, so the profile is matched explicitly.
    if (marker == 0xE2) {
      return _payloadStartsWith(b, start, end, 'ICC_PROFILE\x00');
    }

    // APP1 (EXIF, XMP), APP13 (Photoshop IRB, IPTC), and the rest of the
    // vendor slots.
    return false;
  }

  /// A complete EXIF header whose only content is the orientation tag.
  ///
  /// Thirty-six bytes: the APP1 marker and length, the `Exif\0\0` signature, a
  /// big-endian TIFF header, one IFD entry, and a null next-IFD pointer.
  static Uint8List _orientationOnlyExif(int orientation) => Uint8List.fromList([
        0xFF, 0xE1, 0x00, 0x22, // APP1, length 34
        0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
        0x4D, 0x4D, // big-endian
        0x00, 0x2A, // TIFF magic 42
        0x00, 0x00, 0x00, 0x08, // IFD0 at offset 8
        0x00, 0x01, // one entry
        0x01, 0x12, // tag 0x0112, Orientation
        0x00, 0x03, // type SHORT
        0x00, 0x00, 0x00, 0x01, // count 1
        orientation >> 8, orientation & 0xFF, 0x00, 0x00, // value, left-packed
        0x00, 0x00, 0x00, 0x00, // no next IFD
      ]);

  /// Reads tag 0x0112 out of an APP1 payload, or null if it is not there.
  static int? _orientationIn(Uint8List b, int start, int end) {
    if (end - start < 14) return null;
    if (!_payloadStartsWith(b, start, end, 'Exif\x00\x00')) return null;

    final tiff = start + 6;
    final bool bigEndian;
    if (b[tiff] == 0x4D && b[tiff + 1] == 0x4D) {
      bigEndian = true;
    } else if (b[tiff] == 0x49 && b[tiff + 1] == 0x49) {
      bigEndian = false;
    } else {
      return null;
    }

    int u16(int o) =>
        bigEndian ? (b[o] << 8) | b[o + 1] : (b[o + 1] << 8) | b[o];
    int u32(int o) => bigEndian
        ? (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
        : (b[o + 3] << 24) | (b[o + 2] << 16) | (b[o + 1] << 8) | b[o];

    if (u16(tiff + 2) != 42) return null;
    final ifd = tiff + u32(tiff + 4);
    if (ifd < tiff || ifd + 2 > end) return null;

    final entries = u16(ifd);
    for (var e = 0; e < entries; e++) {
      final entry = ifd + 2 + e * 12;
      if (entry + 12 > end) break;
      if (u16(entry) != 0x0112) continue;
      if (u16(entry + 2) != 3) return null; // not a SHORT; treat as absent
      final value = u16(entry + 8);
      return (value >= 1 && value <= 8) ? value : null;
    }
    return null;
  }

  // ----------------------------------------------------------------- PNG

  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  /// Chunks that describe the image rather than its history.
  ///
  /// PNG's text chunks are the metadata surface here — `eXIf` carries a whole
  /// EXIF header including GPS, and `tEXt`/`iTXt` are where editors write
  /// software names, authors, and comments. Unknown chunks are dropped rather
  /// than kept: a chunk nobody here recognises is a chunk nobody here has
  /// checked.
  static const _pngKeep = {
    'IHDR', 'PLTE', 'IDAT', 'IEND', // critical
    'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP', 'sBIT', 'bKGD', 'hIST', 'pHYs',
    'sPLT', // rendering
    'acTL', 'fcTL', 'fdAT', // APNG frames
  };

  static Uint8List _png(Uint8List b) {
    final out = BytesBuilder()..add(_pngSignature);
    var i = _pngSignature.length;

    while (i + 8 <= b.length) {
      final length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      if (length < 0) throw const UnscrubbableMedia('malformed PNG: bad length');
      final end = i + 12 + length;
      if (end > b.length) {
        throw const UnscrubbableMedia('malformed PNG: truncated chunk');
      }
      final type = String.fromCharCodes(b, i + 4, i + 8);
      if (_pngKeep.contains(type)) out.add(Uint8List.sublistView(b, i, end));
      i = end;
      if (type == 'IEND') break;
    }
    return out.takeBytes();
  }

  // ------------------------------------------------------------- ISO BMFF

  /// Neutralises the metadata boxes in an MP4/M4A, without moving anything.
  ///
  /// This one cannot remove bytes. A `stco` table inside `moov` holds absolute
  /// file offsets into `mdat`, so deleting a box that sits before the media
  /// data shifts every sample and silently corrupts the file — the kind of bug
  /// that appears as audio that plays for one second and stops.
  ///
  /// So the boxes are overwritten in place: the four-byte type becomes `free`,
  /// which the format defines as ignorable padding, and the payload is zeroed.
  /// Same length, same offsets, no metadata. `udta` is where a camera writes
  /// the `©xyz` location atom and the make and model; `meta` is where iTunes
  /// tagging lives.
  static Uint8List _isoBmff(Uint8List b) {
    final out = Uint8List.fromList(b);
    _neutraliseBoxes(out, 0, out.length);
    return out;
  }

  static const _recurseInto = {'moov', 'trak', 'mdia', 'minf', 'edts'};
  static const _neutralise = {'udta', 'meta'};

  static void _neutraliseBoxes(Uint8List b, int start, int limit) {
    var i = start;
    while (i + 8 <= limit) {
      var size = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      final type = String.fromCharCodes(b, i + 4, i + 8);
      var header = 8;

      if (size == 1) {
        // 64-bit size. Anything needing it is far larger than this app sends,
        // and the high word is refused rather than truncated.
        if (i + 16 > limit) return;
        final high =
            (b[i + 8] << 24) | (b[i + 9] << 16) | (b[i + 10] << 8) | b[i + 11];
        if (high != 0) throw const UnscrubbableMedia('MP4 box beyond 4 GiB');
        size = (b[i + 12] << 24) |
            (b[i + 13] << 16) |
            (b[i + 14] << 8) |
            b[i + 15];
        header = 16;
      } else if (size == 0) {
        size = limit - i; // extends to the end of the container
      }

      if (size < header || i + size > limit) return;

      if (_neutralise.contains(type)) {
        b[i + 4] = 0x66; // 'f'
        b[i + 5] = 0x72; // 'r'
        b[i + 6] = 0x65; // 'e'
        b[i + 7] = 0x65; // 'e'
        b.fillRange(i + header, i + size, 0);
      } else if (_recurseInto.contains(type)) {
        _neutraliseBoxes(b, i + header, i + size);
      }
      i += size;
    }
  }

  // --------------------------------------------------------------- helpers

  static bool _startsWith(Uint8List b, List<int> prefix) {
    if (b.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _isFourCc(Uint8List b, int at, String cc) {
    if (at + 4 > b.length) return false;
    for (var i = 0; i < 4; i++) {
      if (b[at + i] != cc.codeUnitAt(i)) return false;
    }
    return true;
  }

  static bool _payloadStartsWith(
      Uint8List b, int start, int end, String prefix) {
    if (end - start < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[start + i] != prefix.codeUnitAt(i)) return false;
    }
    return true;
  }
}
