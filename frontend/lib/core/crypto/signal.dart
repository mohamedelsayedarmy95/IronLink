import 'dart:convert';

/// Temporary stub for the Signal Protocol E2EE service.
///
/// The previous implementation was written against an incompatible version
/// of libsignal_protocol_dart and never had working session establishment
/// (initSessionAsSender/Receiver threw UnimplementedError). This stub keeps
/// the same call surface used by ChatBloc so the app builds and secret
/// chats degrade to a passthrough (base64-wrapped, NOT encrypted) instead of
/// crashing. Real E2EE needs to be rebuilt against the installed package
/// API in a dedicated follow-up.
class SignalService {
  final String _userId;
  final String _baseUrl;

  SignalService(this._userId, {required String baseUrl}) : _baseUrl = baseUrl;

  final Map<String, bool> _sessions = {};

  Future<bool?> loadSession(String remoteUserId) async {
    return _sessions[remoteUserId];
  }

  Future<void> performX3DH(String remoteUserId) async {}

  Future<void> initSessionAsSender(
      String remoteUserId, Map<String, dynamic> x3dhOutput) async {
    _sessions[remoteUserId] = true;
  }

  Future<void> initSessionAsReceiver(
      String remoteUserId, Map<String, dynamic> x3dhOutput) async {
    _sessions[remoteUserId] = true;
  }

  Future<Map<String, dynamic>> encryptMessage(
      String plaintext, String remoteUserId) async {
    return {'ciphertext': base64Encode(utf8.encode(plaintext))};
  }

  Future<String> decryptMessage(
      Map<String, dynamic> ciphertextMap, String remoteUserId) async {
    final ciphertext = ciphertextMap['ciphertext'] as String;
    return utf8.decode(base64Decode(ciphertext));
  }
}
