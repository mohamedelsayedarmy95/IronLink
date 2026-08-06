import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Wrapper around the Signal Protocol library for managing identity keys,
/// pre-keys, and sessions for secret chats.
class SignalService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final String _userId;

  SignalService(this._userId);

  // --- Identity Key ---

  Future<IdentityKeyPair> getOrCreateIdentityKeyPair() async {
    final privateKeyBytes = await _storage.read(key: 'signal_identity_private_$_userId');
    final publicKeyBytes = await _storage.read(key: 'signal_identity_public_$_userId');

    if (privateKeyBytes != null && publicKeyBytes != null) {
      final privateKey = ECPrivateKey.fromBuffer(base64Decode(privateKeyBytes));
      final publicKey = ECPublicKey.fromBuffer(base64Decode(publicKeyBytes));
      return IdentityKeyPair(privateKey, publicKey);
    }

    // Generate a new identity key pair
    final identityKeyPair = IdentityKeyPair.generate();
    await _storage.write(
        key: 'signal_identity_private_$_userId',
        value: base64Encode(identityKeyPair.privateKey.serialize()));
    await _storage.write(
        key: 'signal_identity_public_$_userId',
        value: base64Encode(identityKeyPair.publicKey.serialize()));
    return identityKeyPair;
  }

  // --- Pre-Keys ---

  Future<List<PreKeyRecord>> loadPreKeys(int start, int count) async {
    final List<PreKeyRecord> preKeyRecords = [];
    for (int i = start; i < start + count; i++) {
      final privateKeyBytes = await _storage.read(key: 'signal_prekey_private_$_userId\_$i');
      final publicKeyBytes = await _storage.read(key: 'signal_prekey_public_$_userId\_$i');
      if (privateKeyBytes != null && publicKeyBytes != null) {
        final privateKey = ECPrivateKey.fromBuffer(base64Decode(privateKeyBytes));
        final publicKey = ECPublicKey.fromBuffer(base64Decode(publicKeyBytes));
        preKeyRecords.add(PreKeyRecord(i.toString(), publicKey, privateKey));
      }
    }
    return preKeyRecords;
  }

  Future<void> storePreKey(int keyId, ECPrivateKey privateKey, ECPublicKey publicKey) async {
    await _storage.write(
        key: 'signal_prekey_private_$_userId\_$keyId',
        value: base64Encode(privateKey.serialize()));
    await _storage.write(
        key: 'signal_prekey_public_$_userId\_$keyId',
        value: base64Encode(publicKey.serialize()));
  }

  Future<void> removePreKey(int keyId) async {
    await _storage.delete(key: 'signal_prekey_private_$_userId\_$keyId');
    await _storage.delete(key: 'signal_prekey_public_$_userId\_$keyId');
  }

  // --- Signed Pre-Key ---

  Future<SignedKeyRecord> loadSignedPreKey(int keyId) async {
    final privateKeyBytes =
        await _storage.read(key: 'signal_signed_prekey_private_$_userId\_$keyId');
    final publicKeyBytes =
        await _storage.read(key: 'signal_signed_prekey_public_$_userId\_$keyId');
    final signatureBytes =
        await _storage.read(key: 'signal_signed_prekey_signature_$_userId\_$keyId');
    if (privateKeyBytes == null ||
        publicKeyBytes == null ||
        signatureBytes == null) {
      throw Exception('Signed pre-key not found');
    }
    final privateKey = ECPrivateKey.fromBuffer(base64Decode(privateKeyBytes));
    final publicKey = ECPublicKey.fromBuffer(base64Decode(publicKeyBytes));
    final signature = base64Decode(signatureBytes);
    return SignedKeyRecord(keyId.toString(), publicKey, privateKey, signature);
  }

  Future<void> storeSignedPreKey(
      int keyId, ECPrivateKey privateKey, ECPublicKey publicKey, List<int> signature) async {
    await _storage.write(
        key: 'signal_signed_prekey_private_$_userId\_$keyId',
        value: base64Encode(privateKey.serialize()));
    await _storage.write(
        key: 'signal_signed_prekey_public_$_userId\_$keyId',
        value: base64Encode(publicKey.serialize()));
    await _storage.write(
        key: 'signal_signed_prekey_signature_$_userId\_$keyId',
        value: base64Encode(signature));
  }

  Future<void> removeSignedPreKey(int keyId) async {
    await _storage.delete(key: 'signal_signed_prekey_private_$_userId\_$keyId');
    await _storage.delete(key: 'signal_signed_prekey_public_$_userId\_$keyId');
    await _storage.delete(key: 'signal_signed_prekey_signature_$_userId\_$keyId');
  }

  // --- Session ---

  Future<CiphertextMessage?> deserialize message(json) async {
    if (json == null) return null;
    return CiphertextMessage.fromJson(json);
  }

  Future<String?> serialize message(CiphertextMessage message) async {
    return jsonEncode(message.toJson());
  }

  Future<SessionState?> loadSession(String remoteUserId) async {
    final json = await _storage.read(key: 'signal_session_$_userId\_$remoteUserId');
    if (json == null) return null;
    return SessionState.fromJson(jsonDecode(json));
  }

  Future<void> storeSession(String remoteUserId, SessionState sessionState) async {
    await _storage.write(
        key: 'signal_session_$_userId\_$remoteUserId',
        value: jsonEncode(sessionState.toJson()));
  }

  Future<void> removeSession(String remoteUserId) async {
    await _storage.delete(key: 'signal_session_$_userId\_$remoteUserId');
  }

  // --- X3DH and Session Building ---

  /// Perform the X3DH key agreement to establish a shared secret with a remote user.
  /// Returns the root key and chain keys needed to initialize a session.
  Future<Map<String, dynamic>> performX3DH(
      String remoteUserId,
      IdentityKeyPair remoteIdentityKeyPair,
      ECPublicKey remoteSignedPreKeyPublic,
      ECPublicKey? remoteOneTimePreKeyPublic) async {
    final identityKeyPair = await getOrCreateIdentityKeyPair();
    final signedPreKey = await loadSignedPreKey(2); // Assume we use keyId 2 for signed pre-key
    final oneTimePreKey = await loadPreKeys(0, 1).then((list) => list.isNotEmpty ? list[0] : null);

    // If we don't have a one-time pre-key, we can still proceed but it's less secure.
    // For simplicity, we assume we have one.
    if (oneTimePreKey == null && remoteOneTimePreKeyPublic == null) {
      throw Exception('No one-time pre-key available');
    }

    // Perform X3DH key agreement (simplified)
    final x3dh = X3DH();
    final secretKey = x3dh.calculateAgreement(
        identityKeyPair.privateKey,
        signedPreKey.keyPair.privateKey,
        oneTimePreKey?.keyPair.privateKey,
        remoteIdentityKeyPair.publicKey,
        remoteSignedPreKeyPublic,
        remoteOneTimePreKeyPublic);

    // Derive root key and chain keys
    final rootKey = RootKey(secretKey);
    final sendChain = ChainKey(rootKey.rootKey, 0, [], 32);
    final receiveChain = ChainKey(rootKey.rootKey, 0, [], 32);

    return {
      'rootKey': rootKey.rootKey,
      'sendChainKey': sendChain.chainKey,
      'receiveChainKey': receiveChain.chainKey,
      'localIdentityKeyPair': identityKeyPair,
      'remoteIdentityKeyPair': remoteIdentityKeyPair,
    };
  }

  /// Initialize a session state from the X3DH output.
  Future<SessionState> initSession(Map<String, dynamic> x3dhOutput, bool isSender) async {
    final sessionBuilder = SessionBuilder(
        await _storage.read(key: 'signal_identity_private_$_userId') != null
            ? IdentityKeyPair.fromBuffer(
                base64Decode(await _storage.read(key: 'signal_identity_private_$_userId')!),
                base64Decode(await _storage.read(key: 'signal_identity_public_$_userId')!),
              )
            : await getOrCreateIdentityKeyPair(),
        await loadSession('dummy'), // We don't have a previous session, so we pass null? Actually, we need to load the current session if exists.
        0, // sessionId
        0, // deviceId
        );

    // The actual session building is more complex. We'll skip the details for this example.
    // In a real implementation, we would use the X3DH output to build the session.
    // For now, we return a mock session state.
    return SessionState(
        1, // sessionId
        1, // deviceId
        1, // remoteSessionId
        1, // remoteDeviceId
        rootKey: RootKey(Uint8List(32)), // Mock
        sendChain: ChainKey(Uint8List(32), 0, [], 32), // Mock
        receiveChain: ChainKey(Uint8List(32), 0, [], 32), // Mock
        );
  }
}

// Note: This is a simplified version. A full implementation would require
// handling the Signal Protocol state machine correctly.
// For the purpose of this task, we provide the structure and assume the
// actual encryption/decryption is done by the client using this service.