import 'package:dio/dio.dart' show Options;

import '../../core/api_client.dart';

/// Who has agreed that a conversation's text may be sent for AI processing.
class AiConsentState {
  const AiConsentState({
    required this.granted,
    required this.everyoneAgreed,
    this.waitingOn = const [],
    this.totalParticipants = 0,
  });

  /// Whether *this* user has agreed.
  final bool granted;

  /// Whether everyone whose words would be transmitted has agreed. Only then
  /// will the server accept anything.
  final bool everyoneAgreed;

  /// Names of the others still to agree, so the interface can say who rather
  /// than just refusing.
  final List<String> waitingOn;

  final int totalParticipants;

  /// Nothing may be sent until this is true.
  bool get canUseAi => granted && everyoneAgreed;

  factory AiConsentState.fromJson(Map<String, dynamic> json) => AiConsentState(
        granted: json['granted'] as bool? ?? false,
        everyoneAgreed: json['everyone_agreed'] as bool? ?? false,
        waitingOn: [
          for (final n in (json['waiting_on'] as List<dynamic>? ?? const []))
            n as String
        ],
        totalParticipants:
            (json['total_participants'] as num?)?.toInt() ?? 0,
      );

  static const unknown = AiConsentState(granted: false, everyoneAgreed: false);
}

/// Reads and sets AI consent.
///
/// The client checks this before sending anything, but the check is a
/// courtesy — the server enforces it. A build that skipped this would still
/// be refused, which is the point: consent that only the UI honours is not
/// enforcement.
class AiConsentRepository {
  AiConsentRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<AiConsentState> read({String? peerId, String? groupId}) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/ai/consent',
      queryParameters: {
        if (peerId != null) 'peer_id': peerId,
        if (groupId != null) 'group_id': groupId,
      },
      options: await _auth(),
    );
    return AiConsentState.fromJson(res.data ?? const {});
  }

  Future<AiConsentState> set({
    required bool granted,
    String? peerId,
    String? groupId,
  }) async {
    final res = await _api.dio.put<Map<String, dynamic>>(
      '/ai/consent',
      data: {
        'granted': granted,
        if (peerId != null) 'peer_id': peerId,
        if (groupId != null) 'group_id': groupId,
      },
      options: await _auth(),
    );
    return AiConsentState.fromJson(res.data ?? const {});
  }
}
