import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The key material needed to read one encrypted attachment.
///
/// Travels inside the Signal envelope alongside the caption, so it is
/// end-to-end encrypted like the message text. It must never be sent to the
/// server: with it, the stored object stops being opaque.
class AttachmentKey {
  const AttachmentKey({
    required this.key,
    required this.nonce,
    required this.mimeType,
    required this.sizeBytes,
  });

  final Uint8List key;
  final Uint8List nonce;

  /// The real type, kept here rather than on the object: the server is told
  /// only that it holds opaque bytes, so "this is a PDF" would otherwise leak
  /// from the storage metadata.
  final String mimeType;

  /// Plaintext length. The stored object is longer by the GCM tag.
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
        'k': base64Encode(key),
        'n': base64Encode(nonce),
        'm': mimeType,
        's': sizeBytes,
      };

  factory AttachmentKey.fromJson(Map<String, dynamic> json) => AttachmentKey(
        key: base64Decode(json['k'] as String),
        nonce: base64Decode(json['n'] as String),
        mimeType: json['m'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['s'] as num?)?.toInt() ?? 0,
      );
}

/// Raised when an attachment fails its authentication check.
///
/// This is not a corrupt-download error to retry past: GCM failing means the
/// bytes are not what the sender produced.
class AttachmentTampered implements Exception {
  const AttachmentTampered();

  @override
  String toString() => 'attachment failed authentication';
}

/// AES-256-GCM for attachment bodies.
///
/// GCM rather than CBC because it authenticates: without a tag, an attacker
/// who can write to storage could flip bits in an image and the recipient
/// would decrypt and display the result with no indication anything changed.
class AttachmentCrypto {
  AttachmentCrypto([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  static const keyBytes = 32; // AES-256
  static const nonceBytes = 12; // GCM standard; 96 bits
  static const _tagBits = 128;

  Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );

  /// A fresh key for one attachment.
  ///
  /// Per attachment, never per conversation: reusing a key and nonce pair
  /// across two files in GCM leaks the XOR of their plaintexts and destroys
  /// the authentication guarantee entirely.
  AttachmentKey newKey({required String mimeType, required int sizeBytes}) =>
      AttachmentKey(
        key: _randomBytes(keyBytes),
        nonce: _randomBytes(nonceBytes),
        mimeType: mimeType,
        sizeBytes: sizeBytes,
      );

  GCMBlockCipher _cipher(AttachmentKey material, {required bool encrypt}) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(
          KeyParameter(material.key),
          _tagBits,
          material.nonce,
          Uint8List(0), // no associated data
        ),
      );
    return gcm;
  }

  /// Returns ciphertext with the authentication tag appended.
  Uint8List encrypt(Uint8List plaintext, AttachmentKey material) =>
      _cipher(material, encrypt: true).process(plaintext);

  /// Verifies the tag and returns the plaintext.
  Uint8List decrypt(Uint8List ciphertext, AttachmentKey material) {
    try {
      return _cipher(material, encrypt: false).process(ciphertext);
    } on InvalidCipherTextException {
      // The tag did not verify: wrong key, or the bytes were altered in
      // storage. Either way the content cannot be trusted.
      throw const AttachmentTampered();
    }
  }
}
