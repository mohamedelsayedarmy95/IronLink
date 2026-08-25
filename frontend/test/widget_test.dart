import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/theme.dart';
import 'package:ironlink/features/auth/auth_repository.dart';
import 'package:ironlink/features/auth/screens/splash_screen.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// Wraps a screen with everything it needs from the app shell.
///
/// The localization delegates are the part that matters: every screen now
/// reads its copy through `L.of(context)`, so a test that omits them fails
/// on the first string rather than on anything it meant to check.
///
/// AuthRepository is here because the welcome screen looks for an existing
/// session on launch. There is no keystore under `flutter test`, so the
/// lookup fails and returns null — which is the path this test wants anyway.
Widget _wrap(Widget child, {Locale locale = const Locale('ar')}) {
  return RepositoryProvider(
    create: (_) => AuthRepository(ApiClient()),
    child: MaterialApp(
      theme: ironLinkDarkTheme(),
      locale: locale,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('welcome screen', () {
    testWidgets('shows the brand and a way in, in Arabic', (tester) async {
      await tester.pumpWidget(_wrap(const SplashScreen()));
      // The entrance animation runs for 900ms.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('IRONLINK'), findsOneWidget);
      expect(find.text('ابدأ الآن'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    testWidgets('shows the same screen in English', (tester) async {
      await tester.pumpWidget(
        _wrap(const SplashScreen(), locale: const Locale('en')),
      );
      await tester.pump(const Duration(seconds: 1));

      // The wordmark is not translated; the actions are.
      expect(find.text('IRONLINK'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('lays out under reduced motion', (tester) async {
      // With animations disabled the controller jumps to its end state; the
      // screen must still be fully rendered rather than stuck at opacity 0.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _wrap(const SplashScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('IRONLINK'), findsOneWidget);
      expect(find.text('ابدأ الآن'), findsOneWidget);
    });
  });
}
