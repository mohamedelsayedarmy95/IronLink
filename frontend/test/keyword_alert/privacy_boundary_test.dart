import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/domain/sender_report.dart';
import 'package:ironlink/features/keyword_alert/keyword_alert_pipeline.dart';
import 'package:ironlink/features/keyword_alert/local/alert_store.dart';
import 'package:ironlink/features/keyword_alert/ocr/text_extractor.dart';
import 'package:ironlink/features/keyword_alert/text/text_normalizer.dart';

/// P-1: a keyword is visible to its owner and to nobody else — not the sender,
/// not group admins, not other members, not the server.
///
/// The strongest version of that guarantee is structural rather than
/// behavioural: the sender's view has no field a keyword could occupy, and the
/// rules never leave the device, so there is no payload to inspect. These
/// tests hold both ends.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  KeywordRule ruleFor(String keyword) => KeywordRule.create(
        ownerUserId: 'recipient',
        conversationScope: 'c1',
        displayRepresentation: keyword,
        normalize: const TextNormalizer().normalizeToString,
        now: t0,
      );

  KeywordAlert alertFor(
    KeywordRule rule, {
    AlertStatus status = AlertStatus.alertCreated,
  }) =>
      KeywordAlert(
        id: 'al_1',
        conversationId: 'c1',
        messageId: 'm1',
        attachmentId: 'a1',
        recipientUserId: 'recipient',
        keywordRuleId: rule.id,
        sourceDocumentHash: 'h1',
        processingVersion: 1,
        status: status,
        priorityLevel: rule.priority,
        matchType: MatchType.exact,
        confidence: 0.97,
        matchedText: rule.displayRepresentation,
        contextText: 'the ${rule.displayRepresentation} is attached',
        documentPage: 3,
        detectedAt: t0,
        createdAt: t0,
        updatedAt: t0,
        expiresAt: t0.add(KeywordAlert.retentionWindow),
      );

  group('the sender report (§6.1, §1.4)', () {
    test('says an alert fired and nothing about what matched', () {
      final rule = ruleFor('audit-case-4471');
      final entry = SenderReportEntry.from(
        alertFor(rule),
        recipientPermitsSharing: true,
      );

      final serialized = entry.toJson().toString();
      expect(entry.alertRaised, isTrue);
      expect(serialized, isNot(contains('audit-case-4471')));
      expect(serialized, isNot(contains('attached')));
      expect(serialized, isNot(contains('3')));
    });

    test('has nowhere to put a keyword even if someone tried', () {
      // The boundary is the type. A permission check inside a screen holds
      // until someone writes a second screen; a type with no field for the
      // keyword holds by construction.
      final keys = SenderReportEntry.from(
        alertFor(ruleFor('contract')),
        recipientPermitsSharing: true,
      ).toJson().keys.toSet();

      expect(keys, {
        'recipient_user_id',
        'alert_raised',
        'acknowledged',
        'shared_at',
      });
    });

    test('shows nothing at all without the recipient\'s permission', () {
      final entry = SenderReportEntry.from(
        alertFor(ruleFor('contract')),
        recipientPermitsSharing: false,
      );
      expect(entry.isVisibleToSender, isFalse);
    });

    test('distinguishes acknowledged from merely raised', () {
      // Useful to a sender — "did they deal with it?" — and it reveals nothing
      // about what was matched.
      final rule = ruleFor('contract');
      expect(
        SenderReportEntry.from(
          alertFor(rule, status: AlertStatus.acknowledged),
          recipientPermitsSharing: true,
        ).acknowledged,
        isTrue,
      );
      expect(
        SenderReportEntry.from(
          alertFor(rule, status: AlertStatus.alertPresented),
          recipientPermitsSharing: true,
        ).acknowledged,
        isFalse,
      );
    });

    test('a document that matched nothing reports no alert', () {
      final entry = SenderReportEntry.from(
        alertFor(ruleFor('contract'), status: AlertStatus.noMatch),
        recipientPermitsSharing: true,
      );
      expect(entry.alertRaised, isFalse);
    });

    test('a group admin is a sender with a title, and gets the same object',
        () {
      // §6.2 forbids group-level surveillance outright: there is no admin view
      // of who is watching for what, because there is no wider type to return.
      final admin = SenderReportEntry.from(
        alertFor(ruleFor('contract')),
        recipientPermitsSharing: true,
      );
      expect(admin.toJson().containsKey('keyword'), isFalse);
      expect(admin.toJson().containsKey('matched_text'), isFalse);
    });
  });

  group('rules never leave the device', () {
    test('a rule carries the owner it belongs to, and is scoped to one chat',
        () {
      final rule = ruleFor('contract');
      expect(rule.ownerUserId, 'recipient');
      expect(rule.conversationScope, 'c1');
    });

    test('the store answers only for the conversation asked about', () async {
      final store = InMemoryAlertStore();
      await store.saveRule(ruleFor('contract'));

      expect(await store.rulesFor('c1'), hasLength(1));
      expect(await store.rulesFor('c2'), isEmpty);
    });

    test('signing out erases the watchlist, not just the alerts', () async {
      // A handed-on device must not keep the previous user's keywords, which
      // would say more about them than their message history would.
      final store = InMemoryAlertStore();
      await store.saveRule(ruleFor('contract'));
      await store.record(alertFor(ruleFor('contract')));

      await store.clear();
      expect(await store.ruleCount(), 0);
      expect(await store.alertCount(), 0);
    });
  });

  group('what an alert keeps', () {
    test('a stored alert holds no rule text, only a reference', () async {
      // The keyword lives in one place. An alert that copied it would mean two
      // places to erase when the user deletes a rule, and one of them would
      // eventually be missed.
      final store = InMemoryAlertStore();
      final rule = ruleFor('audit-case-4471');
      await store.saveRule(rule);
      await store.record(alertFor(rule));

      final stored = (await store.history(now: t0)).single;
      expect(stored.keywordRuleId, rule.id);
      // matchedText is the document's word, which happens to coincide here —
      // what must not appear is a copy of the rule's own configuration.
      expect(stored.toRow().containsKey('normalized_representation'), isFalse);
      expect(stored.toRow().containsKey('regex_pattern'), isFalse);
    });

    test('deleting the rule takes the alerts with it', () async {
      final store = InMemoryAlertStore();
      final rule = ruleFor('contract');
      await store.saveRule(rule);
      await store.record(alertFor(rule));

      await store.deleteRule(rule.id);
      expect(await store.alertCount(), 0);
    });
  });

  group('the local pipeline touches no network', () {
    test('its inputs are bytes and its outputs are rows', () {
      // Stated as a property of the constructor: there is no client, no
      // endpoint, and no token anywhere in what it needs to run.
      final pipeline = KeywordAlertPipeline(
        store: InMemoryAlertStore(),
        extractors: TextExtractorRegistry.minimal,
        now: () => t0,
      );
      expect(pipeline.cloudEnabled, isFalse);
    });

    test('cloud processing is off unless explicitly turned on', () {
      final pipeline = KeywordAlertPipeline(
        store: InMemoryAlertStore(),
        extractors: TextExtractorRegistry.minimal,
      );
      expect(pipeline.cloudEnabled, isFalse);
    });
  });
}
