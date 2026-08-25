import 'package:dio/dio.dart';

import 'env.dart';
import 'secure_storage.dart';

/// Thin Dio wrapper. Tokens live in the platform keystore
/// (flutter_secure_storage), never in SharedPreferences.
class ApiClient {
  ApiClient({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? Env.apiBaseUrl,
          // Render's free tier sleeps after inactivity and takes ~50s to wake
          // on the first request — a short timeout here fails that request
          // even though the server is fine, it just hasn't booted yet.
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        )) {
    _dio.interceptors.add(
      InterceptorsWrapper(onError: (error, handler) async {
        // Access tokens last an hour. Without this every screen would have to
        // handle expiry itself, and before the refresh endpoint existed the
        // only recovery was signing in again by SMS.
        if (error.response?.statusCode != 401) {
          return handler.next(error);
        }

        final request = error.requestOptions;
        // One attempt per request. A retry that 401s again means the session
        // is over, and looping would hammer the server on every screen.
        if (request.extra[_retriedFlag] == true) {
          return handler.next(error);
        }
        // Only the endpoints that mint credentials are excluded, not all of
        // /auth/. Excluding the whole prefix would skip /auth/me, which is
        // exactly the call session restore makes when the access token has
        // expired — the one case this interceptor exists for.
        if (_noRefreshPaths.any(request.path.contains)) {
          return handler.next(error);
        }

        if (!await refreshSession()) return handler.next(error);

        final token = await accessToken;
        if (token == null) return handler.next(error);

        try {
          final retried = await _dio.fetch<dynamic>(
            request
              ..extra[_retriedFlag] = true
              ..headers['Authorization'] = 'Bearer $token',
          );
          return handler.resolve(retried);
        } on DioException catch (e) {
          return handler.next(e);
        }
      }),
    );
  }

  static const _retriedFlag = 'ironlink_retried_after_refresh';

  /// Endpoints that issue credentials. A 401 from one of these means the
  /// credentials were wrong, which refreshing cannot fix — and refreshing
  /// inside the refresh call would recurse.
  static const _noRefreshPaths = [
    '/auth/refresh',
    '/auth/verify',
    '/auth/verify-firebase',
    '/auth/register-firebase',
    '/auth/request-otp',
  ];

  final Dio _dio;

  // Shared, not a local FlutterSecureStorage(): see secure_storage.dart. A
  // differently-configured instance elsewhere in the app silently destroys
  // whatever this one wrote.
  static const _storage = ironSecureStorage;

  static const _kAccess = 'mil_access_token';
  static const _kRefresh = 'mil_refresh_token';

  Dio get dio => _dio;

  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccess);

  Future<String?> get refreshToken => _storage.read(key: _kRefresh);

  /// Serialises refreshes so a burst of 401s produces one exchange.
  ///
  /// This matters more than it looks: the refresh token is rotated on use, so
  /// two concurrent refreshes would have the second present an
  /// already-exchanged token — which the server reads as a replay and
  /// responds to by revoking the session. Parallel requests failing together
  /// is the normal case, not an edge one.
  Future<bool>? _inFlightRefresh;

  /// Exchanges the stored refresh token for a new pair.
  ///
  /// Returns false when there is nothing to refresh with or the server
  /// refuses, in which case the session is genuinely over and the tokens are
  /// cleared rather than left to fail every later request.
  Future<bool> refreshSession() {
    return _inFlightRefresh ??= _doRefresh().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refresh = await refreshToken;
    if (refresh == null) return false;

    try {
      // A bare Dio: this must not pass through the interceptor that calls
      // it, or a failing refresh would try to refresh itself.
      final res = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
          .post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = res.data!;
      await saveTokens(
        access: data['access_token'] as String,
        refresh: data['refresh_token'] as String,
      );
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await clearTokens();
        return false;
      }
      // A network failure is not proof the session ended, so the tokens stay
      // and the next attempt can succeed.
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  Future<Response<T>> authedPost<T>(String path, {Object? data}) async {
    final token = await accessToken;
    return _dio.post<T>(
      path,
      data: data,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}
