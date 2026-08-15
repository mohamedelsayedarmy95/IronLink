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

    test('a build with no flags is TLS and points at a real backend', () {
      // This used to skip when no override was supplied, because the default
      // was the emulator loopback and could not satisfy it. That is exactly
      // the bug it should have caught: every build without explicit flags
      // shipped aimed at a host only reachable from a developer's machine.
      //
      // The default is now the deployed backend over TLS, so the assertion
      // runs unconditionally — a regression to a plaintext or loopback
      // default fails here rather than on someone's phone.
      expect(Env.apiBaseUrl, startsWith('https://'));
      expect(Env.wsBaseUrl, startsWith('wss://'));
      expect(Env.apiBaseUrl, isNot(contains('10.0.2.2')));
      expect(Env.apiBaseUrl, isNot(contains('localhost')));
      expect(Env.apiBaseUrl, isNot(contains('127.0.0.1')));
    });

    test('is flagged as a custom backend only when overridden', () {
      // Not const: `.isNotEmpty` on a fromEnvironment value is a runtime
      // call, so a const context here fails to compile.
      final overridden =
          const String.fromEnvironment('API_BASE_URL').isNotEmpty ||
              const String.fromEnvironment('API_HOST').isNotEmpty;
      expect(Env.isCustomBackend, overridden);
    });
  });
}
