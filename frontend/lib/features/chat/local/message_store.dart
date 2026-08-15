import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../chat_repository.dart';

/// On-device cache of decrypted messages.
///
/// WHY THIS EXISTS RATHER THAN A SERVER SEARCH ENDPOINT
///
/// The server stores `content_ciphertext` and, by design, cannot read it.
/// Searching message text therefore cannot happen server-side without either
/// storing plaintext or building a server-side index derived from it — both
/// of which would hand the server exactly what end-to-end encryption exists
/// to withhold. Search belongs on the device, over messages this client has
/// already decrypted for display.
///
/// WHAT IS STORED HERE
///
/// Plaintext. That is unavoidable — a search index over ciphertext finds
/// nothing — and it is the same plaintext already rendered on screen, so it
/// grants no access the device did not already have. It does mean the file
/// is worth protecting:
///
/// * The database lives in the app's private directory, unreadable by other
///   apps on a non-rooted device.
/// * Secret chats are never written here. A message the user asked to be
///   ephemeral must not outlive its conversation in a search index.
/// * [clear] wipes everything and is called on sign-out, so a shared or
///   handed-on device does not keep the previous user's conversations.
///
/// This is a deliberate trade: local search and offline reading, in exchange
/// for plaintext at rest on a device the user already controls.
class MessageStore {
  MessageStore._(this._db);

  final Database _db;

  static const _fileName = 'ironlink_messages.db';
  static const _version = 3;

  static Future<MessageStore> open() async {
    final path = '${await getDatabasesPath()}/$_fileName';
    final db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            peer_id TEXT NOT NULL,
            -- Denormalised on purpose: a search hit has to say which
            -- conversation it came from, and the name is not otherwise
            -- available offline.
            peer_name TEXT,
            sender_id TEXT NOT NULL,
            content TEXT,
            kind TEXT NOT NULL DEFAULT 'text',
            created_at INTEGER NOT NULL,
            is_mine INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            -- Whether the message actually arrived end-to-end encrypted.
            -- Persisted because the bubble marks the ones that did not, and
            -- recomputing it after the fact is impossible: the ciphertext is
            -- long gone by the time a cached message is read back.
            encrypted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // Conversation reads are always "newest first for one peer", so the
        // index matches that shape rather than indexing the columns alone.
        await db.execute(
          'CREATE INDEX idx_messages_peer_time '
          'ON messages (peer_id, created_at DESC)',
        );
        // Search scans content across every conversation.
        await db.execute(
          'CREATE INDEX idx_messages_content ON messages (content)',
        );
      },
      onUpgrade: (db, from, to) async {
        // v1 had no peer_name. Existing rows keep a null name until the
        // conversation is opened again and re-cached, which is why the
        // column is nullable rather than NOT NULL with a placeholder.
        if (from < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN peer_name TEXT');
        }
        if (from < 3) {
          // Defaults to 0. Rows cached before encryption became the default
          // genuinely were not encrypted, so claiming otherwise would be a
          // false assurance about messages that were sent in the clear.
          await db.execute(
            'ALTER TABLE messages ADD COLUMN encrypted INTEGER NOT NULL '
            'DEFAULT 0',
          );
        }
      },
    );
    return MessageStore._(db);
  }

  /// Writes messages for one conversation.
  ///
  /// [isSecret] conversations are skipped entirely rather than filtered on
  /// read: the guarantee should be that the text was never written, not that
  /// something remembers to hide it.
  Future<void> upsertAll(
    String peerId,
    List<ChatMessage> messages, {
    String? peerName,
    bool isSecret = false,
  }) async {
    if (isSecret || messages.isEmpty) return;

    final batch = _db.batch();
    for (final m in messages) {
      batch.insert(
        'messages',
        {
          'id': m.id,
          'peer_id': peerId,
          'peer_name': peerName,
          'sender_id': m.senderId,
          // A deleted message keeps its row so the conversation still shows
          // the tombstone, but its text is dropped — "delete for everyone"
          // must not leave the words sitting in a search index.
          'content': m.deleted ? null : m.content,
          'kind': m.kind,
          'created_at': m.createdAt.millisecondsSinceEpoch,
          'is_mine': m.isMine ? 1 : 0,
          'deleted': m.deleted ? 1 : 0,
          'encrypted': m.encrypted ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Cached messages for one conversation, oldest first for display.
  Future<List<ChatMessage>> conversation(String peerId, {int limit = 200}) async {
    final rows = await _db.query(
      'messages',
      where: 'peer_id = ?',
      whereArgs: [peerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.reversed.map(_toMessage).toList();
  }

  /// Full-text-ish search across every cached conversation.
  ///
  /// LIKE rather than FTS5: the corpus is one device's message history, where
  /// a scan is fast enough, and FTS would add a second table to keep in sync
  /// for no gain at this size. Worth revisiting if histories grow large.
  Future<List<MessageSearchHit>> search(String query, {int limit = 100}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final rows = await _db.rawQuery(
      '''
      SELECT * FROM messages
       WHERE deleted = 0
         AND content IS NOT NULL
         AND content LIKE ? ESCAPE '\\'
       ORDER BY created_at DESC
       LIMIT ?
      ''',
      ['%${_escapeLike(term)}%', limit],
    );

    return rows
        .map((r) => MessageSearchHit(
              message: _toMessage(r),
              peerId: r['peer_id'] as String,
              peerName: r['peer_name'] as String?,
            ))
        .toList();
  }

  /// Removes one conversation, when the user asks for it.
  ///
  /// Deliberately NOT called on block. Blocking stops future contact; it is
  /// not a request to destroy what was already said, and those messages are
  /// often the evidence behind a report that was just filed.
  Future<void> deleteConversation(String peerId) async {
    await _db.delete('messages', where: 'peer_id = ?', whereArgs: [peerId]);
  }

  /// Wipes everything. Called on sign-out.
  Future<void> clear() async {
    await _db.delete('messages');
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM messages'),
      ) ??
      0;

  Future<void> close() => _db.close();

  static ChatMessage _toMessage(Map<String, Object?> r) => ChatMessage(
        id: r['id'] as String,
        senderId: r['sender_id'] as String,
        content: r['content'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        isMine: (r['is_mine'] as int) == 1,
        kind: r['kind'] as String? ?? 'text',
        deleted: (r['deleted'] as int) == 1,
        encrypted: (r['encrypted'] as int? ?? 0) == 1,
      );

  /// Escapes LIKE wildcards so searching for "50%" looks for that literal
  /// text rather than matching everything.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

class MessageSearchHit {
  const MessageSearchHit({
    required this.message,
    required this.peerId,
    this.peerName,
  });

  final ChatMessage message;
  final String peerId;

  /// Null for rows cached before the name was stored. Callers show the id
  /// only as a last resort — an unnamed hit is still a real result.
  final String? peerName;
}

/// No-op store used where sqflite has no platform implementation, so the app
/// degrades to "search finds nothing" rather than crashing on open.
class NullMessageStore implements MessageStore {
  const NullMessageStore();

  @override
  Database get _db => throw UnsupportedError('no local database');

  @override
  Future<void> upsertAll(String peerId, List<ChatMessage> messages,
          {String? peerName, bool isSecret = false}) async =>
      debugPrint('[store] skipped: no local database on this platform');

  @override
  Future<List<ChatMessage>> conversation(String peerId, {int limit = 200}) async =>
      const [];

  @override
  Future<List<MessageSearchHit>> search(String query, {int limit = 100}) async =>
      const [];

  @override
  Future<void> deleteConversation(String peerId) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<int> count() async => 0;

  @override
  Future<void> close() async {}
}
