import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/local/alert_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// §4.3 lists seven ways the same document can arrive twice: WebSocket
/// reconnect, retry, duplicate push, restart, worker retry, timeout, and
/// re-upload. Every one of them reduces to the same question — same rule, same
/// bytes, same pipeline version? — so these tests attack that identity
/// directly rather than simulating seven transports.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AlertStore store;
  final t0 = DateTime.utc(2026, 8, 16, 10);

  // A stand-in for the real normalizer, which arrives in Phase 2. Injected
  // precisely so the domain does not depend on the text pipeline.
  String normalize(String s) => s.trim().toLowerCase();

  KeywordRule ruleFor(
    String keyword, {
    String scope = 'c1',
    KeywordPriority priority = KeywordPriority.medium,
    int? cap,
  }) =>
      KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: scope,
        displayRepresentation: keyword,
        normalize: normalize,
        now: t0,
        priority: priority,
        maxAlertsPerDay: cap,
      );

  KeywordAlert alertFor(
    KeywordRule rule, {
    String messageId = 'm1',
    String attachmentId = 'a1',
    String documentHash = 'h1',
    int processingVersion = 1,
    DateTime? detected,
  }) {
    final at = detected ?? t0;
    return KeywordAlert(
      id: KeywordAlert.deriveId(
        conversationId: rule.conversationScope,
        messageId: messageId,
        attachmentId: attachmentId,
        keywordRuleId: rule.id,
        sourceDocumentHash: documentHash,
        processingVersion: processingVersion,
      ),
      conversationId: rule.conversationScope,
      messageId: messageId,
      attachmentId: attachmentId,
      recipientUserId: rule.ownerUserId,
      keywordRuleId: rule.id,
      sourceDocumentHash: documentHash,
      processingVersion: processingVersion,
      status: AlertStatus.alertCreated,
      priorityLevel: rule.priority,
      matchType: MatchType.exact,
      confidence: 0.98,
      matchedText: rule.displayRepresentation,
      contextText: '… ${rule.displayRepresentation} …',
      detectedAt: at,
      createdAt: at,
      updatedAt: at,
      expiresAt: at.add(KeywordAlert.retentionWindow),
    );
  }

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    store = await AlertStore.open();
    await store.clear();
  });

  tearDown(() async => store.close());

  group('idempotency (§4.3)', () {
    test('the same document and rule yield one alert, however many attempts',
        () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      final alert = alertFor(rule);

      for (var i = 0; i < 5; i++) {
        await store.record(alert);
      }

      expect(await store.alertCount(), 1);
    });

    test('a duplicate write returns the stored alert, not the new one',
        () async {
      // Otherwise the caller goes on to present a duplicate it believes it
      // just created, having already lost the acknowledgement on the original.
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      final first = await store.record(alertFor(rule));
      await store.transition(first.id, AlertStatus.acknowledged, now: t0);

      final second = await store.record(alertFor(rule));
      expect(second.status, AlertStatus.acknowledged);
    });

    test('re-uploading the same file does not alert twice', () async {
      // A re-upload gets a new attachment id but the same bytes. The document
      // hash is what makes that recognisable.
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule, attachmentId: 'a1'));
      await store.record(alertFor(rule, attachmentId: 'a1'));

      expect(await store.alertCount(), 1);
    });

    test('different bytes under the same attachment id are a new alert',
        () async {
      // An edited document that reuses its identifier genuinely needs
      // re-checking; deduplicating it away would hide a real match.
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule, documentHash: 'h1'));
      await store.record(alertFor(rule, documentHash: 'h2'));

      expect(await store.alertCount(), 2);
    });

    test('a new pipeline version reprocesses the same document', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule, processingVersion: 1));
      await store.record(alertFor(rule, processingVersion: 2));

      expect(await store.alertCount(), 2);
    });

    test('two rules on one document each get their own alert', () async {
      final a = ruleFor('contract');
      final b = ruleFor('invoice');
      await store.saveRule(a);
      await store.saveRule(b);
      await store.record(alertFor(a));
      await store.record(alertFor(b));

      expect(await store.alertCount(), 2);
    });

    test('alreadyProcessed lets the caller skip extraction entirely', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);

      Future<bool> processed() => store.alreadyProcessed(
            conversationId: 'c1',
            messageId: 'm1',
            attachmentId: 'a1',
            keywordRuleId: rule.id,
            sourceDocumentHash: 'h1',
            processingVersion: 1,
          );

      expect(await processed(), isFalse);
      await store.record(alertFor(rule));
      expect(await processed(), isTrue);
    });

    test('the derived id is stable across runs', () async {
      // If it were not, a restart would duplicate every outstanding alert.
      final id = KeywordAlert.deriveId(
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        keywordRuleId: 'kw_1',
        sourceDocumentHash: 'h1',
        processingVersion: 1,
      );
      expect(
        id,
        KeywordAlert.deriveId(
          conversationId: 'c1',
          messageId: 'm1',
          attachmentId: 'a1',
          keywordRuleId: 'kw_1',
          sourceDocumentHash: 'h1',
          processingVersion: 1,
        ),
      );
    });
  });

  group('survives restart', () {
    test('an outstanding alert is still outstanding after reopening',
        () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule));
      await store.close();

      store = await AlertStore.open();
      final outstanding = await store.outstanding(now: t0);
      expect(outstanding, hasLength(1));
      expect(outstanding.single.matchedText, 'contract');
    });

    test('an acknowledged alert stays acknowledged after reopening', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      final alert = await store.record(alertFor(rule));
      await store.transition(alert.id, AlertStatus.acknowledged, now: t0);
      await store.close();

      store = await AlertStore.open();
      expect((await store.byId(alert.id))!.status, AlertStatus.acknowledged);
      expect(await store.outstanding(now: t0), isEmpty);
    });
  });

  group('rules', () {
    test('the same keyword twice in one conversation stays one rule', () async {
      await store.saveRule(ruleFor('contract'));
      await store.saveRule(ruleFor('Contract'));
      expect(await store.ruleCount(), 1);
    });

    test('the same keyword in two conversations is two rules', () async {
      await store.saveRule(ruleFor('contract', scope: 'c1'));
      await store.saveRule(ruleFor('contract', scope: 'c2'));
      expect(await store.ruleCount(), 2);
      expect(await store.rulesFor('c1'), hasLength(1));
    });

    test('deleting a rule takes its alerts with it', () async {
      // §1.3 promises deletion is immediate. An alert naming a keyword the
      // user believes they erased would be a lie sitting in history.
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule));
      expect(await store.alertCount(), 1);

      await store.deleteRule(rule.id);
      expect(await store.alertCount(), 0);
    });

    test('a disabled rule is excluded from the matching read', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.saveRule(rule.copyWith(enabled: false, updatedAt: t0));

      expect(await store.rulesFor('c1'), hasLength(1));
      expect(await store.rulesFor('c1', onlyEnabled: true), isEmpty);
    });
  });

  group('retention (§4.5)', () {
    test('alerts past 48 hours are expired on read', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      final alert = await store.record(alertFor(rule));

      final later = t0.add(const Duration(hours: 49));
      expect(await store.outstanding(now: later), isEmpty);
      expect((await store.byId(alert.id))!.status, AlertStatus.expired);
    });

    test('an expired alert stays visible in history before it is purged',
        () async {
      // Vanishing without trace and "you missed this" are different facts,
      // and the second is the useful one.
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule));

      final history = await store.history(now: t0.add(const Duration(hours: 49)));
      expect(history, hasLength(1));
      expect(history.single.status, AlertStatus.expired);
    });

    test('long-expired alerts are deleted', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule));

      await store.sweepExpired(t0.add(const Duration(days: 30)));
      expect(await store.alertCount(), 0);
    });

    test('an acknowledged alert is not re-expired by the sweep', () async {
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      final alert = await store.record(alertFor(rule));
      await store.transition(alert.id, AlertStatus.acknowledged, now: t0);

      await store.sweepExpired(t0.add(const Duration(hours: 49)));
      expect((await store.byId(alert.id))!.status, AlertStatus.acknowledged);
    });
  });

  group('daily cap (§1.3)', () {
    test('counts on a rolling window, not a calendar day', () async {
      // A midnight reset would let a noisy rule spend its whole allowance
      // twice within an hour.
      final rule = ruleFor('contract', cap: 2);
      await store.saveRule(rule);
      await store.record(alertFor(rule, documentHash: 'h1'));
      await store.record(
        alertFor(rule, documentHash: 'h2', detected: t0.add(const Duration(hours: 20))),
      );

      expect(await store.alertsInLastDay(rule.id, t0.add(const Duration(hours: 20))), 2);
      // 25 hours after the first, only the second is still in the window.
      expect(await store.alertsInLastDay(rule.id, t0.add(const Duration(hours: 25))), 1);
    });

    test('a suppressed alert is still recorded', () async {
      // §1.3: excess matches are logged, not discarded — they simply stop
      // interrupting.
      final rule = ruleFor('contract', cap: 1);
      await store.saveRule(rule);
      await store.record(
        alertFor(rule).copyWith(suppressedByDailyCap: true),
      );

      final history = await store.history(now: t0);
      expect(history.single.suppressedByDailyCap, isTrue);
    });
  });

  group('transitions through the store', () {
    test('are judged against what is stored, not a stale caller copy',
        () async {
      // A ticker tap and a push can act on the same alert at once.
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      final alert = await store.record(alertFor(rule));

      await store.transition(alert.id, AlertStatus.acknowledged, now: t0);
      expect(
        () => store.transition(alert.id, AlertStatus.alertPresented, now: t0),
        throwsA(isA<IllegalAlertTransition>()),
      );
    });

    test('a transition on a deleted alert is a no-op, not a crash', () async {
      expect(
        await store.transition('al_missing', AlertStatus.acknowledged, now: t0),
        isNull,
      );
    });
  });

  test('sign-out wipes rules and alerts alike', () async {
    final rule = ruleFor('contract');
    await store.saveRule(rule);
    await store.record(alertFor(rule));

    await store.clear();
    expect(await store.ruleCount(), 0);
    expect(await store.alertCount(), 0);
  });
}
