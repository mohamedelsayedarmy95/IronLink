import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'env.dart';

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
        ));

  final Dio _dio;
  static const _storage = FlutterSecureStorage();

  static const _kAccess = 'mil_access_token';
  static const _kRefresh = 'mil_refresh_token';

  Dio get dio => _dio;

  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccess);

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
