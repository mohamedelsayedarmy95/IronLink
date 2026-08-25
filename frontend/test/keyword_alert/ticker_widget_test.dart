import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/bloc/alert_bloc.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/local/alert_store.dart';
import 'package:ironlink/features/keyword_alert/widgets/smart_alert_ticker.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// The gate for this phase is an RTL/LTR and screen-reader walkthrough, so
/// these tests walk it: the ticker has to be readable by a screen reader, have
/// touch targets a finger can hit, lay out in both directions, and — above all
/// — keep the distinction between "I swiped this away" and "I have dealt with
/// this", which is the entire reason the feature is more than a notification.
///
/// TWO HARNESS CONSTRAINTS, BOTH LEARNED THE HARD WAY
///
/// The store is in memory rather than sqflite: the widget binding runs a test
/// body in a fake-async zone whose clock never advances to meet a future
/// completing on a real I/O thread, so `pumpAndSettle` over real file I/O
/// hangs until the ten-minute timeout.
///
/// And the bloc is constructed *inside* each test rather than in `setUp`. A
/// bloc created in `setUp` binds its stream controller to that zone while the
/// test body runs in the fake one, so its emissions never arrive — and every
/// assertion then sees an empty ticker for no visible reason.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  late InMemoryAlertStore store;
  late AlertBloc bloc;

  KeywordRule ruleFor(
    String keyword, {
    KeywordPriority priority = KeywordPriority.medium,
  }) =>
      KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: keyword,
        normalize: (s) => s.trim().toLowerCase(),
        now: t0,
        priority: priority,
      );

  KeywordAlert alertFor(KeywordRule rule, {required String documentHash}) =>
      KeywordAlert(
        id: KeywordAlert.deriveId(
          conversationId: 'c1',
          messageId: 'm1',
          attachmentId: 'a1',
          keywordRuleId: rule.id,
          sourceDocumentHash: documentHash,
          processingVersion: 1,
        ),
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'u1',
        keywordRuleId: rule.id,
        sourceDocumentHash: documentHash,
        processingVersion: 1,
        status: AlertStatus.alertCreated,
        priorityLevel: rule.priority,
        matchType: MatchType.exact,
        confidence: 0.97,
        matchedText: rule.displayRepresentation,
        contextText: 'please sign the ${rule.displayRepresentation} today',
        detectedAt: t0,
        createdAt: t0,
        updatedAt: t0,
        expiresAt: t0.add(KeywordAlert.retentionWindow),
      );


  /// The ticker's own entrance transition, isolated from the four that
  /// Scaffold's route machinery keeps above it and the one Dismissible builds
  /// below it to drag the card.
  Finder entranceSlide() => find.ancestor(
        of: find.byType(Dismissible),
        matching: find.descendant(
          of: find.byType(AnimatedSwitcher),
          matching: find.byType(SlideTransition),
        ),
      );

  Future<void> pumpTicker(
    WidgetTester tester, {
    List<KeywordRule> rules = const [],
    Locale locale = const Locale('en'),
    void Function(KeywordAlert)? onOpenDocument,
    bool reduceMotion = false,
  }) async {
    store = InMemoryAlertStore();
    bloc = AlertBloc(store, now: () => t0);

    for (var i = 0; i < rules.length; i++) {
      await store.saveRule(rules[i]);
      await store.record(alertFor(rules[i], documentHash: 'h$i'));
    }

    final app = MaterialApp(
      locale: locale,
      // Inside, not around: MaterialApp builds its own MediaQuery from the
      // window, so one wrapped outside it is discarded before any descendant
      // can read it.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(
          body: SmartAlertTicker(onOpenDocument: onOpenDocument),
        ),
      ),
    );

    await tester.pumpWidget(app);
    bloc.add(const AlertsRequested());
    await tester.pumpAndSettle();
  }

  group('what the ticker shows', () {
    testWidgets('nothing at all when there is nothing outstanding',
        (tester) async {
      await pumpTicker(tester);
      expect(find.byIcon(Icons.find_in_page_outlined), findsNothing);
    });

    testWidgets('the matched text, once an alert exists', (tester) async {
      await pumpTicker(tester, rules: [ruleFor('contract')]);
      expect(find.text('contract'), findsOneWidget);
    });

    testWidgets('a count when several are queued, not a stack of tickers',
        (tester) async {
      // §5.5/§5.2.1: a second alert consolidates rather than stacking a second
      // full-height banner over the chat.
      await pumpTicker(
        tester,
        rules: [ruleFor('contract'), ruleFor('invoice')],
      );

      expect(find.byIcon(Icons.find_in_page_outlined), findsOneWidget);
      expect(find.textContaining('2'), findsOneWidget);
    });

    testWidgets('records that it was actually presented', (tester) async {
      // An alert created while the app was backgrounded was never shown, and
      // claiming later that it "was shown" would be false.
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      final stored = (await store.history(now: t0)).single;
      expect(stored.status, AlertStatus.alertPresented);
    });
  });

  group('acknowledge is not seen', () {
    testWidgets('swiping hides the ticker but leaves the alert outstanding',
        (tester) async {
      // §5.2.1: swipe is "not currently shown", never "handled".
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      await tester.drag(find.text('contract'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.text('contract'), findsNothing);
      final stored = (await store.history(now: t0)).single;
      expect(stored.status, AlertStatus.alertPresented);
      expect(stored.status.isOutstanding, isTrue);
      expect(stored.acknowledgedAt, isNull);
    });

    testWidgets('opening the document is not acknowledgement either',
        (tester) async {
      KeywordAlert? opened;
      await pumpTicker(
        tester,
        rules: [ruleFor('contract')],
        onOpenDocument: (a) => opened = a,
      );

      await tester.tap(find.byIcon(Icons.description_outlined));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      final stored = (await store.history(now: t0)).single;
      expect(stored.status, AlertStatus.documentOpened);
      expect(stored.acknowledgedAt, isNull);
    });

    testWidgets('only the explicit press clears it', (tester) async {
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      final stored = (await store.history(now: t0)).single;
      expect(stored.status, AlertStatus.acknowledged);
      expect(stored.acknowledgedAt, isNotNull);
      expect(find.text('contract'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('reads as one sentence, not five fragments', (tester) async {
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      // bySemanticsLabel matches the merged node, which is what a screen
      // reader actually announces — getSemantics on the outer widget returns
      // the container, whose own label is empty by design.
      expect(
        find.bySemanticsLabel(RegExp('Smart Alert.*contract')),
        findsWidgets,
      );
    });

    testWidgets('both actions meet the 48dp touch floor', (tester) async {
      // §5.9. The visible glyph is 20dp; the target may not be.
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      for (final icon in [Icons.description_outlined, Icons.check]) {
        final target = tester.getSize(
          find
              .ancestor(
                of: find.byIcon(icon),
                matching: find.byType(SizedBox),
              )
              .first,
        );
        expect(
          target.width,
          greaterThanOrEqualTo(SmartAlertTicker.minTouchTarget),
        );
        expect(
          target.height,
          greaterThanOrEqualTo(SmartAlertTicker.minTouchTarget),
        );
      }
    });

    testWidgets('both actions are labelled for a screen reader',
        (tester) async {
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      expect(find.bySemanticsLabel('Open document'), findsWidgets);
      expect(find.bySemanticsLabel('Acknowledge'), findsWidgets);
    });

    testWidgets('honours the platform reduce-motion setting', (tester) async {
      await pumpTicker(
        tester,
        rules: [ruleFor('contract')],
        reduceMotion: true,
      );

      // The slide is decoration; the fade carries the meaning. Anchored to
      // the card rather than the whole subtree: Dismissible builds its own
      // SlideTransition to drag the card, and Scaffold's route machinery has
      // more. Only the entrance transition above the card is ours.
      expect(entranceSlide(), findsNothing);
      expect(find.text('contract'), findsOneWidget);
    });

    testWidgets('slides in when motion is not reduced', (tester) async {
      // The negative test above only means something if the positive one
      // holds: without this, deleting the slide entirely would still pass.
      await pumpTicker(tester, rules: [ruleFor('contract')]);

      expect(entranceSlide(), findsOneWidget);
    });
  });

  group('direction', () {
    testWidgets('lays out in Arabic without overflowing', (tester) async {
      final rule = KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: 'عقد',
        normalize: (s) => s.trim(),
        now: t0,
      );
      await pumpTicker(tester, rules: [rule], locale: const Locale('ar'));

      expect(find.text('عقد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long match does not overflow in either direction',
        (tester) async {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        final rule = KeywordRule.create(
          ownerUserId: 'u1',
          conversationScope: 'c1',
          displayRepresentation: 'a very long keyword that will not fit ' * 3,
          normalize: (s) => s.trim().toLowerCase(),
          now: t0,
        );
        await pumpTicker(tester, rules: [rule], locale: locale);

        expect(tester.takeException(), isNull, reason: '$locale');
      }
    });
  });

  group('priority', () {
    test('critical and high get their own colour; medium and low do not', () {
      // Colouring everything is the same as colouring nothing, and colour is
      // never the only signal — ordering and the screen-reader label carry it
      // too.
      expect(
        priorityColor(KeywordPriority.critical),
        isNot(priorityColor(KeywordPriority.medium)),
      );
      expect(
        priorityColor(KeywordPriority.high),
        isNot(priorityColor(KeywordPriority.medium)),
      );
      expect(
        priorityColor(KeywordPriority.medium),
        priorityColor(KeywordPriority.low),
      );
    });

    testWidgets('the critical alert leads, however recent the others are',
        (tester) async {
      await pumpTicker(tester, rules: [
        ruleFor('invoice', priority: KeywordPriority.low),
        ruleFor('contract', priority: KeywordPriority.critical),
      ]);

      expect(find.text('contract'), findsOneWidget);
      expect(find.text('invoice'), findsNothing);
    });
  });
}
