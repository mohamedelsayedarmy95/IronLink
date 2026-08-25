import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/widgets/connection_banner.dart';
import 'package:ironlink/core/ws_service.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// Not one screen in the product distinguished cached data from live data, so
/// a user reading a conversation on a dead connection saw exactly what they
/// would see on a good one.
///
/// The hard part is not showing the banner. It is *not* showing it: a phone
/// reconnects constantly — room to room, WiFi to mobile, back from the lock
/// screen — and a banner that fires on each of those makes a working app feel
/// broken and teaches people to ignore it by the time it matters.
void main() {
  late StreamController<WsStatus> status;

  setUp(() => status = StreamController<WsStatus>.broadcast());
  tearDown(() => status.close());

  Widget harness({Locale locale = const Locale('en')}) => MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: Scaffold(
          body: ConnectionBanner(ws: _FakeWs(status.stream)),
        ),
      );

  group('when it stays quiet', () {
    testWidgets('a healthy connection shows nothing', (tester) async {
      // Silence is the healthy state. A persistent badge saying the thing that
      // is true 99% of the time costs a row of pixels on every screen and
      // tells nobody anything.
      await tester.pumpWidget(harness());
      status.add(WsStatus.connected);
      await tester.pump();

      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('a brief drop is never mentioned', (tester) async {
      // The case that matters most. A handover between networks is a drop and
      // a recovery inside a second, and the user was never disconnected in any
      // sense they would recognise.
      await tester.pumpWidget(harness());

      status.add(WsStatus.connecting);
      await tester.pump(const Duration(milliseconds: 500));
      status.add(WsStatus.connected);
      await tester.pump();
      await tester.pump(ConnectionBanner.settleDelay);

      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('recovery clears it immediately', (tester) async {
      // No fade-out delay. Drawing attention to the moment things started
      // working again is not information anybody needs.
      await tester.pumpWidget(harness());

      status.add(WsStatus.offline);
      await tester.pump();
      await tester.pump(ConnectionBanner.settleDelay);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      status.add(WsStatus.connected);
      // Two turns: a broadcast stream delivers in a microtask, so the first
      // pump lets the event reach the listener and the second renders the
      // setState it caused. One pump asserts against the frame before the
      // widget has heard anything.
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });
  });

  group('when it speaks', () {
    testWidgets('a sustained outage is reported', (tester) async {
      await tester.pumpWidget(harness());

      status.add(WsStatus.offline);
      await tester.pump();
      await tester.pump(ConnectionBanner.settleDelay);

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      // Says what happens to what they type, not only that something is wrong.
      // The outbox does queue it, so this is a promise the product keeps.
      expect(
        find.textContaining('will send when you are back'),
        findsOneWidget,
      );
    });

    testWidgets('an outdated build is reported at once', (tester) async {
      // Terminal: the transport has stopped retrying because the server will
      // refuse this build every time. There is nothing to wait out.
      await tester.pumpWidget(harness());

      status.add(WsStatus.outdated);
      await tester.pump();

      expect(find.byIcon(Icons.system_update_alt), findsOneWidget);
      expect(find.textContaining('Update the app'), findsOneWidget);
    });

    testWidgets('waiting and updating look different in greyscale',
        (tester) async {
      // Two icons rather than one in two colours, so the difference between
      // "wait" and "act" survives a reader who cannot distinguish the hues.
      await tester.pumpWidget(harness());

      status.add(WsStatus.offline);
      await tester.pump();
      await tester.pump(ConnectionBanner.settleDelay);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.system_update_alt), findsNothing);
    });

    testWidgets('it reads in Arabic without overflowing', (tester) async {
      await tester.pumpWidget(harness(locale: const Locale('ar')));

      status.add(WsStatus.offline);
      await tester.pump();
      await tester.pump(ConnectionBanner.settleDelay);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('it announces itself to a screen reader', (tester) async {
      // A liveRegion, so the change is spoken when it happens rather than
      // discovered by exploring the screen.
      await tester.pumpWidget(harness());
      status.add(WsStatus.offline);
      await tester.pump();
      await tester.pump(ConnectionBanner.settleDelay);

      final semantics = tester.getSemantics(find.byType(ConnectionBanner));
      expect(semantics.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    });
  });
}

class _FakeWs implements WsService {
  _FakeWs(this._status);

  final Stream<WsStatus> _status;

  @override
  Stream<WsStatus> get status => _status;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
