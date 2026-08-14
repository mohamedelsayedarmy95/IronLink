import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'models/verification_form.dart';

/// Per-field validation messages returned by the server (HTTP 422).
///
/// The server is the authority on whether an answer satisfies the admin's
/// rules — the client's own checks are a convenience, not the boundary. When
/// the two disagree, this carries the server's verdict back to the exact
/// field so the user isn't told "something is wrong" about a whole form.
class FieldValidationException implements Exception {
  const FieldValidationException(this.fieldErrors);

  final Map<String, String> fieldErrors;

  @override
  String toString() => 'FieldValidationException(${fieldErrors.length} fields)';
}

class GroupEntryRepository {
  GroupEntryRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// The form a prospective member must complete, or null when the group
  /// asks no questions.
  Future<VerificationForm?> activeForm(String groupId) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/groups/$groupId/forms/active',
      options: await _auth(),
    );
    final data = res.data;
    if (data == null || data.isEmpty) return null;
    return VerificationForm.fromJson(data);
  }

  /// This user's own request for the group, or null if they never applied.
  Future<JoinRequest?> myRequest(String groupId) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/groups/$groupId/entry-request/me',
      options: await _auth(),
    );
    final data = res.data;
    if (data == null || data.isEmpty) return null;
    return JoinRequest.fromJson(data);
  }

  Future<JoinRequest> submit(
    String groupId, {
    required Map<String, dynamic> answers,
    String? message,
  }) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/groups/$groupId/entry-request',
        data: {'answers': answers, if (message != null) 'message': message},
        options: await _auth(),
      );
      return JoinRequest.fromJson(res.data!);
    } on DioException catch (e) {
      final errors = _fieldErrorsFrom(e);
      if (errors != null) throw FieldValidationException(errors);
      rethrow;
    }
  }

  Future<void> cancel(String groupId) async {
    await _api.dio.delete<void>(
      '/groups/$groupId/entry-request/me',
      options: await _auth(),
    );
  }

  // ── Admin side ──────────────────────────────────────────────────────────

  Future<List<JoinRequest>> requests(
    String groupId, {
    JoinRequestStatus status = JoinRequestStatus.pending,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/groups/$groupId/entry-requests',
      queryParameters: {
        'status': status.wire,
        'limit': limit,
        'offset': offset,
      },
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        JoinRequest.fromJson(j as Map<String, dynamic>)
    ];
  }

  Future<Map<String, int>> counts(String groupId) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/groups/$groupId/entry-requests/counts',
      options: await _auth(),
    );
    return {
      for (final e in (res.data ?? {}).entries)
        e.key: (e.value as num?)?.toInt() ?? 0,
    };
  }

  Future<JoinRequest> approve(String groupId, String requestId) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/groups/$groupId/entry-requests/$requestId/approve',
      options: await _auth(),
    );
    return JoinRequest.fromJson(res.data!);
  }

  Future<JoinRequest> reject(
    String groupId,
    String requestId, {
    String? reason,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/groups/$groupId/entry-requests/$requestId/reject',
      data: {if (reason != null) 'reason': reason},
      options: await _auth(),
    );
    return JoinRequest.fromJson(res.data!);
  }

  Future<JoinRequest> requestMoreInfo(
    String groupId,
    String requestId, {
    required String notes,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/groups/$groupId/entry-requests/$requestId/request-info',
      data: {'notes': notes},
      options: await _auth(),
    );
    return JoinRequest.fromJson(res.data!);
  }

  /// Returns how many were actually settled. [requestIds] omitted means every
  /// pending request; the caller is expected to have confirmed first.
  Future<({int succeeded, int failed, int total})> bulk(
    String groupId, {
    required bool approve,
    List<String>? requestIds,
    String? reason,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/groups/$groupId/entry-requests/${approve ? 'bulk-approve' : 'bulk-reject'}',
      data: {
        if (requestIds != null) 'request_ids': requestIds,
        if (reason != null) 'reason': reason,
      },
      options: await _auth(),
    );
    final data = res.data ?? const {};
    return (
      succeeded: (data['succeeded'] as num?)?.toInt() ?? 0,
      failed: (data['failed'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Pulls the `{field_id: message}` map out of a 422 body, if present.
  static Map<String, String>? _fieldErrorsFrom(DioException e) {
    if (e.response?.statusCode != 422) return null;
    final detail = (e.response?.data as Map?)?['detail'];
    if (detail is! Map) return null;
    final raw = detail['field_errors'];
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }
}
