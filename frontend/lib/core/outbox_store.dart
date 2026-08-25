/// Durable queue for frames the socket has not yet had acknowledged.
///
/// WHY A TABLE AND NOT A LIST
///
/// There was already an outbox here, and it fixed something worse: `send` used
/// to be `_channel?.sink.add(...)`, a null-aware call that silently did nothing
/// while disconnected, so a message typed during a WiFi-to-mobile handover drew
/// its optimistic bubble and was simply gone.
///
/// But it was a Dart list. The optimistic bubble is written to sqflite, and the
/// queued frame was not — so killing the app left the user looking at a message
/// in their conversation history that had never been sent and never would be.
/// That is the failure mode SLO 1 calls the worst one, because both sides
/// believe it succeeded: the sender can see the message, and the recipient was
/// never told to expect it.
///
/// WHY REMOVAL IS ON ACKNOWLEDGEMENT, NOT ON WRITE
///
/// The previous queue cleared itself the moment a frame was handed to the
/// socket. Handing bytes to a sink is not delivery. A socket that dies between
/// the write and the server's processing loses the frame with no error on
/// either side, which is precisely the case an outbox exists for.
///
/// So an entry survives until the server acknowledges it by `client_ref`, and
/// is re-sent on every reconnect until then. This is only safe because the
/// server is idempotent on `client_ref` — `alembic/versions/0009_message_
/// idempotency.py` and the dedup in `app/services/message_service.py` — so a
/// re-send of an already-stored message returns the existing row rather than
/// creating a duplicate. Without that, this design would turn every reconnect
/// into a flood of repeats.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One queued frame.
class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.raw,
    required this.clientRef,
    required this.attempts,
  });

  /// Monotonic, and the ordering key. Messages must arrive in the order they
  /// were written, and a timestamp is not enough — two frames sent in the same
  /// millisecond would have no defined order.
  final int seq;

  final String raw;

  /// Null for durable frames that carry no reference. Those cannot be tracked
  /// to an acknowledgement and are removed once written, which is the old
  /// best-effort behaviour and the best available for them.
  final String? clientRef;

  final int attempts;

  Map<String, dynamic> get frame =>
      jsonDecode(raw) as Map<String, dynamic>;
}

abstract class OutboxStore {
  Future<List<OutboxEntry>> load();

  /// Returns the entry as stored, with its assigned sequence.
  Future<OutboxEntry> add(String raw, {String? clientRef});

  Future<void> removeByRef(String clientRef);
  Future<void> removeBySeq(int seq);

  /// Records that the queue was flushed, so a frame the server never
  /// acknowledges cannot be retried forever.
  Future<void> countAttempt(int seq);

  /// Drops the oldest entries beyond [max] and returns their refs.
  ///
  /// The refs are returned rather than discarded because the caller has to
  /// tell the user. The previous queue dropped its oldest silently, which
  /// means a message vanished from the outbox while its bubble stayed in the
  /// conversation looking sent.
  Future<List<String>> trimTo(int max);

  Future<void> clear();
}

class SqfliteOutboxStore implements OutboxStore {
  SqfliteOutboxStore._(this._db);

  final Database _db;

  static const _version = 1;

  /// A separate database file from the message cache.
  ///
  /// They have different lifetimes: the message cache is history and is
  /// cleared when the user signs out, while a corrupted or migrating outbox
  /// must not be able to take the history with it. Separate files also mean a
  /// schema change to one does not open the other.
  static Future<SqfliteOutboxStore> open() async {
    final path = p.join(await getDatabasesPath(), 'ironlink_outbox.db');
    final db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE outbox (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            client_ref TEXT,
            raw TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
        // Acknowledgements arrive keyed by ref, and the lookup happens on
        // every ack — which is every message the user sends.
        await db.execute(
            'CREATE INDEX idx_outbox_ref ON outbox(client_ref)');
      },
    );
    return SqfliteOutboxStore._(db);
  }

  @override
  Future<List<OutboxEntry>> load() async {
    final rows = await _db.query('outbox', orderBy: 'seq ASC');
    return rows.map(_toEntry).toList();
  }

  @override
  Future<OutboxEntry> add(String raw, {String? clientRef}) async {
    final seq = await _db.insert('outbox', {
      'client_ref': clientRef,
      'raw': raw,
      'attempts': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return OutboxEntry(seq: seq, raw: raw, clientRef: clientRef, attempts: 0);
  }

  @override
  Future<void> removeByRef(String clientRef) async {
    await _db.delete('outbox', where: 'client_ref = ?', whereArgs: [clientRef]);
  }

  @override
  Future<void> removeBySeq(int seq) async {
    await _db.delete('outbox', where: 'seq = ?', whereArgs: [seq]);
  }

  @override
  Future<void> countAttempt(int seq) async {
    await _db.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1 WHERE seq = ?', [seq]);
  }

  @override
  Future<List<String>> trimTo(int max) async {
    final excess = await _db.rawQuery('''
      SELECT seq, client_ref FROM outbox
      ORDER BY seq DESC LIMIT -1 OFFSET ?
    ''', [max]);
    if (excess.isEmpty) return const [];

    await _db.delete(
      'outbox',
      where: 'seq IN (${List.filled(excess.length, '?').join(',')})',
      whereArgs: [for (final row in excess) row['seq']],
    );
    return [
      for (final row in excess)
        if (row['client_ref'] != null) row['client_ref'] as String,
    ];
  }

  @override
  Future<void> clear() async => _db.delete('outbox');

  static OutboxEntry _toEntry(Map<String, Object?> row) => OutboxEntry(
        seq: row['seq'] as int,
        raw: row['raw'] as String,
        clientRef: row['client_ref'] as String?,
        attempts: row['attempts'] as int,
      );
}

/// In-memory fallback, used where sqflite has no platform implementation.
///
/// It behaves identically apart from surviving a restart, so the app degrades
/// to the old behaviour on those platforms rather than failing to start.
class InMemoryOutboxStore implements OutboxStore {
  final _entries = <int, OutboxEntry>{};
  int _nextSeq = 1;

  @override
  Future<List<OutboxEntry>> load() async {
    final seqs = _entries.keys.toList()..sort();
    return [for (final seq in seqs) _entries[seq]!];
  }

  @override
  Future<OutboxEntry> add(String raw, {String? clientRef}) async {
    final entry = OutboxEntry(
        seq: _nextSeq++, raw: raw, clientRef: clientRef, attempts: 0);
    _entries[entry.seq] = entry;
    return entry;
  }

  @override
  Future<void> removeByRef(String clientRef) async {
    _entries.removeWhere((_, e) => e.clientRef == clientRef);
  }

  @override
  Future<void> removeBySeq(int seq) async => _entries.remove(seq);

  @override
  Future<void> countAttempt(int seq) async {
    final entry = _entries[seq];
    if (entry == null) return;
    _entries[seq] = OutboxEntry(
      seq: entry.seq,
      raw: entry.raw,
      clientRef: entry.clientRef,
      attempts: entry.attempts + 1,
    );
  }

  @override
  Future<List<String>> trimTo(int max) async {
    final seqs = _entries.keys.toList()..sort();
    if (seqs.length <= max) return const [];

    final dropped = <String>[];
    for (final seq in seqs.take(seqs.length - max)) {
      final ref = _entries.remove(seq)?.clientRef;
      if (ref != null) dropped.add(ref);
    }
    return dropped;
  }

  @override
  Future<void> clear() async => _entries.clear();
}

/// Opens the durable store, falling back to memory rather than failing.
Future<OutboxStore> openOutboxStore() async {
  try {
    return await SqfliteOutboxStore.open();
  } catch (err) {
    debugPrint('[outbox] no durable store on this platform: $err');
    return InMemoryOutboxStore();
  }
}
