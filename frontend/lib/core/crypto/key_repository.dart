import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show DioException, Options;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../api_client.dart';

/// A peer's public bundle, as returned by the key directory.
class RemoteKeyBundle {
  const RemoteKeyBundle({
    required this.registrationId,
    required this.identityKey,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    this.oneTimePreKeyId,
    this.oneTimePreKey,
  });

  final int registrationId;
  final Uint8List identityKey;
  final int signedPreKeyId;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;

  /// Null when the peer has run out. libsignal still opens a session; only
  /// the forward secrecy of the very first message is weaker.
  final int? oneTimePreKeyId;
  final Uint8List? oneTimePreKey;

  factory RemoteKeyBundle.fromJson(Map<String, dynamic> json) =>
      RemoteKeyBundle(
        registrationId: (json['registration_id'] as num).toInt(),
        identityKey: base64Decode(json['identity_key'] as String),
        signedPreKeyId: (json['signed_prekey_id'] as num).toInt(),
        signedPreKeyPublic:
            base64Decode(json['signed_prekey_public'] as String),
        signedPreKeySignature:
            base64Decode(json['signed_prekey_signature'] as String),
        oneTimePreKeyId: (json['one_time_prekey_id'] as num?)?.toInt(),
        oneTimePreKey: json['one_time_prekey'] == null
            ? null
            : base64Decode(json['one_time_prekey'] as String),
      );

  /// Converts to the library's type.
  ///
  /// `processPreKeyBundle` verifies signedPreKeySignature against identityKey
  /// before using any of this. That check is the whole reason the server can
  /// be untrusted: without it, the directory could hand out its own keys and
  /// read everything.
  PreKeyBundle toPreKeyBundle({int deviceId = 1}) => PreKeyBundle(
        registrationId,
        deviceId,
        oneTimePreKeyId,
        oneTimePreKey == null ? null : Curve.decodePoint(oneTimePreKey!, 0),
        signedPreKeyId,
        Curve.decodePoint(signedPreKeyPublic, 0),
        signedPreKeySignature,
        IdentityKey.fromBytes(identityKey, 0),
      );
}

/// Talks to the public key directory.
///
/// Every value crossing this class is public key material. Nothing here ever
/// sends a private key — see the contract in app/api/routes/keys.py.
class KeyRepository {
  KeyRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> publishBundle({
    required int registrationId,
    required IdentityKey identityKey,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord> oneTimePreKeys,
  }) async {
    await _api.dio.post<void>(
      '/keys/bundle',
      data: {
        'registration_id': registrationId,
        'identity_key': base64Encode(identityKey.serialize()),
        'signed_prekey_id': signedPreKey.id,
        'signed_prekey_public':
            base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signed_prekey_signature': base64Encode(signedPreKey.signature),
        'one_time_prekeys': [
          for (final pk in oneTimePreKeys)
            {
              'key_id': pk.id,
              'public_key': base64Encode(pk.getKeyPair().publicKey.serialize()),
            }
        ],
      },
      options: await _auth(),
    );
  }

  Future<void> replenishPreKeys(List<PreKeyRecord> preKeys) async {
    if (preKeys.isEmpty) return;
    await _api.dio.post<void>(
      '/keys/prekeys',
      data: {
        'one_time_prekeys': [
          for (final pk in preKeys)
            {
              'key_id': pk.id,
              'public_key': base64Encode(pk.getKeyPair().publicKey.serialize()),
            }
        ],
      },
      options: await _auth(),
    );
  }

  Future<int> remainingPreKeys() async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/keys/prekeys/count',
      options: await _auth(),
    );
    return ((res.data ?? const {})['remaining'] as num?)?.toInt() ?? 0;
  }

  /// Fetches a peer's bundle, consuming one of their one-time pre-keys.
  ///
  /// Returns null when the peer has never published keys, which means they
  /// cannot receive an encrypted message at all.
  Future<RemoteKeyBundle?> fetchBundle(String userId) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/keys/bundle/$userId',
        options: await _auth(),
      );
      return RemoteKeyBundle.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
