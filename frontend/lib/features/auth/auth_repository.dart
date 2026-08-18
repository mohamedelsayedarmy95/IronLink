import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/secure_storage.dart';

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

  /// Firebase accepted the request and never came back.
  ///
  /// Distinct from [network] because the device is usually online — saying
  /// "you appear to be offline" sends the user to check a connection that is
  /// working, which is worse than saying nothing. In practice this means the
  /// app is not registered in Firebase under its real package and signing
  /// fingerprint, so verification can never complete.
  verificationTimeout,
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

  /// The same shape the server sends, so one parser serves both.
  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'username': username,
        'role': role,
        'avatar_url': avatarUrl,
      };
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
    // Whether any of Firebase's callbacks has fired. Without it the guard
    // below could report a timeout after the code had already been sent.
    var settled = false;

    // A wall-clock guard, which `timeout:` below is NOT: that one only governs
    // Android's SMS auto-retrieval and fires codeAutoRetrievalTimeout. If the
    // underlying request never comes back — which is what happens when the app
    // is not registered in Firebase under its real package and signing
    // fingerprint — then none of the three callbacks fire and the caller waits
    // forever. Observed on a real device: 70 seconds with no error and no
    // timeout, just a spinner.
    final guard = Timer(const Duration(seconds: 45), () {
      if (settled) return;
      settled = true;
      onError(AuthErrorCode.verificationTimeout, null);
    });

    void finish(void Function() callback) {
      if (settled) return;
      settled = true;
      guard.cancel();
      callback();
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          // Not routed through finish(): signing in is itself slow, and the
          // guard must stay armed until it either works or throws.
          if (settled) return;
          try {
            final idToken = await _signInAndGetIdToken(credential);
            finish(() => onAutoVerified(idToken));
          } catch (e) {
            final (code, detail) = firebaseErrorCode(e);
            finish(() => onError(code, detail));
          }
        },
        verificationFailed: (e) {
          final (code, detail) = firebaseErrorCode(e);
          finish(() => onError(code, detail));
        },
        codeSent: (verificationId, resendToken) =>
            finish(() => onCodeSent(verificationId, resendToken)),
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      final (code, detail) = firebaseErrorCode(e);
      finish(() => onError(code, detail));
    }
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

  /// The signed-in user, or null if there is no usable session.
  ///
  /// Returns null rather than throwing for an expired or rejected token,
  /// because "not signed in" is a normal state at launch and not an error to
  /// report. Tokens that the server refuses are cleared, so a stale pair does
  /// not sit there failing every request.
  static const _profileKey = 'auth_profile_v1';

  /// Who is signed in, or null if nobody is.
  ///
  /// THE BUG THIS SHAPE USED TO CAUSE
  ///
  /// There are three possible answers — signed in, not signed in, and "cannot
  /// check right now" — and a nullable return can only carry two. A network
  /// failure collapsed into null, which the splash screen reads as "not signed
  /// in", so **losing the network signed the user out of the interface.**
  ///
  /// The tokens were kept, and the code said so in a comment: "a network
  /// failure is not proof the session is gone". It then returned null anyway,
  /// because there was nothing else to return.
  ///
  /// Found by pulling the network on a real phone. Every unit test passes
  /// either way, because the bug is not in this function's logic — it is in
  /// what the caller can distinguish.
  ///
  /// It defeated the whole offline-first design at the front door: the cached
  /// conversations, the durable outbox, and the banner promising "your
  /// messages will send when you are back" were all behind a sign-in wall that
  /// appeared precisely when the network went away.
  ///
  /// So a verified profile is cached, and an unreachable server returns the
  /// cached one. The session is still assumed valid — which it is, until the
  /// server says otherwise, and the moment it does say 401 the tokens and the
  /// cache are both cleared.
  Future<AuthUser?> restoreSession() async {
    try {
      final token = await _client.accessToken;
      if (token == null) return null;

      final res = await _client.dio.get<Map<String, dynamic>>(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final user = AuthUser.fromJson(res.data!);
      await _cacheProfile(user);
      return user;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        // Refused, so it will keep being refused. Cleared rather than left
        // to fail every subsequent request — and the cached profile goes with
        // the tokens, or an expired session would still open the app.
        await _client.clearTokens();
        await _clearProfile();
        return null;
      }
      // Unreachable, not rejected. The tokens are as valid as they were a
      // moment ago, so the app opens on the cached identity and the
      // connection banner tells the truth about being offline.
      return _cachedProfile();
    } catch (_) {
      // Anything else — no keystore on this platform, storage unreadable.
      // Failing to answer "is there a session" must never stop the app from
      // starting; the welcome screen is a safe answer.
      return null;
    }
  }

  Future<void> _cacheProfile(AuthUser user) async {
    try {
      await ironSecureStorage.write(
        key: _profileKey,
        value: jsonEncode(user.toJson()),
      );
    } catch (err) {
      // Not fatal. The consequence of failing to cache is the old behaviour
      // for this one account — a sign-in screen when offline — not a crash.
      debugPrint('[auth] could not cache profile: $err');
    }
  }

  Future<AuthUser?> _cachedProfile() async {
    try {
      final raw = await ironSecureStorage.read(key: _profileKey);
      if (raw == null) return null;
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (err) {
      debugPrint('[auth] cached profile unreadable: $err');
      return null;
    }
  }

  Future<void> _clearProfile() async {
    try {
      await ironSecureStorage.delete(key: _profileKey);
    } catch (_) {
      // Nothing useful to do; the tokens are already gone, so the cache
      // cannot be used to open the app.
    }
  }

  /// Registers a new account from a verified phone number.
  ///
  /// The number is not sent: the server reads it from the token, so a client
  /// cannot register a number it does not control. The military ID is *set*
  /// here and becomes the second factor for every later sign-in.
  ///
  /// Returns null when the account was created but needs an administrator's
  /// approval before it can be used.
  Future<AuthUser?> register({
    required String idToken,
    required String fullName,
    required String militaryId,
    required String deviceFingerprint,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/register-firebase',
      data: {
        'id_token': idToken,
        'full_name': fullName,
        'military_id': militaryId,
        'device_fingerprint': deviceFingerprint,
      },
    );
    final data = res.data!;
    if (data['approved'] != true) return null;

    final session = data['session'] as Map<String, dynamic>;
    await _client.saveTokens(
      access: session['access_token'] as String,
      refresh: session['refresh_token'] as String,
    );
    return AuthUser.fromJson(session['user'] as Map<String, dynamic>);
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
