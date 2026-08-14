import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/api_client.dart';

/// Semantic error outcomes from the auth flow. The repository/bloc layer
/// stays UI-agnostic — it has no BuildContext to localize a message with —
/// so it classifies failures into these codes and the screen (which does
/// have a BuildContext) maps each one to localized text when displaying it.
enum AuthErrorCode {
  network,
  unexpected,
  invalidPhone,
  tooManyRequests,
  invalidCode,
  sessionExpired,
  phoneVerificationFailed,
}

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

  // ── Firebase Phone Auth ────────────────────────────────────────────────────
  // Real SMS delivery, verified server-side. Replaces requestOtp() as the
  // production path; the military ID stays a required second factor on top —
  // Firebase only proves phone ownership, not who's authorized to use it.

  /// Starts phone verification. [onCodeSent] fires once Firebase has sent the
  /// SMS; [onAutoVerified] fires instead on Android devices that can confirm
  /// the code automatically, skipping manual entry. [onError] covers both
  /// immediate validation failures and later ones (wrong code, expired, etc).
  Future<void> sendPhoneOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String idToken) onAutoVerified,
    required void Function(AuthErrorCode code, String? detail) onError,
    int? forceResendingToken,
  }) async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          final idToken = await _signInAndGetIdToken(credential);
          onAutoVerified(idToken);
        } catch (e) {
          final (code, detail) = firebaseErrorCode(e);
          onError(code, detail);
        }
      },
      verificationFailed: (e) {
        final (code, detail) = firebaseErrorCode(e);
        onError(code, detail);
      },
      codeSent: (verificationId, resendToken) =>
          onCodeSent(verificationId, resendToken),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Exchanges the OTP the user typed for a Firebase ID token.
  Future<String> confirmOtp({
    required String verificationId,
    required String otpCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otpCode,
    );
    return _signInAndGetIdToken(credential);
  }

  Future<String> _signInAndGetIdToken(PhoneAuthCredential credential) async {
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final idToken = await userCredential.user?.getIdToken();
    if (idToken == null) {
      // Not FirebaseAuthException, so firebaseErrorCode() below maps this to
      // AuthErrorCode.unexpected — the message itself is never surfaced.
      throw Exception('Firebase returned no ID token after sign-in');
    }
    return idToken;
  }

  /// Verified Firebase ID token → IronLink session. Mirrors verify() but the
  /// phone number itself is never sent — the server reads it out of the
  /// verified token so a client can't claim a number it doesn't control.
  Future<AuthUser> exchangeFirebaseToken({
    required String idToken,
    required String militaryId,
    required String deviceFingerprint,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/verify-firebase',
      data: {
        'id_token': idToken,
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

  /// Classifies a backend-request failure for the auth screen to localize.
  /// [detail] carries through the server's raw detail string, if any, since
  /// that text comes from the API (already whatever language it replies in)
  /// rather than something this client can translate.
  static (AuthErrorCode, String?) errorCode(Object error) {
    if (error is DioException) {
      final detail = error.response?.data is Map
          ? (error.response!.data as Map)['detail']
          : null;
      if (detail is String) return (AuthErrorCode.unexpected, detail);
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.connectionError) {
        return (AuthErrorCode.network, null);
      }
    }
    return (AuthErrorCode.unexpected, null);
  }

  /// Same as [errorCode] but also covers FirebaseAuthException codes from
  /// the phone-verification step.
  static (AuthErrorCode, String?) firebaseErrorCode(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-phone-number':
          return (AuthErrorCode.invalidPhone, null);
        case 'too-many-requests':
          return (AuthErrorCode.tooManyRequests, null);
        case 'invalid-verification-code':
          return (AuthErrorCode.invalidCode, null);
        case 'session-expired':
          return (AuthErrorCode.sessionExpired, null);
        default:
          return (AuthErrorCode.phoneVerificationFailed, error.message);
      }
    }
    return errorCode(error);
  }
}
