/// Build-time backend configuration.
///
/// Two ways to point the app at a backend. Either works; the full-URL form wins
/// when both are supplied.
///
/// 1. Full URL — one flag, best for CI and hosted backends:
///
///      flutter build apk --release \
///        --dart-define=API_BASE_URL=https://ironlink-api.onrender.com/api/v1 \
///        --dart-define=WS_BASE_URL=wss://ironlink-api.onrender.com
///
/// 2. Host / port / TLS — convenient for local work:
///
///      flutter run --dart-define=API_HOST=10.140.128.63 --dart-define=USE_TLS=false
///
/// Defaults target the Android emulator (10.0.2.2 = host loopback).
/// Release builds MUST use a real hostname over TLS.
abstract class Env {
  // Full-URL overrides. The CI workflow has been passing these flags since
  // before anything read them, so release builds silently kept the emulator
  // defaults and shipped pointing at 10.0.2.2.
  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const _wsBaseUrlOverride = String.fromEnvironment('WS_BASE_URL');

  static const host = String.fromEnvironment(
    'API_HOST',
    defaultValue: '10.0.2.2',
  );

  /// Pass an empty value for a hosted backend on the default port:
  /// `--dart-define=API_PORT=`
  static const port = String.fromEnvironment(
    'API_PORT',
    defaultValue: '8000',
  );

  static const useTls = bool.fromEnvironment(
    'USE_TLS',
    defaultValue: false,
  );

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
}
