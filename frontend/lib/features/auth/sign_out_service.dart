import 'package:dio/dio.dart' show Options;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/api_client.dart';
import '../../core/crypto/signal.dart';
import '../../core/secure_storage.dart';
import '../chat/local/message_store.dart';

/// Signs out and erases what this device holds.
///
/// There was no sign-out at all — no UI, and nothing calling the wipe methods
/// whose own docstrings said "called on sign-out". A user could not leave the
/// device, and everything stayed: the decrypted message cache, the Signal
/// identity and session keys, group sender keys, the contact-hash salt, saved
/// form drafts.
///
/// That matters most in exactly the situation this product is for — a device
/// handed on, lost, or inspected. Clearing the token alone would leave the
/// plaintext history sitting in SQLite for whoever holds the phone next.
class SignOutService {
  SignOutService({
    required ApiClient api,
    required MessageStore messages,
    SignalService? signal,
  })  : _api = api,
        _messages = messages,
        _signal = signal;

  final ApiClient _api;
  final MessageStore _messages;

  /// Null when signing out from a screen that never built it. Its stored
  /// material — including group sender keys — is cleared by the sweep below
  /// either way, so this being absent is not a hole.
  final SignalService? _signal;

  /// Everything, in the order that matters.
  ///
  /// Local erasure happens even if the server call fails: being offline must
  /// not mean the data stays. The server-side revoke is attempted first only
  /// because it needs the token that is about to be destroyed.
  Future<void> signOut() async {
    await _revokeServerSession();

    // Ordered most-sensitive first, and each guarded on its own: one failure
    // must not leave the rest behind.
    await _attempt('signal keys', () async => _signal?.reset());
    await _attempt('message cache', _messages.clear);
    await _attempt('secure storage', _wipeSecureStorage);
    await _attempt('tokens', _api.clearTokens);
  }

  Future<void> _revokeServerSession() async {
    try {
      final token = await _api.accessToken;
      if (token == null) return;
      await _api.dio.post<void>(
        '/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      // Offline, or the session was already revoked. The local wipe is the
      // part that protects this device, and it proceeds regardless.
      debugPrint('[signout] server revoke skipped: $e');
    }
  }

  /// Removes every key this app owns, rather than a named list.
  ///
  /// A list would need updating each time a feature stores something, and
  /// the failure mode of forgetting is silent: one more piece of the previous
  /// user's data left behind. This clears the app's whole store — the salt,
  /// drafts, Signal material and sender keys included, which is also why
  /// [_signal] being null above is not a hole.
  Future<void> _wipeSecureStorage() => ironSecureStorage.deleteAll();

  Future<void> _attempt(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[signout] failed to clear $what: $e');
    }
  }
}
