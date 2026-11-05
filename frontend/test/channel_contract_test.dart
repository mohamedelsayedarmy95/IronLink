import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/features/channel/bloc/channel_bloc.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final visibility in ['public', 'private']) {
    test('channel discovery parses $visibility UUID response', () async {
      FlutterSecureStorage.setMockInitialValues({'mil_access_token': 'synthetic'});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/channels');
        expect(request.headers.value('Authorization'), 'Bearer synthetic');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([
          {
            'id': '1433de55-dc61-48e6-a854-f50c5eb765f7',
            'owner_id': 'cda97a9b-2d91-4804-8c63-baa32e7e4fd5',
            'name': 'Permitted channel',
            'description': null,
            'channel_type': visibility,
            'category': null,
            'is_verified': false,
            'subscriber_count': 1,
          }
        ]));
        await request.response.close();
      });
      final baseUrl = 'http://127.0.0.1:${server.port}';
      final api = ApiClient(baseUrl: baseUrl);
      final rows = await HttpOverrides.runZoned(
        () => ChannelApiService(baseUrl: baseUrl, api: api).getChannels(),
        createHttpClient: _RealHttp().createHttpClient,
      );
      expect(rows.single.id, '1433de55-dc61-48e6-a854-f50c5eb765f7');
      expect(rows.single.ownerId, 'cda97a9b-2d91-4804-8c63-baa32e7e4fd5');
      expect(rows.single.type, visibility);
    });
  }
}
