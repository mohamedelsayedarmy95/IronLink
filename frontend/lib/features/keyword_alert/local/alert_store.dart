import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/keyword_alert.dart';
import '../domain/keyword_rule.dart';

/// On-device persistence for keyword rules and the alerts they raise.
///
/// WHY A SEPARATE DATABASE FROM THE MESSAGE CACHE
///
/// The message cache is disposable: losing it costs offline reading and local
/// search, both of which rebuild themselves the next time a conversation is
/// opened. This is not disposable. A rule the user wrote and an alert they
/// have not yet answered cannot be rebuilt from anywhere — the server has
/// never seen either — so the two deserve independent schema versions and
/// independent failure. A migration mistake in the message cache should not
/// take someone's watchlist with it.
///
/// WHAT IS DELIBERATELY NOT STORED HERE
///
/// The extracted document text. §4.5 allows the matched fragment and a short
/// window of context, and nothing more. Keeping the full OCR output would
/// build, on the device, exactly the searchable corpus of everyone's documents
/// that this design exists to avoid — and it would outlive the document by 48
/// hours, which the user never agreed to.
class AlertStore {
  AlertStore._(this._db);

  final Database _db;

  static const _fileName = 'ironlink_alerts.db';
  static const _version = 1;

  static Future<AlertStore> open() async {
    final path = '${await getDatabasesPath()}/$_fileName';
    final db = await openDatabase(
      path,
      version: _version,
      onConfigure: (db) async {
        // An alert without its rule is unreadable — it can name a keyword only
        // by pointing at one — so the two are tied together at the database
        // rather than in whichever code path happens to delete a rule.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE keyword_rules (
            id TEXT PRIMARY KEY,
            owner_user_id TEXT NOT NULL,
            conversation_scope TEXT NOT NULL,
            display_representation TEXT NOT NULL,
            normalized_representation TEXT NOT NULL,
            language TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            match_mode TEXT NOT NULL,
            priority TEXT NOT NULL,
            case_sensitive INTEGER NOT NULL DEFAULT 0,
            regex_pattern TEXT,
            category TEXT,
            max_alerts_per_day INTEGER,
            notes TEXT
          )
        ''');
        // The hot read is "the enabled rules for the conversation I just
        // received a document in", so the index matches that shape.
        await db.execute(
          'CREATE INDEX idx_rules_scope '
          'ON keyword_rules (conversation_scope, enabled)',
        );
        // The same keyword twice in one conversation is a mistake, not a
        // preference: it would raise two identical alerts for every document.
        await db.execute(
          'CREATE UNIQUE INDEX idx_rules_unique '
          'ON keyword_rules (conversation_scope, normalized_representation, '
          'match_mode)',
        );

        await db.execute('''
          CREATE TABLE keyword_alerts (
            -- Derived from the alert's identity, not random. This column is
            -- the idempotency guarantee: reconnect, retry, duplicate push,
            -- restart and re-upload all derive the same id, so the second
            -- write is a primary-key conflict rather than a second alert.
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            attachment_id TEXT NOT NULL,
            recipient_user_id TEXT NOT NULL,
            keyword_rule_id TEXT NOT NULL
              REFERENCES keyword_rules (id) ON DELETE CASCADE,
            source_document_hash TEXT NOT NULL,
            processing_version INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL,
            priority_level TEXT NOT NULL,
            match_type TEXT,
            confidence REAL,
            -- The fragment of the document that matched, and a short window
            -- around it. Never the full extracted text (§4.5).
            matched_text TEXT,
            context_text TEXT,
            document_page INTEGER,
            document_region TEXT,
            processing_source TEXT NOT NULL DEFAULT 'local',
            retry_count INTEGER NOT NULL DEFAULT 0,
            detected_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            acknowledged_at INTEGER,
            dismissed_at INTEGER,
            failure_reason TEXT,
            suppressed_by_cap INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_alerts_history ON keyword_alerts (detected_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_alerts_status ON keyword_alerts (status, detected_at DESC)',
        );
        // Counting today's alerts for one rule, for the daily cap.
        await db.execute(
          'CREATE INDEX idx_alerts_rule_time '
          'ON keyword_alerts (keyword_rule_id, detected_at)',
        );
        await db.execute(
          'CREATE INDEX idx_alerts_expiry ON keyword_alerts (expires_at)',
        );
      },
    );
    return AlertStore._(db);
  }

  // ── Rules ──────────────────────────────────────────────────────────────────

  /// Inserts or updates a rule.
  ///
  /// Replace rather than fail on the unique index, so editing a rule into the
  /// shape of one that already exists resolves to a single rule instead of an
  /// error the user cannot act on.
  Future<void> saveRule(KeywordRule rule) async {
    await _db.insert(
      'keyword_rules',
      rule.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<KeywordRule>> rulesFor(
    String conversationScope, {
    bool onlyEnabled = false,
  }) async {
    final rows = await _db.query(
      'keyword_rules',
      where: onlyEnabled
          ? 'conversation_scope = ? AND enabled = 1'
          : 'conversation_scope = ?',
      whereArgs: [conversationScope],
      orderBy: 'created_at DESC',
    );
    return rows.map(KeywordRule.fromRow).toList();
  }

  Future<KeywordRule?> rule(String id) async {
    final rows = await _db.query(
      'keyword_rules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : KeywordRule.fromRow(rows.first);
  }

  /// Deletes a rule and, by cascade, every alert it raised.
  ///
  /// The cascade is the point. §1.3 promises deletion takes effect
  /// immediately; an alert that outlived its rule would still be sitting in
  /// history naming a keyword the user believes they erased.
  Future<void> deleteRule(String id) async {
    await _db.delete('keyword_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> ruleCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM keyword_rules'),
      ) ??
      0;

  // ── Alerts ─────────────────────────────────────────────────────────────────

  /// Records an alert, or returns the one already recorded for this document
  /// and rule.
  ///
  /// This is where §4.3 is enforced, and it returns the *stored* alert rather
  /// than a boolean so the caller cannot accidentally go on to present the
  /// duplicate it just failed to insert.
  Future<KeywordAlert> record(KeywordAlert alert) async {
    final inserted = await _db.insert(
      'keyword_alerts',
      alert.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return alert;

    final existing = await byId(alert.id);
    // The row can only be missing if it was deleted between the two
    // statements — a rule deleted mid-processing. Returning the alert the
    // caller built keeps the pipeline honest without resurrecting the row.
    return existing ?? alert;
  }

  Future<KeywordAlert?> byId(String id) async {
    final rows = await _db.query(
      'keyword_alerts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : KeywordAlert.fromRow(rows.first);
  }

  Future<void> save(KeywordAlert alert) async {
    await _db.update(
      'keyword_alerts',
      alert.toRow(),
      where: 'id = ?',
      whereArgs: [alert.id],
    );
  }

  /// Applies a state transition and persists it.
  ///
  /// Reads the alert back rather than trusting a caller-held copy: two
  /// surfaces can act on the same alert at once — a ticker tap and a push
  /// notification — and the transition has to be judged against what is
  /// actually stored.
  Future<KeywordAlert?> transition(
    String alertId,
    AlertStatus next, {
    required DateTime now,
    String? failureReason,
    bool incrementRetry = false,
  }) async {
    final current = await byId(alertId);
    if (current == null) return null;
    final updated = current.transitionTo(
      next,
      now: now,
      failureReason: failureReason,
      incrementRetry: incrementRetry,
    );
    await save(updated);
    return updated;
  }

  /// Alerts the user still owes an answer to, best first.
  Future<List<KeywordAlert>> outstanding({DateTime? now, int limit = 100}) async {
    final at = now ?? DateTime.now().toUtc();
    await sweepExpired(at);
    final rows = await _db.query(
      'keyword_alerts',
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        AlertStatus.alertCreated.name,
        AlertStatus.alertPresented.name,
        AlertStatus.documentOpened.name,
      ],
      orderBy: 'detected_at DESC',
      limit: limit,
    );
    return rows.map(KeywordAlert.fromRow).toList()
      ..sort(compareAlertsForPresentation);
  }

  /// Chronological history (§4.5), newest first.
  Future<List<KeywordAlert>> history({
    String? conversationId,
    DateTime? now,
    int limit = 200,
  }) async {
    await sweepExpired(now ?? DateTime.now().toUtc());
    final rows = await _db.query(
      'keyword_alerts',
      where: conversationId == null ? null : 'conversation_id = ?',
      whereArgs: conversationId == null ? null : [conversationId],
      orderBy: 'detected_at DESC',
      limit: limit,
    );
    return rows.map(KeywordAlert.fromRow).toList();
  }

  /// How many alerts this rule has raised in the last 24 hours, for the soft
  /// daily cap.
  ///
  /// A rolling window rather than a calendar day: a cap that resets at
  /// midnight lets a noisy rule fire its whole allowance twice in an hour.
  /// Suppressed alerts count — otherwise a capped rule would re-open its own
  /// allowance every time it was suppressed.
  Future<int> alertsInLastDay(String ruleId, DateTime now) async {
    final since = now.toUtc().subtract(const Duration(hours: 24));
    return Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM keyword_alerts '
          'WHERE keyword_rule_id = ? AND detected_at >= ?',
          [ruleId, since.millisecondsSinceEpoch],
        )) ??
        0;
  }

  /// Whether this exact document has already been processed under this
  /// pipeline version for this rule.
  ///
  /// Lets the pipeline skip the expensive part — extraction — rather than
  /// doing the work and discarding the result at the insert (§8.2, "only once
  /// per processing version").
  Future<bool> alreadyProcessed({
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String keywordRuleId,
    required String sourceDocumentHash,
    required int processingVersion,
  }) async {
    final id = KeywordAlert.deriveId(
      conversationId: conversationId,
      messageId: messageId,
      attachmentId: attachmentId,
      keywordRuleId: keywordRuleId,
      sourceDocumentHash: sourceDocumentHash,
      processingVersion: processingVersion,
    );
    return await byId(id) != null;
  }

  /// Expires everything past its retention window, and deletes what has been
  /// expired long enough that keeping it serves no one.
  ///
  /// Two stages on purpose: an alert that expires while the user was away
  /// should still be visible in history as "expired, you missed this" rather
  /// than vanishing without trace. A week later, it goes.
  Future<int> sweepExpired(DateTime now) async {
    final at = now.toUtc();
    final expired = await _db.update(
      'keyword_alerts',
      {'status': AlertStatus.expired.name, 'updated_at': at.millisecondsSinceEpoch},
      where: 'expires_at < ? AND status NOT IN (?, ?, ?, ?, ?)',
      whereArgs: [
        at.millisecondsSinceEpoch,
        AlertStatus.expired.name,
        AlertStatus.acknowledged.name,
        AlertStatus.dismissed.name,
        AlertStatus.noMatch.name,
        AlertStatus.unsupportedDocument.name,
      ],
    );
    await _db.delete(
      'keyword_alerts',
      where: 'expires_at < ?',
      whereArgs: [
        at.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      ],
    );
    return expired;
  }

  Future<int> alertCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM keyword_alerts'),
      ) ??
      0;

  /// Wipes everything. Called on sign-out, alongside the message cache — a
  /// handed-on device must not keep the previous user's watchlist.
  Future<void> clear() async {
    await _db.delete('keyword_alerts');
    await _db.delete('keyword_rules');
  }

  Future<void> close() => _db.close();
}

/// Used where sqflite has no platform implementation, so the app degrades to
/// "no keyword alerts" rather than failing to start.
class NullAlertStore implements AlertStore {
  const NullAlertStore();

  @override
  Database get _db => throw UnsupportedError('no local database');

  @override
  Future<void> saveRule(KeywordRule rule) async =>
      debugPrint('[alerts] skipped: no local database on this platform');

  @override
  Future<List<KeywordRule>> rulesFor(String conversationScope,
          {bool onlyEnabled = false}) async =>
      const [];

  @override
  Future<KeywordRule?> rule(String id) async => null;

  @override
  Future<void> deleteRule(String id) async {}

  @override
  Future<int> ruleCount() async => 0;

  @override
  Future<KeywordAlert> record(KeywordAlert alert) async => alert;

  @override
  Future<KeywordAlert?> byId(String id) async => null;

  @override
  Future<void> save(KeywordAlert alert) async {}

  @override
  Future<KeywordAlert?> transition(String alertId, AlertStatus next,
          {required DateTime now,
          String? failureReason,
          bool incrementRetry = false}) async =>
      null;

  @override
  Future<List<KeywordAlert>> outstanding({DateTime? now, int limit = 100}) async =>
      const [];

  @override
  Future<List<KeywordAlert>> history(
          {String? conversationId, DateTime? now, int limit = 200}) async =>
      const [];

  @override
  Future<int> alertsInLastDay(String ruleId, DateTime now) async => 0;

  @override
  Future<bool> alreadyProcessed({
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String keywordRuleId,
    required String sourceDocumentHash,
    required int processingVersion,
  }) async =>
      false;

  @override
  Future<int> sweepExpired(DateTime now) async => 0;

  @override
  Future<int> alertCount() async => 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}
