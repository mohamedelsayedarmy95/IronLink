import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'secret_store.dart';

/// Raised when a peer presents an identity key different from the one this
/// device already trusts for them.
///
/// This is the signal that matters: it happens on a legitimate reinstall, and
/// it also happens when someone is impersonating the peer. The two are
/// indistinguishable from here, so the decision belongs to the user rather
/// than to a silent default.
class IdentityChanged implements Exception {
  const IdentityChanged(this.address);
  final String address;

  @override
  String toString() => 'identity key changed for $address';
}

/// A [SignalProtocolStore] that survives an app restart.
///
/// The library ships in-memory stores, which lose every session and every
/// private key when the process dies — the ratchet state would be gone and no
/// past or future message could be decrypted. Everything here is private key
/// material, so it lives in [SecretStore] and never in SharedPreferences.
class PersistentSignalStore implements SignalProtocolStore {
  PersistentSignalStore(this._secrets);

  final SecretStore _secrets;

  static const _kIdentity = 'sig.identity';
  static const _kRegistrationId = 'sig.regid';
  static const _kOwner = 'sig.owner';
  static const _kPublished = 'sig.published';
  static const _pPreKey = 'sig.pre.';
  static const _pSignedPreKey = 'sig.spk.';
  static const _pSession = 'sig.sess.';
  static const _pTrusted = 'sig.trust.';

  // Cached because libsignal asks for these on every single operation and
  // each read crosses a platform channel.
  IdentityKeyPair? _identityCache;
  int? _registrationCache;

  String _sessionKey(SignalProtocolAddress a) =>
      '$_pSession${a.getName()}.${a.getDeviceId()}';

  String _trustKey(SignalProtocolAddress a) =>
      '$_pTrusted${a.getName()}.${a.getDeviceId()}';

  Future<Uint8List?> _readBytes(String key) async {
    final raw = await _secrets.read(key);
    return raw == null ? null : base64Decode(raw);
  }

  Future<void> _writeBytes(String key, Uint8List value) =>
      _secrets.write(key, base64Encode(value));

  // ── Installation ──────────────────────────────────────────────────────────

  /// True once this device holds an identity key for [owner].
  ///
  /// Scoped to the owner on purpose. On a shared device a second account must
  /// not inherit the first account's identity key and sessions: it would send
  /// as them, and be able to read their traffic.
  Future<bool> installedFor(String owner) async {
    if (await _secrets.read(_kIdentity) == null) return false;

    final storedOwner = await _secrets.read(_kOwner);
    if (storedOwner == owner) return true;

    // Different user (or key material from before owners were recorded):
    // start clean rather than adopt it.
    await wipe();
    return false;
  }

  /// Generates and stores the long-term identity. Called once per install.
  Future<void> install({
    required String owner,
    required IdentityKeyPair identity,
    required int registrationId,
  }) async {
    await _writeBytes(_kIdentity, identity.serialize());
    await _secrets.write(_kRegistrationId, '$registrationId');
    await _secrets.write(_kOwner, owner);
    _identityCache = identity;
    _registrationCache = registrationId;
  }

  /// Whether the public half of this device's bundle reached the server.
  ///
  /// Tracked separately from being installed, because the two can diverge:
  /// keys are stored locally first (publishing first would advertise keys
  /// whose private halves might not have been saved), so a failed upload
  /// leaves a device that believes it is set up while the directory has
  /// nothing. Every peer then finds no keys and cannot message it — silently,
  /// and forever, because nothing retries.
  Future<bool> get isPublished async =>
      await _secrets.read(_kPublished) == 'true';

  Future<void> markPublished() => _secrets.write(_kPublished, 'true');

  /// Erases every key and session. Used on sign-out: leaving identity keys on
  /// a shared device would let the next person decrypt cached traffic.
  Future<void> wipe() async {
    for (final key in await _secrets.keys()) {
      if (key.startsWith('sig.')) await _secrets.delete(key);
    }
    _identityCache = null;
    _registrationCache = null;
  }

  // ── IdentityKeyStore ──────────────────────────────────────────────────────

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final cached = _identityCache;
    if (cached != null) return cached;

    final raw = await _readBytes(_kIdentity);
    if (raw == null) {
      throw StateError('no identity key — install() has not run');
    }
    return _identityCache = IdentityKeyPair.fromSerialized(raw);
  }

  @override
  Future<int> getLocalRegistrationId() async {
    final cached = _registrationCache;
    if (cached != null) return cached;

    final raw = await _secrets.read(_kRegistrationId);
    if (raw == null) {
      throw StateError('no registration id — install() has not run');
    }
    return _registrationCache = int.parse(raw);
  }

  @override
  Future<bool> saveIdentity(
      SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;

    final existing = await getIdentity(address);
    await _writeBytes(_trustKey(address), identityKey.serialize());

    // The return value means "this replaced a different key", which is what
    // callers use to decide whether to warn the user.
    return existing != null && existing != identityKey;
  }

  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
      IdentityKey? identityKey, Direction direction) async {
    if (identityKey == null) return false;

    final known = await getIdentity(address);
    // Trust on first use: there is no prior key to compare against, and
    // refusing here would make the first message to anyone impossible.
    if (known == null) return true;

    // A changed key is refused rather than accepted-with-a-warning. In a
    // product whose premise is a trustworthy channel, silently continuing
    // through a key change is the one behaviour an attacker needs.
    return known == identityKey;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final raw = await _readBytes(_trustKey(address));
    return raw == null ? null : IdentityKey.fromBytes(raw, 0);
  }

  /// Accepts a peer's new identity key after the user has confirmed it.
  ///
  /// Deliberately separate from [saveIdentity]: replacing a trusted key is a
  /// decision, not a side effect of receiving a message.
  Future<void> acceptNewIdentity(
      SignalProtocolAddress address, IdentityKey identityKey) async {
    await _writeBytes(_trustKey(address), identityKey.serialize());
    // The old session is built on the old identity and cannot continue.
    await deleteSession(address);
  }

  // ── PreKeyStore ───────────────────────────────────────────────────────────

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final raw = await _readBytes('$_pPreKey$preKeyId');
    if (raw == null) throw InvalidKeyIdException('no pre-key $preKeyId');
    return PreKeyRecord.fromBuffer(raw);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _writeBytes('$_pPreKey$preKeyId', record.serialize());

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      await _secrets.read('$_pPreKey$preKeyId') != null;

  @override
  Future<void> removePreKey(int preKeyId) =>
      _secrets.delete('$_pPreKey$preKeyId');

  /// Pre-key ids this device still holds privately. Compared against the
  /// server's count to decide when to replenish.
  Future<Set<int>> localPreKeyIds() async => {
        for (final key in await _secrets.keys())
          if (key.startsWith(_pPreKey))
            int.parse(key.substring(_pPreKey.length))
      };

  // ── SignedPreKeyStore ─────────────────────────────────────────────────────

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final raw = await _readBytes('$_pSignedPreKey$signedPreKeyId');
    if (raw == null) {
      throw InvalidKeyIdException('no signed pre-key $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(raw);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final records = <SignedPreKeyRecord>[];
    for (final key in await _secrets.keys()) {
      if (!key.startsWith(_pSignedPreKey)) continue;
      final raw = await _readBytes(key);
      if (raw != null) records.add(SignedPreKeyRecord.fromSerialized(raw));
    }
    return records;
  }

  @override
  Future<void> storeSignedPreKey(
          int signedPreKeyId, SignedPreKeyRecord record) =>
      _writeBytes('$_pSignedPreKey$signedPreKeyId', record.serialize());

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      await _secrets.read('$_pSignedPreKey$signedPreKeyId') != null;

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) =>
      _secrets.delete('$_pSignedPreKey$signedPreKeyId');

  // ── SessionStore ──────────────────────────────────────────────────────────

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final raw = await _readBytes(_sessionKey(address));
    // A fresh record rather than an error: this is how libsignal asks
    // "do we have a session", and an empty one means no.
    return raw == null ? SessionRecord() : SessionRecord.fromSerialized(raw);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final prefix = '$_pSession$name.';
    return [
      for (final key in await _secrets.keys())
        if (key.startsWith(prefix))
          if (int.tryParse(key.substring(prefix.length)) case final id?)
            if (id != 1) id
    ];
  }

  @override
  Future<void> storeSession(
          SignalProtocolAddress address, SessionRecord record) =>
      _writeBytes(_sessionKey(address), record.serialize());

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final raw = await _readBytes(_sessionKey(address));
    if (raw == null) return false;
    // A stored-but-uninitialised record is not a usable session; treating it
    // as one would send a message the peer cannot decrypt.
    return SessionRecord.fromSerialized(raw).sessionState.hasSenderChain();
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _secrets.delete(_sessionKey(address));

  @override
  Future<void> deleteAllSessions(String name) async {
    final prefix = '$_pSession$name.';
    for (final key in await _secrets.keys()) {
      if (key.startsWith(prefix)) await _secrets.delete(key);
    }
  }
}
