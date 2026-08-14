import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// What went wrong, in terms a person can act on.
///
/// Transport details (`DioException`, socket errors, the dev host address)
/// are diagnostic data, not user-facing copy — leaking them tells the user
/// nothing they can do and exposes internal hosts. The bloc layer classifies
/// into one of these; the widget layer maps each to a localized sentence.
enum NetworkFailure {
  /// No usable connection from the device itself.
  offline,

  /// Reached the network but nothing answered in time.
  timeout,

  /// Server answered with 5xx, or could not be reached at all.
  server,

  /// Credentials are missing or no longer valid (401/403).
  unauthorized,

  /// Server rejected the request as invalid (other 4xx).
  rejected,

  /// TLS could not be validated — worth calling out separately in a product
  /// whose entire premise is a trustworthy channel.
  insecure,

  /// Classified nothing more specific.
  unknown,
}

extension NetworkFailureClassifier on NetworkFailure {
  /// Maps a thrown error onto a failure cause, logging the original in debug
  /// builds so the detail stays available to developers without shipping it
  /// into the interface.
  static NetworkFailure from(Object error) {
    if (kDebugMode) {
      debugPrint('[network] $error');
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return NetworkFailure.timeout;
        case DioExceptionType.badCertificate:
          return NetworkFailure.insecure;
        case DioExceptionType.connectionError:
          return error.error is SocketException
              ? NetworkFailure.offline
              : NetworkFailure.server;
        case DioExceptionType.badResponse:
          final status = error.response?.statusCode ?? 0;
          if (status == 401 || status == 403) return NetworkFailure.unauthorized;
          if (status >= 500) return NetworkFailure.server;
          if (status >= 400) return NetworkFailure.rejected;
          return NetworkFailure.unknown;
        case DioExceptionType.cancel:
        case DioExceptionType.unknown:
          return error.error is SocketException
              ? NetworkFailure.offline
              : NetworkFailure.unknown;
      }
    }
    if (error is SocketException) return NetworkFailure.offline;
    return NetworkFailure.unknown;
  }
}
