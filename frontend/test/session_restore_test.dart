import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/secure_storage.dart';
import 'package:ironlink/features/auth/auth_repository.dart';

/// Losing the network used to sign the user out of the interface.
///
/// The tokens survived — the code said so, in a comment — but `restoreSession`
/// returned null on a network failure, and the splash screen reads null as "not
/// signed in". So the cached conversations, the durable outbox, and the banner
/// promising "your messages will send when you are back" all sat behind a
/// sign-in wall that appeared exactly when the network went away.
///
/// Every unit test passed either way, because the bug was not in the function's
/// logic. It was in what its return type let the caller distinguish: three
/// answers — signed in, not signed in, cannot check — squeezed into two.
///
/// It was found by pulling the network on a real phone.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  ApiClient clientThat({int? status, Map<String, dynamic>? body}) {
    final api = ApiClient();
    api.dio.httpClientAdapter = _Stub(status: status, body: body);
    return api;
  }

  const profile = {
    'id': 'u1',
    'full_name': 'Someone',
    'username': 'someone',
    'role': 'user',
    'avatar_url': null,
  };

  // The shared instance, never a fresh FlutterSecureStorage: secure_storage.dart
  // explains that two differently-configured instances cannot read each other's
  // entries, and a test that uses its own would silently see nothing.
  Future<void> withToken(ApiClient api) =>
      ironSecureStorage.write(key: 'mil_access_token', value: 't0ken');

  group('when the server answers', () {
    test('the session is restored and remembered', () async {
      final api = clientThat(status: 200, body: profile);
      await withToken(api);

      final user = await AuthRepository(api).restoreSession();

      expect(user?.id, 'u1');
      final cached =
          await ironSecureStorage.read(key: 'auth_profile_v1');
      expect(cached, isNotNull,
          reason: 'the profile has to be kept, or the next offline launch '
              'has nothing to open on');
      expect(jsonDecode(cached!)['full_name'], 'Someone');
    });
  });

  group('when the server is unreachable', () {
    test('the app opens on the cached identity', () async {
      // The fix. A network failure is not proof the session is gone, and the
      // tokens are as valid as they were a moment ago.
      await ironSecureStorage.write(key: 'auth_profile_v1', value: jsonEncode(profile));
      final api = clientThat();
      await withToken(api);

      final user = await AuthRepository(api).restoreSession();

      expect(user, isNotNull);
      expect(user!.fullName, 'Someone');
    });

    test('a first launch with no cache still shows the welcome screen',
        () async {
      // Nothing was ever verified on this device, so there is no identity to
      // open on. Returning null is right here.
      final api = clientThat();
      await withToken(api);

      expect(await AuthRepository(api).restoreSession(), isNull);
    });

    test('the tokens are kept, not cleared', () async {
      await ironSecureStorage.write(key: 'auth_profile_v1', value: jsonEncode(profile));
      final api = clientThat();
      await withToken(api);

      await AuthRepository(api).restoreSession();

      expect(await ironSecureStorage.read(key: 'mil_access_token'),
          isNotNull);
    });
  });

  group('when the server refuses', () {
    test('a 401 clears the tokens and the cached identity', () async {
      // Rejected is not the same as unreachable. An expired session must not
      // be able to open the app from cache, or signing somebody out would
      // stop working the moment they went offline.
      await ironSecureStorage.write(key: 'auth_profile_v1', value: jsonEncode(profile));
      final api = clientThat(status: 401, body: {'detail': 'nope'});
      await withToken(api);

      final user = await AuthRepository(api).restoreSession();

      expect(user, isNull);
      expect(await ironSecureStorage.read(key: 'auth_profile_v1'),
          isNull);
    });
  });

  test('no token means no session, cache or not', () async {
    await ironSecureStorage.write(key: 'auth_profile_v1', value: jsonEncode(profile));
    final api = clientThat(status: 200, body: profile);

    expect(await AuthRepository(api).restoreSession(), isNull);
  });
}

class _Stub implements HttpClientAdapter {
  _Stub({this.status, this.body});

  final int? status;
  final Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (status == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'no network',
      );
    }
    if (status! >= 400) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: status,
          data: body,
        ),
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body ?? const {}),
      status!,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
