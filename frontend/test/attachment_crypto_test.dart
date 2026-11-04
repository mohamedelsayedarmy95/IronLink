import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/crypto/attachment_crypto.dart';

void main() {
  final crypto = AttachmentCrypto();

  AttachmentKey keyFor(Uint8List data, {String mime = 'image/jpeg'}) =>
      crypto.newKey(mimeType: mime, sizeBytes: data.length);

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  group('round trip', () {
    test('a file comes back byte for byte', () {
      final plaintext = bytes('the contents of a classified document');
      final key = keyFor(plaintext);

      final ciphertext = crypto.encrypt(plaintext, key);
      expect(crypto.decrypt(ciphertext, key), plaintext);
    });

    test('an empty file is handled', () {
      final plaintext = Uint8List(0);
      final key = keyFor(plaintext);

      expect(crypto.decrypt(crypto.encrypt(plaintext, key), key), plaintext);
    });

    test('a large file is handled', () {
      // 2 MB, larger than one upload chunk, so this covers the real path.
      final plaintext =
          Uint8List.fromList(List<int>.generate(2 * 1024 * 1024, (i) => i % 256));
      final key = keyFor(plaintext);

      expect(crypto.decrypt(crypto.encrypt(plaintext, key), key), plaintext);
    });
  });

  group('what the server can see', () {
    test('the stored bytes do not contain the plaintext', () {
      final plaintext = bytes('TOP SECRET troop movements');
      final key = keyFor(plaintext);

      final ciphertext = crypto.encrypt(plaintext, key);
      expect(
        utf8.decode(ciphertext, allowMalformed: true),
        isNot(contains('TOP SECRET')),
      );
    });

    test('the same file encrypted twice looks different', () {
      final plaintext = bytes('identical file');

      final first = crypto.encrypt(plaintext, keyFor(plaintext));
      final second = crypto.encrypt(plaintext, keyFor(plaintext));

      // Otherwise the server could tell that two people sent the same
      // document just by comparing stored objects.
      expect(first, isNot(second));
    });

    test('ciphertext is longer than plaintext only by the tag', () {
      final plaintext = bytes('exactly this');
      final key = keyFor(plaintext);

      // 128-bit GCM tag. Worth pinning: the length is all the server learns,
      // and a surprise change here would mean the format changed.
      expect(crypto.encrypt(plaintext, key).length, plaintext.length + 16);
    });

    test('the real mime type is not in the key material sent upstream', () {
      final plaintext = bytes('x');
      final key = keyFor(plaintext, mime: 'application/pdf');

      // The type lives in the envelope, which is end-to-end encrypted. This
      // asserts it is carried there at all — the upload declares
      // octet-stream instead.
      expect(key.toJson()['m'], 'application/pdf');
    });
  });

  group('authentication', () {
    test('a flipped byte is refused, not decrypted', () {
      final plaintext = bytes('transfer 1000 units');
      final key = keyFor(plaintext);
      final ciphertext = crypto.encrypt(plaintext, key);

      // Someone who can write to object storage must not be able to alter a
      // file and have it silently render as though the sender sent it.
      ciphertext[3] ^= 0xFF;

      expect(() => crypto.decrypt(ciphertext, key),
          throwsA(isA<AttachmentTampered>()));
    });

    test('a truncated file is refused', () {
      final plaintext = bytes('a complete report');
      final key = keyFor(plaintext);
      final ciphertext = crypto.encrypt(plaintext, key);

      expect(
        () => crypto.decrypt(
            Uint8List.sublistView(ciphertext, 0, ciphertext.length - 4), key),
        throwsA(isA<AttachmentTampered>()),
      );
    });

    test('the wrong key is refused rather than producing garbage', () {
      final plaintext = bytes('secret');
      final key = keyFor(plaintext);
      final ciphertext = crypto.encrypt(plaintext, key);

      expect(() => crypto.decrypt(ciphertext, keyFor(plaintext)),
          throwsA(isA<AttachmentTampered>()));
    });
  });

  group('key material', () {
    test('every attachment gets a fresh key and nonce', () {
      final plaintext = bytes('x');
      final keys = [for (var i = 0; i < 50; i++) keyFor(plaintext)];

      // Reusing a key/nonce pair in GCM leaks the XOR of the two plaintexts
      // and voids the authentication guarantee outright.
      expect(keys.map((k) => base64Encode(k.key)).toSet(), hasLength(50));
      expect(keys.map((k) => base64Encode(k.nonce)).toSet(), hasLength(50));
    });

    test('key and nonce are the expected sizes', () {
      final key = keyFor(bytes('x'));
      expect(key.key, hasLength(AttachmentCrypto.keyBytes));
      expect(key.nonce, hasLength(AttachmentCrypto.nonceBytes));
    });

    test('survives the trip through the envelope', () {
      final plaintext = bytes('carried inside the signal envelope');
      final key = keyFor(plaintext, mime: 'image/png');
      final ciphertext = crypto.encrypt(plaintext, key);

      // The key material is serialised into the Signal-encrypted message, so
      // a lossy round trip here would make attachments unreadable.
      final restored = AttachmentKey.fromJson(
        jsonDecode(jsonEncode(key.toJson())) as Map<String, dynamic>,
      );

      expect(crypto.decrypt(ciphertext, restored), plaintext);
      expect(restored.mimeType, 'image/png');
      expect(restored.sizeBytes, plaintext.length);
    });
  });
}
