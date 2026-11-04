/// Build-time backend configuration.
///
/// The deployed backend is the default, so a plain `flutter run` or
/// `flutter build apk` produces a working app. This was previously inverted:
/// the emulator loopback (`10.0.2.2`) was the default, so any build without
/// explicit flags shipped pointing at a host that only exists on a developer's
/// machine — which is why sign-in failed on a real device.
///
/// Overriding for local work, in order of precedence:
///
/// 1. Full URL — one flag, best for CI and alternate environments:
///
///      flutter run \
///        --dart-define=API_BASE_URL=http://192.168.1.10:8000/api/v1 \
///        --dart-define=WS_BASE_URL=ws://192.168.1.10:8000
///
/// 2. Host / port / TLS — convenient against a local server:
///
///      flutter run --dart-define=API_HOST=10.0.2.2 \
///                  --dart-define=API_PORT=8000 \
///                  --dart-define=USE_TLS=false
abstract class Env {
  /// The deployed backend. Declared here rather than only in CI so that a
  /// build with no flags still reaches a real server.
  static const _defaultHost = 'ironlink-api.onrender.com';

  // Full-URL overrides win when supplied.
  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const _wsBaseUrlOverride = String.fromEnvironment('WS_BASE_URL');

  static const host = String.fromEnvironment(
    'API_HOST',
    defaultValue: _defaultHost,
  );

  /// Empty means "the scheme's default port", which is what a hosted backend
  /// behind a proxy needs. Pass a value only when targeting a local server:
  /// `--dart-define=API_PORT=8000`
  static const port = String.fromEnvironment('API_PORT', defaultValue: '');

  /// Defaults to TLS. A plaintext build has to be asked for explicitly — in a
  /// product whose premise is a trustworthy channel, insecure transport should
  /// never be something you get by forgetting a flag.
  static const useTls = bool.fromEnvironment('USE_TLS', defaultValue: true);

  static String get _authority => port.isEmpty ? host : '$host:$port';

  /// Trailing slashes are stripped so callers can concatenate `'$base/path'`
  /// without producing a double slash, which some proxies 404 rather than
  /// normalise.
  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Base for REST calls — includes the `/api/v1` prefix.
  static String get apiBaseUrl => _apiBaseUrlOverride.isNotEmpty
      ? _trim(_apiBaseUrlOverride)
      : '${useTls ? 'https' : 'http'}://$_authority/api/v1';

  /// Base for WebSocket connections — no `/api/v1`; the WS routes are mounted
  /// at the application root.
  static String get wsBaseUrl => _wsBaseUrlOverride.isNotEmpty
      ? _trim(_wsBaseUrlOverride)
      : '${useTls ? 'wss' : 'ws'}://$_authority';

  /// True when pointing at something other than the deployed backend. Used to
  /// surface a visible marker in debug builds so a screenshot taken against a
  /// local server is never mistaken for production.
  static bool get isCustomBackend =>
      _apiBaseUrlOverride.isNotEmpty || host != _defaultHost;
}
