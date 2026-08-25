import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/widgets/empty_state.dart';
import 'package:ironlink/features/security/domain/scam_signals.dart';
import 'package:ironlink/features/security/widgets/message_safety_banner.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// Arabic is this product's primary language, and nothing verified that a
/// single screen laid out correctly in it. The strings were translated and the
/// direction was never checked — the usual shape of the bug: a product that is
/// bilingual in its content and left-to-right in its bones.
///
/// Two kinds of test here, because they catch different failures.
///
/// The first group pumps real widgets under `ar` and fails on an overflow or a
/// thrown exception. That catches a layout that breaks when the direction flips
/// or the text grows.
///
/// The second is a static guard over the source, and it is the more valuable
/// half. The directional bugs that matter do not throw:
/// `Padding(EdgeInsets.only(left: 16))` renders perfectly in both directions
/// and is simply wrong in one of them, with the gap on the far side of the
/// screen instead of beside the text. Nothing at runtime will ever report it.
/// The repository turns out to be clean of these; this is what keeps it clean.
void main() {
  Widget arabic(Widget child) => MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: Scaffold(body: child),
      );

  ScamAssessment codeRequest() =>
      const ScamIntelligence().assess('ابعتلي الكود اللي وصلك حالا');

  group('screens lay out in Arabic', () {
    testWidgets('the direction actually flips', (tester) async {
      // The precondition for everything else in this file. If Arabic strings
      // are rendering inside a left-to-right layout, every test below passes
      // while the product is still wrong.
      await tester.pumpWidget(arabic(const SizedBox.shrink()));
      final context = tester.element(find.byType(SizedBox));
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('the empty state', (tester) async {
      await tester.pumpWidget(arabic(const IronEmptyState(
        title: 'لا توجد محادثات بعد',
        message: 'ابدأ محادثة جديدة من زر الإضافة في الأعلى',
        rings: 1,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a safety warning', (tester) async {
      await tester.pumpWidget(arabic(
        MessageSafetyBanner(isMine: false, assessment: codeRequest()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a safety warning with its explanation open', (tester) async {
      // The expanded state is the one that grows, and growth is where an
      // overflow shows up.
      await tester.pumpWidget(arabic(
        MessageSafetyBanner(isMine: false, assessment: codeRequest()),
      ));
      await tester.tap(find.text('لماذا أرى هذا؟'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a narrow screen', (tester) async {
      // Overflow is a function of width, and a test at the default 800 logical
      // pixels proves nothing about the smallest phone this will run on.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(arabic(
        MessageSafetyBanner(isMine: false, assessment: codeRequest()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('at the largest system text size', (tester) async {
      // Dynamic type is an accessibility requirement, and it is the other way
      // a row that fits becomes a row that does not.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(arabic(const IronEmptyState(
        title: 'لا توجد محادثات بعد',
        message: 'ابدأ محادثة جديدة',
        rings: 1,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the source stays direction-agnostic', () {
    test('no widget hardcodes a left or right edge', () {
      // The bug class that never throws. EdgeInsetsDirectional says "start"
      // and "end", which follow the reading direction.
      final offenders = _sourceHits(
        RegExp(r'EdgeInsets\.only\([^)]*\b(left|right):'),
      );
      expect(offenders, isEmpty,
          reason: 'use EdgeInsetsDirectional.only(start:/end:)');
    });

    test('no widget hardcodes a left or right alignment', () {
      // Gradient stops are excluded, and that is a judgement rather than an
      // oversight. `Alignment.topLeft` on a LinearGradient names the corner
      // the sweep starts from — a decorative direction, not a reading one.
      // Mirroring it in Arabic would change how a message bubble is shaded for
      // no reason anybody could state. Layout alignment is a different thing
      // and is still caught.
      final offenders = _sourceHits(
        RegExp(r'Alignment\.(center|top|bottom)(Left|Right)\b'),
        skip: RegExp(r'^\s*(begin|end):'),
      );
      expect(offenders, isEmpty,
          reason: 'use AlignmentDirectional, which follows the direction');
    });

    test('no widget hardcodes left or right text alignment', () {
      final offenders = _sourceHits(RegExp(r'TextAlign\.(left|right)\b'));
      expect(offenders, isEmpty, reason: 'use TextAlign.start / TextAlign.end');
    });

    test('Arabic is the template bundle, not a translation of one', () {
      // Ordering matters more than it looks. Whichever ARB is the template is
      // the one a developer adds a string to first, and the other is the one
      // that gets forgotten. With Arabic as the template, a forgotten string
      // is missing in English — visible to the people writing it — rather than
      // missing in Arabic, where it would ship.
      final config = File('l10n.yaml');
      expect(config.existsSync(), isTrue);
      expect(config.readAsStringSync(), contains('app_ar.arb'));
    });
  });
}

/// Every `lib/**.dart` line matching [pattern], as `path:line  text`.
List<String> _sourceHits(RegExp pattern, {RegExp? skip}) {
  final hits = <String>[];
  final dir = Directory('lib');
  if (!dir.existsSync()) return hits;

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Generated localisations are not hand-written and are not ours to fix.
    if (entity.path.contains('app_localizations')) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (skip != null && skip.hasMatch(lines[i])) continue;
      if (pattern.hasMatch(lines[i])) {
        hits.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
  }
  return hits;
}
