import 'package:dio/dio.dart' show Options;
import 'package:equatable/equatable.dart';

import '../../core/api_client.dart';

/// The reasons a report can carry.
///
/// Fixed rather than free text: a moderator triaging a queue needs to sort by
/// severity, and "other" with a note covers what the list does not.
enum ReportReason {
  spam('spam'),
  harassment('harassment'),
  impersonation('impersonation'),
  scam('scam'),
  illegalContent('illegal_content'),
  leakedClassified('leaked_classified'),
  other('other');

  const ReportReason(this.wire);
  final String wire;
}

class BlockedUser extends Equatable {
  const BlockedUser({
    required this.userId,
    required this.fullName,
    required this.blockedAt,
    this.username,
  });

  final String userId;
  final String fullName;
  final String? username;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        username: json['username'] as String?,
        blockedAt:
            DateTime.tryParse(json['blocked_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );

  @override
  List<Object?> get props => [userId, blockedAt];
}

class SubmittedReport extends Equatable {
  const SubmittedReport({
    required this.id,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String reason;

  /// open / reviewing / actioned / dismissed — shown back to the reporter so
  /// filing a report is not a dead end.
  final String status;
  final DateTime createdAt;

  factory SubmittedReport.fromJson(Map<String, dynamic> json) =>
      SubmittedReport(
        id: json['id'] as String,
        reason: json['reason'] as String? ?? 'other',
        status: json['status'] as String? ?? 'open',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );

  @override
  List<Object?> get props => [id, status];
}

class ModerationRepository {
  ModerationRepository(this._api);

  final ApiClient _api;

  /// Server-side cap on the evidence snapshot. Mirrored here so the text is
  /// trimmed before the request rather than bounced back as a 422.
  static const maxSnapshotChars = 4000;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> block(String userId, {String? reason}) async {
    await _api.dio.post<void>(
      '/users/$userId/block',
      data: {'reason': reason},
      options: await _auth(),
    );
  }

  Future<void> unblock(String userId) async {
    await _api.dio.delete<void>(
      '/users/$userId/block',
      options: await _auth(),
    );
  }

  /// Whether *this* user has blocked the other.
  ///
  /// There is deliberately no call for the reverse direction: the server does
  /// not expose who has blocked you, because that is precisely what a block
  /// withholds.
  Future<bool> isBlocked(String userId) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/users/$userId/block-status',
      options: await _auth(),
    );
    return (res.data ?? const {})['blocked'] as bool? ?? false;
  }

  Future<List<BlockedUser>> blockedUsers() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/users/blocked',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        BlockedUser.fromJson(j as Map<String, dynamic>)
    ];
  }

  /// Files a report.
  ///
  /// [contentSnapshot] is the decrypted text as this device rendered it. The
  /// server holds only ciphertext it cannot read, so without the snapshot the
  /// evidence vanishes the moment the sender unsends the message.
  Future<SubmittedReport> report({
    required String reportedUserId,
    required ReportReason reason,
    String? messageId,
    String? details,
    String? contentSnapshot,
  }) async {
    final snapshot = contentSnapshot != null &&
            contentSnapshot.length > maxSnapshotChars
        ? contentSnapshot.substring(0, maxSnapshotChars)
        : contentSnapshot;

    final res = await _api.dio.post<Map<String, dynamic>>(
      '/reports',
      data: {
        'reported_user_id': reportedUserId,
        'reason': reason.wire,
        if (messageId != null) 'message_id': messageId,
        if (details != null && details.isNotEmpty) 'details': details,
        if (snapshot != null && snapshot.isNotEmpty)
          'content_snapshot': snapshot,
      },
      options: await _auth(),
    );
    return SubmittedReport.fromJson(res.data ?? const {});
  }

  Future<List<SubmittedReport>> myReports() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/reports/mine',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        SubmittedReport.fromJson(j as Map<String, dynamic>)
    ];
  }
}
