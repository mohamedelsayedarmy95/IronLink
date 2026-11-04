import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/chat/chat_repository.dart';
import 'package:ironlink/features/chat/widgets/reply_quote.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// Reply is the feature that makes a group conversation readable, and this
/// product did not have it — though the database column had been sitting there
/// unused since the schema was created.
///
/// The interesting part is not the feature. It is that a reply here carries an
/// id and nothing else, because the server has never held the quoted text and
/// cannot send it. Everything below is about what that implies.
void main() {
  ChatMessage message({
    String id = 'm1',
    String? content = 'the original message',
    bool mine = false,
    bool deleted = false,
    String kind = 'text',
  }) =>
      ChatMessage(
        id: id,
        senderId: mine ? 'me' : 'them',
        content: content,
        createdAt: DateTime(2026, 1, 1),
        isMine: mine,
        deleted: deleted,
        kind: kind,
      );

  Widget harness(Widget child, {Locale locale = const Locale('en')}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: Scaffold(body: child),
      );

  group('the quotation', () {
    testWidgets('shows the original text', (tester) async {
      await tester.pumpWidget(harness(
        ReplyQuote(original: message(), myId: 'me'),
      ));

      expect(find.text('the original message'), findsOneWidget);
    });

    testWidgets('says so when this device does not have the original',
        (tester) async {
      // The consequence of end-to-end encryption that no other messenger has
      // to handle: there is nowhere to fetch it from. Not the server, which
      // holds ciphertext and no key; not anywhere else. So it is stated,
      // rather than rendering an empty block that reads as a bug.
      await tester.pumpWidget(harness(
        const ReplyQuote(original: null, myId: 'me'),
      ));

      expect(find.text('Not available on this device'), findsOneWidget);
    });

    testWidgets('a retracted message is named, not quoted', (tester) async {
      // The whole point of retracting a message is that it stops being
      // readable. A reply that preserved the text would undo that for every
      // reader of the conversation.
      await tester.pumpWidget(harness(
        ReplyQuote(original: message(deleted: true), myId: 'me'),
      ));

      expect(find.text('This message was removed'), findsOneWidget);
      expect(find.text('the original message'), findsNothing);
    });

    testWidgets('an attachment is described rather than blank', (tester) async {
      for (final (kind, label) in [
        ('image', 'Photo'),
        ('voice', 'Voice note'),
        ('file', 'Attachment'),
      ]) {
        await tester.pumpWidget(harness(
          ReplyQuote(original: message(content: null, kind: kind), myId: 'me'),
        ));
        expect(find.text(label), findsOneWidget, reason: kind);
      }
    });

    testWidgets('it distinguishes answering yourself from answering them',
        (tester) async {
      await tester.pumpWidget(harness(
        ReplyQuote(original: message(mine: true), myId: 'me'),
      ));
      expect(find.text('You'), findsOneWidget);

      await tester.pumpWidget(harness(
        ReplyQuote(original: message(mine: false), myId: 'me'),
      ));
      expect(find.text('Replying to'), findsOneWidget);
    });

    testWidgets('a long original is truncated rather than filling the bubble',
        (tester) async {
      await tester.pumpWidget(harness(
        SizedBox(
          width: 250,
          child: ReplyQuote(
            original: message(content: 'a very long message ' * 40),
            myId: 'me',
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(
        find.textContaining('a very long message').first,
      );
      expect(text.maxLines, 2);
    });

    testWidgets('the composer preview can be dismissed', (tester) async {
      // A stray swipe picks the wrong message. Undoing it should cost one tap.
      var dismissed = false;
      await tester.pumpWidget(harness(
        ReplyQuote(
          original: message(),
          myId: 'me',
          onDismiss: () => dismissed = true,
        ),
      ));

      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('a bubble quote has no dismiss control', (tester) async {
      // Only the composer preview is dismissible. A close button on a sent
      // message would suggest the quotation could be removed after the fact,
      // which it cannot — the reference is part of the message.
      await tester.pumpWidget(harness(
        ReplyQuote(original: message(), myId: 'me'),
      ));

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('it lays out in Arabic', (tester) async {
      await tester.pumpWidget(harness(
        ReplyQuote(original: message(content: 'الرسالة الأصلية'), myId: 'me'),
        locale: const Locale('ar'),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('الرسالة الأصلية'), findsOneWidget);
    });
  });

  group('the wire format', () {
    test('a reply carries an id and never the quoted text', () {
      // If the text travelled inside the envelope it would be stored twice
      // under two keys, so retracting the original would leave copies of it
      // inside every reply — a deletion that does not delete.
      final parsed = ChatMessage.fromJson(
        {
          'id': 'm2',
          'sender_id': 'them',
          'content_ciphertext': 'envelope',
          'created_at': '2026-01-01T00:00:00Z',
          'status': 'sent',
          'reply_to_id': 'm1',
        },
        myId: 'me',
      );

      expect(parsed.replyToId, 'm1');
    });

    test('a message answering nothing has no reference', () {
      final parsed = ChatMessage.fromJson(
        {
          'id': 'm2',
          'sender_id': 'them',
          'content_ciphertext': 'envelope',
          'created_at': '2026-01-01T00:00:00Z',
          'status': 'sent',
        },
        myId: 'me',
      );

      expect(parsed.replyToId, isNull);
    });
  });
}
