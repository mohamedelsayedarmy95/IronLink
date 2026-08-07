import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/env.dart';

/// These assertions depend on --dart-define values, so the expectations branch
/// on what was actually supplied. Run the production shape with:
///
///   flutter test test/env_test.dart \
///     --dart-define=API_BASE_URL=https://ironlink-api.onrender.com/api/v1 \
///     --dart-define=WS_BASE_URL=wss://ironlink-api.onrender.com
void main() {
  group('Env', () {
    test('apiBaseUrl carries the /api/v1 prefix', () {
      expect(Env.apiBaseUrl, contains('/api/v1'));
    });

    test('wsBaseUrl uses a websocket scheme and omits /api/v1', () {
      expect(Env.wsBaseUrl, anyOf(startsWith('ws://'), startsWith('wss://')));
      // The WebSocket routes are mounted at the application root, not under
      // the versioned API prefix.
      expect(Env.wsBaseUrl, isNot(contains('/api/v1')));
    });

    test('no base URL ends in a slash', () {
      // Callers build paths as '$base/segment'; a trailing slash would produce
      // a double slash, which some proxies 404 rather than normalise.
      expect(Env.apiBaseUrl.endsWith('/'), isFalse);
      expect(Env.wsBaseUrl.endsWith('/'), isFalse);
    });

    test('release configuration is TLS and is not the emulator default', () {
      const apiOverride = String.fromEnvironment('API_BASE_URL');
      if (apiOverride.isEmpty) {
        // Local/dev run — nothing to assert beyond the shape checks above.
        return;
      }
      expect(Env.apiBaseUrl, startsWith('https://'));
      expect(Env.wsBaseUrl, startsWith('wss://'));
      expect(Env.apiBaseUrl, isNot(contains('10.0.2.2')));
      expect(Env.apiBaseUrl, isNot(contains('localhost')));
    });
  });
}
