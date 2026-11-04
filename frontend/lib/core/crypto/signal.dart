import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'key_repository.dart';
import 'secret_store.dart';
import 'signal_store.dart';

export 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show DuplicateMessageException, IdentityKey;
export 'signal_store.dart' show IdentityChanged;

/// Raised when a message cannot be encrypted or decrypted.
///
/// Every failure path in this file ends here rather than falling back to
/// plaintext. A secret chat that quietly downgrades is worse than one that
/// refuses to send: the user believes they are protected and is not.
class EncryptionFailed implements Exception {
  const EncryptionFailed(this.reason);
  final String reason;

  @override
  String toString() => 'encryption failed: $reason';
}

/// The peer has never published keys, so nothing can be sent to them.
class PeerHasNoKeys implements Exception {
  const PeerHasNoKeys(this.userId);
  final String userId;
}

/// Signal Protocol E2EE.
///
/// X3DH key agreement and the Double Ratchet are provided by
/// libsignal_protocol_dart; this class owns installation, the key directory
/// exchange, and the on-the-wire envelope. No cryptographic primitive is
/// implemented here on purpose — hand-rolled crypto is how these systems fail.
class SignalService {
  SignalService(
    this.userId, {
    required KeyRepository keys,
    SecretStore? secrets,
    PersistentSignalStore? store,
  })  : _keys = keys,
        _store = store ?? PersistentSignalStore(secrets ?? SecureSecretStore());

  final String userId;
  final KeyRepository _keys;
  final PersistentSignalStore _store;

  /// This app runs one device per account. The field exists because the
  /// protocol addresses sessions by (user, device) and multi-device would
  /// otherwise require a migration of every stored session key.
  static const deviceId = 1;

  /// Generated per install. 100 is what Signal itself uses.
  static const _preKeyBatch = 100;

  /// Replenish before running out: a peer who claims the last one leaves
  /// later senders with a weaker first message.
  static const preKeyLowWaterMark = 20;

  /// How long a signed pre-key may stay in service.
  ///
  /// Two days, matching Signal. It bounds the damage from that key being
  /// obtained: sessions opened before the rotation stay exposed, sessions
  /// after it do not.
  static const signedPreKeyMaxAge = Duration(days: 2);

  PersistentSignalStore get store => _store;

  SignalProtocolAddress _address(String remoteUserId) =>
      SignalProtocolAddress(remoteUserId, deviceId);

  // ── Installation ──────────────────────────────────────────────────────────

  /// Generates this device's keys and publishes the public half.
  ///
  /// Safe to call on every launch: it returns immediately once installed.
  Future<void> ensureInstalled() async {
    if (await _store.installedFor(userId)) {
      // Installed locally, but the upload may never have landed. Retried on
      // every launch until it does — otherwise one failed request at first
      // login leaves this device permanently unreachable, with peers simply
      // finding no keys for it.
      if (!await _store.isPublished) {
        await _publishExisting();
        return;
      }
      await _rotateSignedPreKeyIfStale();
      await _replenishIfLow();
      return;
    }

    final identity = generateIdentityKeyPair();
    // Not the extended range: the server bounds registration_id to 14 bits,
    // and a wider value would be rejected at upload.
    final registrationId = generateRegistrationId(false);
    await _store.install(
      owner: userId,
      identity: identity,
      registrationId: registrationId,
    );

    final signedPreKey = generateSignedPreKey(identity, 1);
    await _store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    final preKeys = generatePreKeys(1, _preKeyBatch);
    for (final pk in preKeys) {
      await _store.storePreKey(pk.id, pk);
    }

    // Published last: publishing first would advertise keys whose private
    // halves might not have been stored. If it throws, the keys stay and
    // ensureInstalled retries the upload on the next launch — which only
    // works because "published" is recorded separately from "installed".
    await _keys.publishBundle(
      registrationId: registrationId,
      identityKey: identity.getPublicKey(),
      signedPreKey: signedPreKey,
      oneTimePreKeys: preKeys,
    );
    await _store.markPublished();
  }

  /// Uploads the bundle for keys this device already holds.
  ///
  /// Reuses the stored identity and signed pre-key rather than generating new
  /// ones: regenerating would change this device's identity every time an
  /// upload failed, invalidating sessions that peers had already built.
  Future<void> _publishExisting() async {
    final identity = await _store.getIdentityKeyPair();
    final registrationId = await _store.getLocalRegistrationId();

    final signedPreKeys = await _store.loadSignedPreKeys();
    if (signedPreKeys.isEmpty) return;

    final preKeys = <PreKeyRecord>[];
    for (final id in await _store.localPreKeyIds()) {
      preKeys.add(await _store.loadPreKey(id));
    }

    await _keys.publishBundle(
      registrationId: registrationId,
      identityKey: identity.getPublicKey(),
      signedPreKey: signedPreKeys.first,
      // The server caps a single upload; the rest replenish later.
      oneTimePreKeys: preKeys.take(_preKeyBatch).toList(),
    );
    await _store.markPublished();
  }

  /// Replaces the signed pre-key once it is older than [signedPreKeyMaxAge].
  ///
  /// It was generated once at install, with id 1, and kept forever. A signed
  /// pre-key is the long-lived half of session establishment: every session
  /// opened with it derives from that one private key, so a device that never
  /// rotates gives an attacker who eventually obtains it the ability to
  /// decrypt every session ever started with that device. Rotation bounds
  /// that window to the age of the key.
  ///
  /// The previous one is deliberately kept in the store rather than deleted.
  /// Someone may have fetched the old bundle moments before this ran, and
  /// their PreKeySignalMessage still names it; discarding it immediately
  /// would make that first message undecryptable for no benefit.
  Future<void> _rotateSignedPreKeyIfStale() async {
    try {
      final existing = await _store.loadSignedPreKeys();
      if (existing.isEmpty) return;

      existing.sort((a, b) => b.id.compareTo(a.id));
      final newest = existing.first;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(newest.timestamp.toInt()),
      );
      if (age < signedPreKeyMaxAge) return;

      final identity = await _store.getIdentityKeyPair();
      final rotated = generateSignedPreKey(identity, newest.id + 1);
      await _store.storeSignedPreKey(rotated.id, rotated);

      await _keys.publishBundle(
        registrationId: await _store.getLocalRegistrationId(),
        identityKey: identity.getPublicKey(),
        signedPreKey: rotated,
        // None: the existing ones are still valid and unclaimed. Sending a
        // fresh batch here would replace the server's set on every rotation.
        oneTimePreKeys: const [],
      );

      // Two generations kept, so a bundle fetched just before the rotation
      // still opens. Older ones are past any plausible in-flight window.
      for (final old in existing.skip(1)) {
        await _store.removeSignedPreKey(old.id);
      }
    } catch (e) {
      // Not fatal: the current key still works. Retried next launch.
      debugPrint('[signal] signed pre-key rotation skipped: $e');
    }
  }

  Future<void> _replenishIfLow() async {
    try {
      final remaining = await _keys.remainingPreKeys();
      if (remaining >= preKeyLowWaterMark) return;

      // Continue past the highest id this device already holds, so a
      // replenished key never collides with one still in use.
      final existing = await _store.localPreKeyIds();
      final start = (existing.isEmpty ? 0 : existing.reduce((a, b) => a > b ? a : b)) + 1;

      final fresh = generatePreKeys(start, _preKeyBatch - remaining);
      for (final pk in fresh) {
        await _store.storePreKey(pk.id, pk);
      }
      await _keys.replenishPreKeys(fresh);
    } catch (e) {
      // Running low is not fatal — sessions still open without a one-time
      // pre-key — so this must not block the app from starting.
      debugPrint('[signal] pre-key replenish skipped: $e');
    }
  }

  /// Drops all key material. Called on sign-out.
  Future<void> reset() => _store.wipe();

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<bool> hasSession(String remoteUserId) =>
      _store.containsSession(_address(remoteUserId));

  /// Opens a session by fetching the peer's bundle and running X3DH.
  ///
  /// Throws [IdentityChanged] if the peer's identity key differs from the one
  /// already trusted — the user has to decide, because a reinstall and an
  /// impersonation look identical from here.
  Future<void> openSession(String remoteUserId) async {
    final address = _address(remoteUserId);
    final bundle = await _keys.fetchBundle(remoteUserId);
    if (bundle == null) throw PeerHasNoKeys(remoteUserId);

    final builder = SessionBuilder.fromSignalStore(_store, address);
    try {
      // Verifies the signed pre-key signature against the identity key
      // before deriving anything, which is what makes an untrusted server
      // acceptable here.
      await builder.processPreKeyBundle(bundle.toPreKeyBundle(
        deviceId: deviceId,
      ));
    } on UntrustedIdentityException {
      throw IdentityChanged(remoteUserId);
    } on InvalidKeyException catch (e) {
      // A bad signature means the bundle was not produced by the holder of
      // that identity key. Refuse rather than continue.
      throw EncryptionFailed('peer key bundle failed verification: $e');
    }
  }

  /// Accepts a peer's changed identity after the user confirms it.
  Future<void> acceptIdentityChange(
      String remoteUserId, IdentityKey identityKey) =>
      _store.acceptNewIdentity(_address(remoteUserId), identityKey);

  // ── Envelope ──────────────────────────────────────────────────────────────
  //
  // The wire format has to carry the message type. A pre-key message (the
  // first of a session) and a normal ratchet message are decrypted by
  // different calls, and guessing wrong fails on every message.

  static const _envelopeVersion = 1;

  /// Whether [content] is one of our envelopes.
  ///
  /// Used to tell an encrypted message from a legacy plaintext one during the
  /// transition to encryption-by-default. Deliberately strict: it requires
  /// the exact shape, a known version, and a known message type, so ordinary
  /// text that happens to be JSON is not mistaken for an envelope.
  ///
  /// This check decides whether a message is *treated* as encrypted, never
  /// whether it is *displayed*. A message that fails it is still shown, but
  /// visibly marked as unencrypted — otherwise this would be the very
  /// downgrade path the rest of this class refuses to open.
  static bool isEnvelope(String? content) {
    if (content == null || !content.startsWith('{')) return false;
    try {
      final parsed = jsonDecode(content);
      return parsed is Map<String, dynamic> &&
          parsed['v'] == _envelopeVersion &&
          parsed['b'] is String &&
          (parsed['t'] == CiphertextMessage.prekeyType ||
              parsed['t'] == CiphertextMessage.whisperType);
    } catch (_) {
      return false;
    }
  }

  String _wrap(CiphertextMessage message) => jsonEncode({
        'v': _envelopeVersion,
        't': message.getType(),
        'b': base64Encode(message.serialize()),
      });

  // ── Encrypt / decrypt ─────────────────────────────────────────────────────

  /// Encrypts for [remoteUserId], opening a session if there is not one.
  ///
  /// Returns the envelope to put on the wire. Throws rather than returning
  /// anything readable if encryption is not possible.
  Future<String> encrypt(String plaintext, String remoteUserId) async {
    if (!await hasSession(remoteUserId)) {
      await openSession(remoteUserId);
    }

    final cipher = SessionCipher.fromStore(_store, _address(remoteUserId));
    try {
      final message = await cipher.encrypt(
        Uint8List.fromList(utf8.encode(plaintext)),
      );
      return _wrap(message);
    } on UntrustedIdentityException {
      throw IdentityChanged(remoteUserId);
    }
  }

  /// Decrypts an envelope produced by [encrypt].
  Future<String> decrypt(String envelope, String remoteUserId) async {
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(envelope) as Map<String, dynamic>;
    } catch (_) {
      // Anything that is not an envelope is not something this device can
      // read. Returning the raw text would display ciphertext — or, worse,
      // present an unencrypted message as though it had been encrypted.
      throw const EncryptionFailed('message is not an encrypted envelope');
    }

    if (parsed['v'] != _envelopeVersion) {
      throw EncryptionFailed('unsupported envelope version ${parsed['v']}');
    }

    final body = base64Decode(parsed['b'] as String);
    final cipher = SessionCipher.fromStore(_store, _address(remoteUserId));

    try {
      final plaintext = switch (parsed['t']) {
        CiphertextMessage.prekeyType =>
          await cipher.decrypt(PreKeySignalMessage(body)),
        CiphertextMessage.whisperType =>
          await cipher.decryptFromSignal(SignalMessage.fromSerialized(body)),
        _ => throw EncryptionFailed('unknown message type ${parsed['t']}'),
      };
      return utf8.decode(plaintext);
    } on UntrustedIdentityException {
      throw IdentityChanged(remoteUserId);
    } on DuplicateMessageException {
      // The ratchet refuses to process the same message twice. That is a
      // replay defence working, not a failure, so it passes through for the
      // caller to drop the duplicate quietly.
      rethrow;
    } catch (e) {
      // Everything else — bad MAC, malformed message, missing session — is
      // a decryption failure. Caught broadly on purpose: the library does
      // not export all of its exception types, and an uncaught one here
      // would escape as an unhandled error rather than a handled refusal.
      throw EncryptionFailed('$e');
    }
  }
}
