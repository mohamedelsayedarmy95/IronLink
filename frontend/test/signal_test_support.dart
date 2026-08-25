import 'dart:convert';

import 'package:ironlink/core/crypto/key_repository.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// A stand-in for the key directory that behaves the way the real server does:
/// it holds only public material, and it hands out each one-time pre-key once.
///
/// This is what makes the crypto tests meaningful — the devices under test
/// share nothing except what actually crosses the wire, so a successful
/// exchange proves they really did agree on a key without the directory
/// knowing it.
class FakeDirectory implements KeyRepository {
  final Map<String, Map<String, dynamic>> _bundles = {};
  final Map<String, List<PreKeyRecord>> _preKeys = {};

  /// Set by the service under test before publishing.
  String? publishingAs;

  int handedOutWithoutOneTimeKey = 0;

  /// How many bundles have been published, so a test can assert a device does
  /// not needlessly re-upload on every launch.
  int publishCount = 0;

  /// Makes the next publish fail, standing in for the 401 seen on a real
  /// device when the auth token could not be read.
  bool failNextPublish = false;

  /// Lets a test replace a published bundle, to simulate a malicious server.
  void overrideBundle(String userId, Map<String, dynamic> bundle) {
    _bundles[userId] = bundle;
  }

  Map<String, dynamic>? rawBundle(String userId) => _bundles[userId];

  /// Empties a user's one-time pre-keys, as happens when someone has been
  /// offline while many people started conversations with them.
  void drainPreKeys(String userId) => _preKeys[userId]?.clear();

  @override
  Future<void> publishBundle({
    required int registrationId,
    required IdentityKey identityKey,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord> oneTimePreKeys,
  }) async {
    if (failNextPublish) {
      failNextPublish = false;
      throw Exception('publish rejected (401)');
    }
    publishCount++;

    final user = publishingAs!;
    _bundles[user] = {
      'registration_id': registrationId,
      'identity_key': base64Encode(identityKey.serialize()),
      'signed_prekey_id': signedPreKey.id,
      'signed_prekey_public':
          base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signed_prekey_signature': base64Encode(signedPreKey.signature),
    };
    _preKeys[user] = [...oneTimePreKeys];
  }

  @override
  Future<void> replenishPreKeys(List<PreKeyRecord> preKeys) async {
    (_preKeys[publishingAs!] ??= []).addAll(preKeys);
  }

  @override
  Future<int> remainingPreKeys() async => _preKeys[publishingAs]?.length ?? 0;

  @override
  Future<RemoteKeyBundle?> fetchBundle(String userId) async {
    final bundle = _bundles[userId];
    if (bundle == null) return null;

    final available = _preKeys[userId] ?? [];
    final json = Map<String, dynamic>.from(bundle);
    if (available.isEmpty) {
      handedOutWithoutOneTimeKey++;
    } else {
      // Claimed, exactly as the server's DELETE ... RETURNING does.
      final claimed = available.removeAt(0);
      json['one_time_prekey_id'] = claimed.id;
      json['one_time_prekey'] =
          base64Encode(claimed.getKeyPair().publicKey.serialize());
    }
    return RemoteKeyBundle.fromJson(json);
  }
}
