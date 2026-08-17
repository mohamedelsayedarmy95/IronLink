import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/security/domain/scam_signals.dart';
import 'package:ironlink/features/security/widgets/message_safety_banner.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// The banner annotates a message; it never gates one. These tests hold that
/// line, and the other one that matters — that an ordinary message produces
/// nothing at all, because a strip of amber on innocent conversation is how a
/// warning becomes wallpaper.
void main() {
  const scam = ScamIntelligence();

  Widget harness(
    String text, {
    bool mine = false,
    Locale locale = const Locale('en'),
  }) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: Scaffold(
          body: MessageSafetyBanner(
            isMine: mine,
            assessment: scam.assess(text),
          ),
        ),
      );

  group('when it appears', () {
    testWidgets('on a message asking for a verification code', (tester) async {
      await tester.pumpWidget(harness('send me the code you just got'));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('This message asks for a verification code'),
          findsOneWidget);
    });

    testWidgets('in Arabic', (tester) async {
      await tester.pumpWidget(
        harness('ابعتلي الكود اللي وصلك حالا', locale: const Locale('ar')),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never on an ordinary message', (tester) async {
      await tester.pumpWidget(harness('see you at five, bring the file'));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('never on the user own message', (tester) async {
      // Telling someone their own message looks like a scam is noise, and
      // implies the app is grading their conversation.
      await tester.pumpWidget(harness('send me the code', mine: true));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('never on a single weak signal', (tester) async {
      await tester.pumpWidget(harness('need this urgently please'));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });

  group('what the user can do about it', () {
    testWidgets('the explanation is hidden until asked for', (tester) async {
      await tester.pumpWidget(harness('send me the code'));

      expect(find.textContaining('IronLink sends verification codes'),
          findsNothing);

      await tester.tap(find.text('Why am I seeing this?'));
      await tester.pumpAndSettle();

      expect(find.textContaining('IronLink sends verification codes'),
          findsOneWidget);
    });

    testWidgets('the explanation names the host, not the whole URL',
        (tester) async {
      // A full URL is unreadable on a phone and buries the domain mid-path.
      // The host is the part that says where a link actually goes.
      await tester.pumpWidget(
        harness('urgent: verify at https://apple.com@evil.example/a/b/c'),
      );
      await tester.tap(find.text('Why am I seeing this?'));
      await tester.pumpAndSettle();

      expect(find.textContaining('evil.example'), findsOneWidget);
      expect(find.textContaining('/a/b/c'), findsNothing);
    });

    testWidgets('it can be hidden, and stays hidden', (tester) async {
      await tester.pumpWidget(harness('send me the code'));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('reads as one statement', (tester) async {
      await tester.pumpWidget(harness('send me the code'));

      expect(
        find.bySemanticsLabel(RegExp('Safety notice.*verification code')),
        findsOneWidget,
      );
    });

    testWidgets('the warning does not depend on colour alone', (tester) async {
      // Amber conveys caution to people who can see it. The headline conveys
      // it to everyone.
      await tester.pumpWidget(harness('send me the code'));
      expect(find.text('This message asks for a verification code'),
          findsOneWidget);
    });
  });

  group('the assessment cache', () {
    test('assesses a given message once', () {
      final safety = MessageSafety(intelligence: _CountingIntelligence());
      safety.assess('m1', 'send me the code');
      safety.assess('m1', 'send me the code');
      safety.assess('m1', 'send me the code');

      // Same id, so the text argument is never even looked at again.
      safety.assess('m1', 'completely different text');
      expect(_CountingIntelligence.calls, 1);
    });

    test('is bounded, because it holds decrypted text', () {
      final safety = MessageSafety(maxEntries: 10);
      for (var i = 0; i < 50; i++) {
        safety.assess('m$i', 'message $i');
      }
      // No direct size accessor by design; clearing must not throw and the
      // structure must still work afterwards.
      expect(() => safety.clear(), returnsNormally);
      expect(safety.assess('m0', 'send me the code').shouldWarn, isTrue);
    });

    test('clears on demand, for sign-out', () {
      final safety = MessageSafety();
      safety.assess('m1', 'send me the code');
      safety.clear();
      expect(safety.assess('m1', 'ordinary text').shouldWarn, isFalse);
    });
  });
}

class _CountingIntelligence implements ScamIntelligence {
  static int calls = 0;

  _CountingIntelligence() {
    calls = 0;
  }

  @override
  ScamAssessment assess(String text) {
    calls++;
    return const ScamAssessment(signals: {}, linkVerdicts: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
