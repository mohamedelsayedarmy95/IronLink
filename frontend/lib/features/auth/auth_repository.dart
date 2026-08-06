import 'package:dio/dio.dart';

import '../../core/api_client.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    this.username,
    required this.role,
    this.avatarUrl,
  });

  final String id;
  final String fullName;
  final String? username;
  final String role;
  final String? avatarUrl;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        username: json['username'] as String?,
        role: json['role'] as String,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<int> requestOtp(String phoneNumber) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/request-otp',
      data: {'phone_number': phoneNumber},
    );
    return (res.data?['retry_after_seconds'] as num?)?.toInt() ?? 60;
  }

  Future<AuthUser> verify({
    required String phoneNumber,
    required String otpCode,
    required String militaryId,
    required String deviceFingerprint,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/verify',
      data: {
        'phone_number': phoneNumber,
        'otp_code': otpCode,
        'military_id': militaryId,
        'device_fingerprint': deviceFingerprint,
      },
    );
    final data = res.data!;
    await _client.saveTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Extracts the server's error message for the red military snackbar.
  static String errorMessage(Object error) {
    if (error is DioException) {
      final detail = error.response?.data is Map
          ? (error.response!.data as Map)['detail']
          : null;
      if (detail is String) return detail;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'تعذر الاتصال بالخادم — تحقق من الشبكة';
      }
    }
    return 'حدث خطأ غير متوقع';
  }
}
