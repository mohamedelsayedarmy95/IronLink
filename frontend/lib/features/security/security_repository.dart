import 'package:dio/dio.dart' show Options;

import '../../core/api_client.dart';
import 'domain/security_posture.dart';

/// IronShield's server surface, which is deliberately tiny.
///
/// Two endpoints, both of which already existed before this feature: listing
/// sessions and revoking one. Nothing was added server-side, and that is the
/// point — a Security Center is the last place to introduce new privileged
/// operations. Every action the screen offers composes from these two.
///
/// In particular there is no "secure my account" endpoint. That button revokes
/// the other sessions one at a time through the same per-device endpoint the
/// user could use by hand. A bulk endpoint would be one more thing to
/// authorize correctly, for no capability the client cannot already express.
class SecurityRepository {
  const SecurityRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Every active session on this account.
  ///
  /// The server decides what "active" means — non-revoked and unexpired — and
  /// marks which one is making the request. This client does not re-derive
  /// either, because two places computing the same thing eventually disagree,
  /// and the disagreement here would be a device the user cannot see.
  Future<List<ActiveSession>> sessions() async {
    final response = await _api.dio.get<List<dynamic>>(
      '/auth/sessions',
      options: await _auth(),
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ActiveSession.fromJson)
        .toList(growable: false);
  }

  /// Revokes one session. The refresh token dies immediately and the live
  /// socket on that device is told to close.
  Future<void> revoke(String sessionId) async {
    await _api.dio.delete<void>(
      '/auth/sessions/$sessionId',
      options: await _auth(),
    );
  }

  /// Revokes every session except the one making the request.
  ///
  /// Sequential rather than concurrent, and it does not stop at the first
  /// failure. A partial result is the honest outcome of a flaky network here:
  /// three of four devices signed out is better than an exception that leaves
  /// the user unsure whether any were, and the screen reloads from the server
  /// afterwards so what it shows is what actually happened rather than what was
  /// attempted.
  ///
  /// Returns the ids it could not revoke.
  Future<List<String>> revokeOthers(List<ActiveSession> sessions) async {
    final failed = <String>[];
    for (final session in sessions) {
      if (session.isCurrent) continue;
      try {
        await revoke(session.id);
      } catch (_) {
        failed.add(session.id);
      }
    }
    return failed;
  }
}
