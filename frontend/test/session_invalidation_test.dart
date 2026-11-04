import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/ws_service.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('temporary refresh failure keeps WebSocket credentials and outbox',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'mil_access_token': 'expired-access',
      'mil_refresh_token': 'valid-refresh',
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode =
          request.uri.path == '/auth/refresh' ? 503 : 401;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    await HttpOverrides.runZoned(() async {
      final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final ws = WsService.forTest(api: api);
      addTearDown(ws.dispose);
      ws.send({'type': 'text', 'client_ref': 'temporary-outage'});
      await ws.debugSettled;
      await ws.connect();
      expect(await api.refreshToken, 'valid-refresh');
      expect(await ws.debugOutbox, hasLength(1));
      expect(ws.debugReconnectScheduled, isTrue);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  for (final newLogin in [false, true]) {
    test('delayed refresh cannot undo ${newLogin ? 'new login' : 'revocation'}',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'mil_access_token': 'old-access',
        'mil_refresh_token': 'old-refresh',
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<HttpRequest>();
      server.listen((request) => received.complete(request));
      addTearDown(() => server.close(force: true));

      await HttpOverrides.runZoned(() async {
        final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        final refreshing = api.refreshSession();
        final request = await received.future;
        await request.drain<void>();
        await api.clearTokens();
        if (newLogin) {
          await api.saveTokens(access: 'new-access', refresh: 'new-refresh');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'access_token': 'late-old-access',
          'refresh_token': 'late-old-refresh',
        }));
        await request.response.close();
        expect(await refreshing, isFalse);
        expect(await api.accessToken, newLogin ? 'new-access' : isNull);
        expect(await api.refreshToken, newLogin ? 'new-refresh' : isNull);
      }, createHttpClient: _RealHttp().createHttpClient);
    });
  }
}
