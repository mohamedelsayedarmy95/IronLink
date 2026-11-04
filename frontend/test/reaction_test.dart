import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/chat/widgets/reaction_bar.dart';

/// A reaction is content. "Somebody laughed at this" is exactly the inference
/// a metadata-only adversary is trying to draw, so the emoji travels encrypted
/// like a message body and the server stores reactions it cannot read.
///
/// These cover the part that lives on the device: folding individual reactions
/// into a legible aggregate, and the interaction rules that make one tap
/// enough.
void main() {
  Widget harness(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  group('the aggregate', () {
    testWidgets('nothing is drawn when nobody reacted', (tester) async {
      await tester.pumpWidget(harness(
        ReactionBar(reactions: const {}, myId: 'me', onToggle: (_) {}),
      ));
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('one reaction shows the emoji without a count', (tester) async {
      // A "1" next to every chip is noise: the emoji already says one person.
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'alice': '👍'},
          myId: 'me',
          onToggle: (_) {},
        ),
      ));
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('the same emoji from several people is counted once',
        (tester) async {
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'alice': '👍', 'bob': '👍', 'carol': '👍'},
          myId: 'me',
          onToggle: (_) {},
        ),
      ));
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('different emoji get their own chips', (tester) async {
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'alice': '👍', 'bob': '😂'},
          myId: 'me',
          onToggle: (_) {},
        ),
      ));
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('😂'), findsOneWidget);
    });

    testWidgets('an emoji from a newer build is shown, not dropped',
        (tester) async {
      // An unknown emoji is still something a person said. Discarding it
      // would make a reaction silently vanish for anyone on an older build.
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'alice': '🦀'},
          myId: 'me',
          onToggle: (_) {},
        ),
      ));
      expect(find.text('🦀'), findsOneWidget);
    });

    testWidgets('chip order does not depend on who reacted first',
        (tester) async {
      // A chip that jumps position when somebody else reacts is a chip you
      // have to look at before pressing.
      Future<List<String>> order(Map<String, String> reactions) async {
        await tester.pumpWidget(harness(
          ReactionBar(reactions: reactions, myId: 'me', onToggle: (_) {}),
        ));
        return tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((d) => d.isNotEmpty && int.tryParse(d) == null)
            .toList();
      }

      expect(
        await order({'a': '😂', 'b': '👍'}),
        await order({'b': '👍', 'a': '😂'}),
      );
    });
  });

  group('interaction', () {
    testWidgets('tapping a chip reports the emoji', (tester) async {
      String? tapped;
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'alice': '👍'},
          myId: 'me',
          onToggle: (e) => tapped = e,
        ),
      ));

      await tester.tap(find.text('👍'));
      expect(tapped, '👍');
    });

    testWidgets('your own reaction is marked by more than colour',
        (tester) async {
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'me': '👍', 'alice': '😂'},
          myId: 'me',
          onToggle: (_) {},
        ),
      ));

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .map((c) => c.decoration as BoxDecoration)
          .toList();
      // Exactly one chip carries an outline: the one that is yours.
      final outlined = containers.where(
        (d) => d.border != null && d.border!.top.color != Colors.transparent,
      );
      expect(outlined, hasLength(1));
    });

    testWidgets('a chip reads as a sentence to a screen reader',
        (tester) async {
      await tester.pumpWidget(harness(
        ReactionBar(
          reactions: const {'me': '👍', 'alice': '👍'},
          myId: 'me',
          onToggle: (_) {},
        ),
      ));

      expect(
        find.bySemanticsLabel(RegExp('including you.*remove yours')),
        findsOneWidget,
      );
    });
  });

  group('the picker', () {
    testWidgets('offers six and no more', (tester) async {
      // Six, not a keyboard. A picker turns one tap into a search, at which
      // point people type a message instead and the feature has failed at the
      // only thing it was for.
      await tester.pumpWidget(harness(
        ReactionPicker(selected: null, onPick: (_) {}),
      ));

      expect(ReactionBar.quickSet, hasLength(6));
      for (final emoji in ReactionBar.quickSet) {
        expect(find.text(emoji), findsOneWidget);
      }
    });

    testWidgets('shows which one is already yours', (tester) async {
      await tester.pumpWidget(harness(
        ReactionPicker(selected: '😂', onPick: (_) {}),
      ));

      final highlighted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color != Colors.transparent);
      expect(highlighted, hasLength(1));
    });

    testWidgets('picking reports the emoji', (tester) async {
      String? picked;
      await tester.pumpWidget(harness(
        ReactionPicker(selected: null, onPick: (e) => picked = e),
      ));

      await tester.tap(find.text('❤️'));
      expect(picked, '❤️');
    });
  });
}
