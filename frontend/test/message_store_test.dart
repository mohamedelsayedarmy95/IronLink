import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/crypto/attachment_crypto.dart';
import 'package:ironlink/features/chat/chat_repository.dart';
import 'package:ironlink/features/chat/local/message_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The store holds decrypted plaintext, so what it must never retain matters
/// as much as what it finds. These cover both.
void main() {
  setUpAll(() {
    // sqflite has no desktop implementation; the FFI backend runs the same
    // SQL the device does, so these exercise the real queries.
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

  ChatMessage msg(
    String id,
    String content, {
    bool mine = false,
    bool deleted = false,
    DateTime? at,
  }) =>
      ChatMessage(
        id: id,
        senderId: mine ? 'me' : 'them',
        content: content,
        createdAt: at ?? DateTime(2026, 1, 1),
        isMine: mine,
        deleted: deleted,
      );

  group('what must never be retained', () {
    test('a secret chat is never written', () async {
      await store.upsertAll('peer-1', [msg('1', 'burn after reading')],
          isSecret: true);

      expect(await store.count(), 0);
      expect(await store.search('burn'), isEmpty);
    });

    test('a deleted message keeps its row but loses its text', () async {
      await store.upsertAll('peer-1', [msg('1', 'regrettable', deleted: true)]);

      // The tombstone survives so the conversation still shows something was
      // removed...
      final conversation = await store.conversation('peer-1');
      expect(conversation, hasLength(1));
      expect(conversation.single.deleted, isTrue);
      expect(conversation.single.content, isNull);

      // ...but "delete for everyone" must not leave the words searchable.
      expect(await store.search('regrettable'), isEmpty);
    });

    test('deleting one conversation leaves the others alone', () async {
      await store.upsertAll('blocked', [msg('1', 'unwanted')]);
      await store.upsertAll('kept', [msg('2', 'wanted')]);

      await store.deleteConversation('blocked');

      expect(await store.search('unwanted'), isEmpty);
      expect(await store.search('wanted'), hasLength(1));
    });

    test('clear wipes everything, for sign-out on a shared device', () async {
      await store.upsertAll('peer-1', [msg('1', 'private')]);
      await store.clear();

      expect(await store.count(), 0);
      expect(await store.search('private'), isEmpty);
    });
  });

  group('upgrading an existing install', () {
    test('a v1 database gains peer_name without losing messages', () async {
      // This is the path every existing install takes on next launch. If
      // onUpgrade is wrong the app cannot open its own database, so the
      // v1 schema is recreated here verbatim rather than mocked.
      final path = '${await databaseFactory.getDatabasesPath()}'
          '/ironlink_messages.db';
      await databaseFactory.deleteDatabase(path);

      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE messages (
                id TEXT PRIMARY KEY,
                peer_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                content TEXT,
                kind TEXT NOT NULL DEFAULT 'text',
                created_at INTEGER NOT NULL,
                is_mine INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
          },
        ),
      );
      await v1.insert('messages', {
        'id': 'old-1',
        'peer_id': 'peer-1',
        'sender_id': 'them',
        'content': 'written before the upgrade',
        'kind': 'text',
        'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        'is_mine': 0,
        'deleted': 0,
      });
      await v1.close();

      final upgraded = await MessageStore.open();
      addTearDown(upgraded.close);

      final hit = (await upgraded.search('before the upgrade')).single;
      expect(hit.message.id, 'old-1');
      expect(hit.peerName, isNull, reason: 'v1 rows have no name to carry');

      // Reading alone would pass even if onUpgrade did nothing, since
      // SELECT * simply yields null for a column that is not there. Writing
      // the new column is what actually proves the ALTER TABLE ran.
      await upgraded.upsertAll('peer-2', [msg('new-1', 'written after')],
          peerName: 'Sgt. Nabil');
      expect((await upgraded.search('written after')).single.peerName,
          'Sgt. Nabil');
    });
  });

  group('media survives a restart', () {
    test('a voice note keeps its pointer, key, duration and waveform',
        () async {
      final key = AttachmentCrypto().newKey(mimeType: 'audio/mp4', sizeBytes: 9);
      await store.upsertAll('peer-1', [
        ChatMessage(
          id: 'v1',
          senderId: 'them',
          content: null,
          createdAt: DateTime(2026, 1, 1),
          isMine: false,
          kind: 'voice',
          encrypted: true,
          mediaKey: 'obj-123',
          attachmentKey: key,
          duration: 7.5,
          waveform: const [0.1, 0.9, 0.4],
        ),
      ]);

      // The cache is the history now — the server's ciphertext cannot be
      // decrypted after the fact — so a cached voice note that loses these
      // is simply broken.
      final restored = (await store.conversation('peer-1')).single;
      expect(restored.mediaKey, 'obj-123');
      expect(restored.duration, 7.5);
      expect(restored.waveform, const [0.1, 0.9, 0.4]);
      expect(restored.attachmentKey, isNotNull);
      expect(restored.attachmentKey!.key, key.key);
      expect(restored.attachmentKey!.nonce, key.nonce);
      expect(restored.attachmentKey!.mimeType, 'audio/mp4');
    });

    test('a text message stores no media metadata', () async {
      await store.upsertAll('peer-1', [msg('t1', 'just words')]);

      final restored = (await store.conversation('peer-1')).single;
      expect(restored.mediaKey, isNull);
      expect(restored.attachmentKey, isNull);
      expect(restored.duration, isNull);
    });

    test('a deleted media message loses its pointer and key', () async {
      final key = AttachmentCrypto().newKey(mimeType: 'image/jpeg', sizeBytes: 1);
      await store.upsertAll('peer-1', [
        ChatMessage(
          id: 'd1',
          senderId: 'them',
          content: 'gone',
          createdAt: DateTime(2026, 1, 1),
          isMine: false,
          kind: 'image',
          deleted: true,
          mediaKey: 'obj-9',
          attachmentKey: key,
        ),
      ]);

      // "Delete for everyone" must not leave a working key to the attachment
      // sitting in the cache.
      final restored = (await store.conversation('peer-1')).single;
      expect(restored.mediaKey, isNull);
      expect(restored.attachmentKey, isNull);
    });
  });

  group('remembering whether a message was encrypted', () {
    test('the flag survives a round trip', () async {
      await store.upsertAll('peer-1', [
        ChatMessage(
          id: 'e1',
          senderId: 'them',
          content: 'protected',
          createdAt: DateTime(2026, 1, 1),
          isMine: false,
          encrypted: true,
        ),
        msg('p1', 'in the clear'),
      ]);

      final conversation = await store.conversation('peer-1');
      final byId = {for (final m in conversation) m.id: m};

      // The bubble marks unencrypted messages, and the ciphertext is long
      // gone by the time a cached row is read back — so if this were not
      // stored, every restored message would be mislabelled.
      expect(byId['e1']!.encrypted, isTrue);
      expect(byId['p1']!.encrypted, isFalse);
    });

    test('rows from before the column existed are not claimed as encrypted',
        () async {
      // v1/v2 rows genuinely were sent in the clear. Defaulting them to
      // "encrypted" would be a false assurance about real messages.
      final path = '${await databaseFactory.getDatabasesPath()}'
          '/ironlink_messages.db';
      await databaseFactory.deleteDatabase(path);

      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE messages (
                id TEXT PRIMARY KEY,
                peer_id TEXT NOT NULL,
                peer_name TEXT,
                sender_id TEXT NOT NULL,
                content TEXT,
                kind TEXT NOT NULL DEFAULT 'text',
                created_at INTEGER NOT NULL,
                is_mine INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
          },
        ),
      );
      await old.insert('messages', {
        'id': 'legacy',
        'peer_id': 'peer-1',
        'sender_id': 'them',
        'content': 'sent before encryption',
        'kind': 'text',
        'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        'is_mine': 0,
        'deleted': 0,
      });
      await old.close();

      final upgraded = await MessageStore.open();
      addTearDown(upgraded.close);

      expect(
        (await upgraded.conversation('peer-1')).single.encrypted,
        isFalse,
      );
    });
  });

  group('naming the conversation a hit came from', () {
    test('a hit carries the peer name', () async {
      await store.upsertAll('peer-1', [msg('1', 'the briefing is at noon')],
          peerName: 'Cpt. Rashid');

      final hit = (await store.search('briefing')).single;
      expect(hit.peerName, 'Cpt. Rashid');
    });

    test('a row cached without a name is still a usable result', () async {
      // Rows written by v1 of the schema have no name. Dropping them from
      // results would lose real messages over a cosmetic gap.
      await store.upsertAll('peer-1', [msg('1', 'orders received')]);

      final hit = (await store.search('orders')).single;
      expect(hit.peerName, isNull);
      expect(hit.peerId, 'peer-1');
    });

    test('a renamed contact updates on the next cache write', () async {
      await store.upsertAll('peer-1', [msg('1', 'acknowledged')],
          peerName: 'Unknown');
      await store.upsertAll('peer-1', [msg('1', 'acknowledged')],
          peerName: 'Lt. Karim');

      expect((await store.search('acknowledged')).single.peerName, 'Lt. Karim');
    });
  });

  group('search', () {
    test('finds a message across conversations', () async {
      await store.upsertAll('peer-1', [msg('1', 'the briefing is at noon')]);
      await store.upsertAll('peer-2', [msg('2', 'briefing moved')]);
      await store.upsertAll('peer-3', [msg('3', 'unrelated')]);

      final hits = await store.search('briefing');
      expect(hits, hasLength(2));
      expect(hits.map((h) => h.peerId), containsAll(['peer-1', 'peer-2']));
    });

    test('matches partial words', () async {
      await store.upsertAll('p', [msg('1', 'reconnaissance')]);
      expect(await store.search('connaiss'), hasLength(1));
    });

    test('returns newest first', () async {
      await store.upsertAll('p', [
        msg('old', 'report', at: DateTime(2026, 1, 1)),
        msg('new', 'report', at: DateTime(2026, 6, 1)),
      ]);

      final hits = await store.search('report');
      expect(hits.first.message.id, 'new');
    });

    test('an empty query returns nothing rather than everything', () async {
      await store.upsertAll('p', [msg('1', 'something')]);
      expect(await store.search(''), isEmpty);
      expect(await store.search('   '), isEmpty);
    });

    test('wildcards are searched literally', () async {
      // Without escaping, "%" as a LIKE wildcard would match every message.
      await store.upsertAll('p', [
        msg('1', 'battery at 50%'),
        msg('2', 'nothing relevant'),
      ]);

      final hits = await store.search('50%');
      expect(hits, hasLength(1));
      expect(hits.single.message.id, '1');
    });

    test('underscore is searched literally too', () async {
      await store.upsertAll('p', [
        msg('1', 'file_name.pdf'),
        msg('2', 'fileXname.pdf'),
      ]);

      final hits = await store.search('file_name');
      expect(hits, hasLength(1));
      expect(hits.single.message.id, '1');
    });
  });

  group('caching', () {
    test('re-syncing the same message updates rather than duplicates',
        () async {
      await store.upsertAll('p', [msg('1', 'first version')]);
      await store.upsertAll('p', [msg('1', 'edited version')]);

      expect(await store.count(), 1);
      expect((await store.conversation('p')).single.content, 'edited version');
    });

    test('a conversation reads back oldest first, as displayed', () async {
      await store.upsertAll('p', [
        msg('b', 'second', at: DateTime(2026, 2, 1)),
        msg('a', 'first', at: DateTime(2026, 1, 1)),
      ]);

      final conversation = await store.conversation('p');
      expect(conversation.map((m) => m.id), ['a', 'b']);
    });

    test('conversations stay separate', () async {
      await store.upsertAll('p1', [msg('1', 'one')]);
      await store.upsertAll('p2', [msg('2', 'two')]);

      expect(await store.conversation('p1'), hasLength(1));
      expect((await store.conversation('p1')).single.id, '1');
    });
  });
}
