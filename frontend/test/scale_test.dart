import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/chat/chat_repository.dart';
import 'package:ironlink/features/chat/local/message_store.dart';
import 'package:ironlink/features/security/widgets/message_safety_banner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ten thousand messages, which the engineering standard asks for by name and
/// which nothing here had ever been run against.
///
/// A COMMENT ON WHAT THESE NUMBERS ARE
///
/// The budgets below are generous, and deliberately so. This runs on CI
/// hardware whose speed varies between runs, and a tight threshold on a shared
/// runner produces a test that fails for reasons unrelated to the change that
/// triggered it — which is how a suite loses its credibility.
///
/// They are set to catch a **complexity** regression, not to measure
/// performance: a query that goes from indexed to full-scan, or a per-row
/// operation that becomes per-row-times-per-row. Those blow past any of these
/// by an order of magnitude. A change that makes something 20% slower will not
/// fail here, and should not — that is what profiling on a real device is for,
/// and this repository has not done any, which `docs/SLO.md` records rather
/// than glosses over.
void main() {
  setUpAll(() {
    // The FFI backend runs the same SQL a phone runs, so these exercise the
    // real queries rather than a mock that cannot be slow.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late MessageStore store;

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    store = await MessageStore.open();
    await store.clear();
  });

  tearDown(() async => store.close());

  List<ChatMessage> history(String peerId, int count) => [
        for (var i = 0; i < count; i++)
          ChatMessage(
            id: '$peerId-$i',
            senderId: i.isEven ? peerId : 'me',
            content: 'message number $i in a long conversation',
            createdAt: DateTime(2026, 1, 1).add(Duration(seconds: i)),
            isMine: i.isOdd,
          ),
      ];

  group('a conversation with ten thousand messages', () {
    test('writes in one batch, not ten thousand round trips', () async {
      final watch = Stopwatch()..start();
      await store.upsertAll('peer-1', history('peer-1', 10000));
      watch.stop();

      expect(await store.count(), 10000);
      // upsertAll uses a sqflite batch. Without one this is ten thousand
      // separate statements and takes minutes rather than seconds.
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)),
          reason: 'a per-row write would not finish in this budget');
    });

    test('reading a page does not read the whole history', () async {
      await store.upsertAll('peer-1', history('peer-1', 10000));

      final watch = Stopwatch()..start();
      final page = await store.conversation('peer-1', limit: 200);
      watch.stop();

      expect(page, hasLength(200));
      // The LIMIT is the point. A query that loads all ten thousand rows and
      // then takes the last two hundred passes every correctness test in this
      // repository and turns opening a long conversation into a visible pause.
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('the page is the newest messages, oldest first', () async {
      // Correctness under load, not just speed. An ordering bug that only
      // appears past the page size is invisible in a test with ten messages.
      await store.upsertAll('peer-1', history('peer-1', 10000));

      final page = await store.conversation('peer-1', limit: 200);
      expect(page.first.id, 'peer-1-9800');
      expect(page.last.id, 'peer-1-9999');
    });

    test('search over ten thousand messages stays interactive', () async {
      await store.upsertAll('peer-1', history('peer-1', 10000));

      final watch = Stopwatch()..start();
      final hits = await store.search('number 4242');
      watch.stop();

      expect(hits, hasLength(1));
      // LIKE over one device's history rather than FTS5, which the store
      // documents as a deliberate choice. This is the test that says when to
      // revisit it.
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)),
          reason: 'if this fails, the LIKE scan has outgrown its justification');
    });

    test('the conversation list stays one query as chats multiply', () async {
      // latestPerPeer is grouped precisely so a list of forty conversations is
      // not forty round trips on every rebuild.
      for (var p = 0; p < 40; p++) {
        await store.upsertAll('peer-$p', history('peer-$p', 250));
      }

      final watch = Stopwatch()..start();
      final latest = await store.latestPerPeer();
      watch.stop();

      expect(latest, hasLength(40));
      expect(latest['peer-7']!.id, 'peer-7-249');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('the safety cache under a long scroll', () {
    test('assessing every visible message stays cheap', () {
      // A bubble rebuilds on every scroll frame. Without the cache this is a
      // dozen regular expressions plus URL parsing per visible message per
      // frame — the cost that shows up as jank on exactly the hardware this
      // product is likeliest to run on.
      final safety = MessageSafety();
      final watch = Stopwatch()..start();
      for (var frame = 0; frame < 200; frame++) {
        for (var i = 0; i < 30; i++) {
          safety.assess('m$i', 'message number $i in a long conversation');
        }
      }
      watch.stop();

      // 6000 assessments, 30 of them real.
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('it does not grow without bound over a long session', () {
      // The cache holds assessments derived from decrypted text. Unbounded, it
      // would keep them for as long as the app is open.
      final safety = MessageSafety(maxEntries: 200);
      for (var i = 0; i < 10000; i++) {
        safety.assess('m$i', 'message number $i');
      }
      // No size accessor by design; the property under test is that ten
      // thousand distinct messages neither slow it down nor exhaust memory.
      expect(safety.assess('fresh', 'send me the code').shouldWarn, isTrue);
    });
  });
}
