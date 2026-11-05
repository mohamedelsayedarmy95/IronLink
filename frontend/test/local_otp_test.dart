import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/auth/local_otp.dart';

void main() {
  const api = 'http://localhost:18765/api/v1';
  const ws = 'ws://localhost:18765';

  test('local OTP requires matching explicit localhost REST and WS origins', () {
    expect(isLocalOtpTarget(api, ws), isTrue);
    for (final invalidApi in [
      'https://ironlink-api.onrender.com/api/v1',
      'http://192.168.1.2:18765/api/v1',
      'http://localhost/api/v1',
      'http://localhost:18765/api/v1?redirect=production',
      'http://local@localhost:18765/api/v1',
      'https://localhost:18765/api/v1',
    ]) {
      expect(isLocalOtpTarget(invalidApi, ws), isFalse);
    }
    expect(isLocalOtpTarget(api, 'ws://localhost:18766'), isFalse);
    expect(isLocalOtpTarget(api, 'wss://ironlink-api.onrender.com'), isFalse);
  });

  test('local OTP activation requires a debug build and explicit opt-in', () {
    const configured = bool.fromEnvironment('EXPECT_LOCAL_OTP');
    expect(localOtpEnabled, configured && kDebugMode);
  });
}
