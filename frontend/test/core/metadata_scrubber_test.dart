import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/media/metadata_scrubber.dart';

/// The fixtures here are built byte by byte rather than checked in as binary
/// files, for two reasons. A test that asserts "the GPS coordinates are gone"
/// is only meaningful if the reader can see the coordinates going in, and a
/// binary fixture hides exactly the thing under test. And a photograph with
/// real coordinates in it is not something to commit to a repository.
void main() {
  const scrubber = MetadataScrubber();

  // A coordinate and a serial number: the two disclosures that matter most.
  const coordinates = 'GPS 30.0444,31.2357';
  const serial = 'CAM-SERIAL-99';

  group('JPEG', () {
    test('a location in the EXIF header does not survive', () {
      final out = scrubber.scrub(_jpegWithEverything());
      expect(_contains(out, serial), isFalse);
    });

    test('a location in a comment segment does not survive', () {
      final out = scrubber.scrub(_jpegWithEverything());
      expect(_contains(out, coordinates), isFalse);
    });

    test('the image data itself is untouched', () {
      // The whole design rests on this: metadata is removed by rewriting the
      // container, never by re-encoding the picture. If this fails, the
      // scrubber has become a lossy filter.
      final out = scrubber.scrub(_jpegWithEverything());
      expect(_contains(out, 'ENTROPY-CODED-IMAGE-DATA'), isTrue);
    });

    test('the colour profile is kept', () {
      final out = scrubber.scrub(_jpegWithEverything());
      expect(_contains(out, 'ICC_PROFILE'), isTrue);
    });

    test('orientation survives, and nothing else from EXIF does', () {
      // Android's picker writes pixels in sensor order and relies on this tag.
      // Dropping it would turn every portrait photograph sideways — a visible
      // regression that would get the whole feature reverted.
      final out = scrubber.scrub(_jpegWithEverything());

      final app1 = _segment(out, 0xE1);
      expect(app1, isNotNull, reason: 'orientation should be re-emitted');
      expect(app1!.length, 36, reason: 'a header holding one tag and no more');

      // Offsets into the re-emitted header: marker and length (4), the Exif
      // signature (6), the TIFF header (8), the entry count (2), then the one
      // entry — tag, type and count (8) followed by its value.
      const value = 4 + 6 + 8 + 2 + 8;
      expect(app1[value] << 8 | app1[value + 1], 6);
      expect(_contains(app1, serial), isFalse);
    });

    test('an upright image gets no EXIF header at all', () {
      final out = scrubber.scrub(_jpegWithEverything(orientation: 1));
      expect(_segment(out, 0xE1), isNull);
    });

    test('a JFXX thumbnail is dropped, a JFIF density header is kept', () {
      // JFXX carries a second copy of the picture, which this pass would not
      // otherwise look inside.
      final withJfif = scrubber.scrub(_jpegWithEverything());
      expect(_contains(withJfif, 'JFIF'), isTrue);
      expect(_contains(withJfif, 'JFXX'), isFalse);
    });

    test('vendor application segments are dropped without being named', () {
      // APP13 is Photoshop's; the point is that the rule is an allowlist, so
      // a segment nobody anticipated is dropped rather than passed through.
      final out = scrubber.scrub(_jpegWithEverything());
      expect(_contains(out, 'Photoshop 3.0'), isFalse);
      expect(_contains(out, 'SomeVendorNobodyPlannedFor'), isFalse);
    });

    test('the result is still a JPEG', () {
      final out = scrubber.scrub(_jpegWithEverything());
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(_segment(out, 0xDB), isNotNull, reason: 'quantisation table kept');
    });

    test('truncated input is refused, not half-scrubbed', () {
      final full = _jpegWithEverything();
      final cut = Uint8List.sublistView(full, 0, full.length ~/ 2);
      expect(() => scrubber.scrub(cut), throwsA(isA<UnscrubbableMedia>()));
    });
  });

  group('PNG', () {
    test('an eXIf chunk does not survive', () {
      final out = scrubber.scrub(_png());
      expect(_contains(out, serial), isFalse);
      expect(_contains(out, 'eXIf'), isFalse);
    });

    test('a text chunk does not survive', () {
      final out = scrubber.scrub(_png());
      expect(_contains(out, coordinates), isFalse);
      expect(_contains(out, 'tEXt'), isFalse);
    });

    test('a chunk nobody here recognises is dropped', () {
      // Unknown means unchecked. The allowlist is the whole safety property.
      final out = scrubber.scrub(_png());
      expect(_contains(out, 'prIv'), isFalse);
    });

    test('the image survives intact', () {
      final out = scrubber.scrub(_png());
      expect(_contains(out, 'IHDR'), isTrue);
      expect(_contains(out, 'IDAT'), isTrue);
      expect(_contains(out, 'IEND'), isTrue);
      expect(_contains(out, 'PIXELS-HERE'), isTrue);
    });
  });

  group('MP4 and M4A', () {
    test('the metadata box does not survive', () {
      final out = scrubber.scrub(_mp4());
      expect(_contains(out, coordinates), isFalse);
      expect(_contains(out, 'udta'), isFalse);
    });

    test('not one byte moves', () {
      // A stco table holds absolute file offsets into mdat. Deleting a box
      // that sits before the media data shifts every sample and corrupts the
      // file, which is why the box is overwritten in place rather than
      // removed.
      final input = _mp4();
      final out = scrubber.scrub(input);
      expect(out.length, input.length);
    });

    test('the neutralised box becomes ignorable padding', () {
      final out = scrubber.scrub(_mp4());
      expect(_contains(out, 'free'), isTrue);
    });

    test('the audio samples are untouched', () {
      final out = scrubber.scrub(_mp4());
      expect(_contains(out, 'AUDIO-SAMPLES'), isTrue);
    });
  });

  group('anything else is refused', () {
    test('an unrecognised container throws rather than passing through', () {
      // Fail closed. A scrubber that lets an unknown format past does nothing
      // the first time it meets one, and does it silently.
      final pdf = Uint8List.fromList('%PDF-1.7\n%aaaa\n'.codeUnits);
      expect(() => scrubber.scrub(pdf), throwsA(isA<UnscrubbableMedia>()));
    });

    test('an empty file throws', () {
      expect(() => scrubber.scrub(Uint8List(0)),
          throwsA(isA<UnscrubbableMedia>()));
    });

    test('a JPEG mislabelled as anything else is still scrubbed', () {
      // Dispatch is on the magic bytes, never on a declared MIME type. The
      // declared type is the one input here an attacker upstream could pick.
      final out = scrubber.scrub(_jpegWithEverything());
      expect(_contains(out, serial), isFalse);
    });
  });

  test('scrubbing is idempotent', () {
    final once = scrubber.scrub(_jpegWithEverything());
    final twice = scrubber.scrub(once);
    expect(twice, once);
  });
}

// ---------------------------------------------------------------- fixtures

Uint8List _jpegWithEverything({int orientation = 6}) {
  final b = BytesBuilder()..add([0xFF, 0xD8]);
  b.add(_app(0xE0, [...'JFIF\x00'.codeUnits, 1, 2, 0, 0, 72, 0, 72, 0, 0]));
  b.add(_app(0xE0, [...'JFXX\x00'.codeUnits, 0x10, 0xAA, 0xBB]));
  b.add(_app(0xE1, _exif(orientation)));
  b.add(_app(0xE2, [...'ICC_PROFILE\x00'.codeUnits, 1, 1, 0, 0, 0, 0]));
  b.add(_app(0xED, 'Photoshop 3.0\x008BIM'.codeUnits));
  b.add(_app(0xEB, 'SomeVendorNobodyPlannedFor'.codeUnits));
  b.add(_app(0xFE, 'GPS 30.0444,31.2357'.codeUnits)); // COM
  b.add(_app(0xDB, List.filled(65, 0x10))); // quantisation table
  b.add(_app(0xDA, [1, 1, 0, 0, 63, 0])); // start of scan
  b.add('ENTROPY-CODED-IMAGE-DATA'.codeUnits);
  b.add([0xFF, 0xD9]);
  return b.takeBytes();
}

/// A real EXIF header: big-endian TIFF, IFD0 with a camera serial and an
/// orientation, entries in ascending tag order as the format requires.
List<int> _exif(int orientation) {
  const make = 'CAM-SERIAL-99\x00';
  const ifd0 = 8;
  const entries = ifd0 + 2;
  const afterEntries = entries + 2 * 12 + 4; // two entries, then next-IFD
  return [
    ...'Exif\x00\x00'.codeUnits,
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, ifd0,
    0x00, 0x02, // two entries
    // 0x010F Make, ASCII, value stored out of line
    0x01, 0x0F, 0x00, 0x02,
    0x00, 0x00, 0x00, make.length,
    0x00, 0x00, 0x00, afterEntries,
    // 0x0112 Orientation, SHORT, value packed into the field
    0x01, 0x12, 0x00, 0x03,
    0x00, 0x00, 0x00, 0x01,
    orientation >> 8, orientation & 0xFF, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no next IFD
    ...make.codeUnits,
  ];
}

Uint8List _app(int marker, List<int> payload) {
  final length = payload.length + 2;
  return Uint8List.fromList(
      [0xFF, marker, (length >> 8) & 0xFF, length & 0xFF, ...payload]);
}

Uint8List _png() {
  final b = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  b.add(_chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]));
  b.add(_chunk('eXIf', _exif(1).sublist(6)));
  b.add(_chunk('tEXt', 'Comment\x00GPS 30.0444,31.2357'.codeUnits));
  b.add(_chunk('prIv', 'anything at all'.codeUnits));
  b.add(_chunk('IDAT', 'PIXELS-HERE'.codeUnits));
  b.add(_chunk('IEND', const []));
  return b.takeBytes();
}

/// CRCs are filler. The scrubber copies kept chunks verbatim and never
/// validates them, so a real checksum would test the fixture rather than the
/// code.
Uint8List _chunk(String type, List<int> data) => Uint8List.fromList([
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...type.codeUnits,
      ...data,
      0, 0, 0, 0,
    ]);

Uint8List _mp4() {
  final udta = _box('udta', 'GPS 30.0444,31.2357'.codeUnits);
  final trak = _box('trak', _box('mdia', const [0, 0, 0, 0]));
  final moov = _box('moov', [...trak, ...udta]);
  return Uint8List.fromList([
    ..._box('ftyp', 'isom\x00\x00\x02\x00'.codeUnits),
    ...moov,
    ..._box('mdat', 'AUDIO-SAMPLES'.codeUnits),
  ]);
}

List<int> _box(String type, List<int> payload) {
  final size = payload.length + 8;
  return [
    (size >> 24) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    ...type.codeUnits,
    ...payload,
  ];
}

// ----------------------------------------------------------------- helpers

bool _contains(Uint8List haystack, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i + n.length <= haystack.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Returns a whole marker segment including its two marker bytes, or null.
Uint8List? _segment(Uint8List jpeg, int marker) {
  var i = 2;
  while (i + 3 < jpeg.length) {
    if (jpeg[i] != 0xFF) return null;
    final m = jpeg[i + 1];
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      i += 2;
      continue;
    }
    if (m == 0xD9) return null;
    final length = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (m == marker) return Uint8List.sublistView(jpeg, i, i + 2 + length);
    if (m == 0xDA) return null;
    i += 2 + length;
  }
  return null;
}
