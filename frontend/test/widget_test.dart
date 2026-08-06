import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/env.dart';
import 'package:ironlink/core/theme.dart';
import 'package:ironlink/features/auth/screens/splash_screen.dart';

void main() {
  testWidgets('splash shows brand and the start button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: milTheme(),
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const SplashScreen(),
    ));

    // Logo fade-in runs for 1.8s
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('IronLink'), findsOneWidget);
    expect(find.text('ابدأ'), findsOneWidget);
  });

  test('Env builds api and ws urls from the same authority', () {
    expect(Env.apiBaseUrl, endsWith('/api/v1'));
    expect(
      Env.wsBaseUrl.startsWith('ws://') || Env.wsBaseUrl.startsWith('wss://'),
      isTrue,
    );
    // Both must point at the same host:port — a mismatch would silently
    // break the WS ticket handshake.
    expect(
      Uri.parse(Env.apiBaseUrl).authority,
      equals(Uri.parse(Env.wsBaseUrl).authority),
    );
  });
}
