/// Build-time backend configuration.
///
/// Defaults target the Android emulator (10.0.2.2 = host loopback).
/// For a physical device over USB/Wi-Fi, pass your PC's LAN IP:
///
///   flutter run --dart-define=API_HOST=10.140.128.63 --dart-define=USE_TLS=false
///
/// Release builds MUST set USE_TLS=true and a real hostname.
abstract class Env {
  static const host = String.fromEnvironment(
    'API_HOST',
    defaultValue: '10.0.2.2',
  );

  static const port = String.fromEnvironment(
    'API_PORT',
    defaultValue: '8000',
  );

  static const useTls = bool.fromEnvironment(
    'USE_TLS',
    defaultValue: false,
  );

  static String get _authority => port.isEmpty ? host : '$host:$port';

  static String get apiBaseUrl =>
      '${useTls ? 'https' : 'http'}://$_authority/api/v1';

  static String get wsBaseUrl => '${useTls ? 'wss' : 'ws'}://$_authority';
}
