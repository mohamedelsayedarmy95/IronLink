import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A private, per-conversation rule that says "tell me if this appears in a
/// document someone sends me here".
///
/// WHY THIS LIVES ON THE DEVICE
///
/// Encryption is the default for every chat, so the server holds no key and
/// cannot read an attachment. Matching therefore has to happen where the
/// plaintext already is — in this client, after decryption. Keeping the rules
/// here too is not merely convenient: a keyword is the single most sensitive
/// thing this feature touches, because it tells anyone who reads it exactly
/// what its owner is watching for. The server cannot leak what it never
/// receives.
///
/// The rule is invisible to the sender, to group admins, and to every other
/// member (§1.4). That is a property of where the data lives, not of a
/// permission check someone has to remember to write.

/// User-assigned urgency. Governs ordering and framing only — never the
/// confidence threshold required to alert, and never who can see the rule.
enum KeywordPriority {
  low(0),
  medium(1),
  high(2),
  critical(3);

  const KeywordPriority(this.rank);

  /// Higher sorts first in the ticker. Stored as a number rather than relying
  /// on declaration order, so reordering the enum cannot silently reshuffle
  /// every user's alerts.
  final int rank;

  static KeywordPriority fromName(String? name) => KeywordPriority.values
      .firstWhere((p) => p.name == name, orElse: () => KeywordPriority.medium);
}

/// How the text of a rule is compared against extracted document text.
enum KeywordMatchMode {
  /// Whole word, after normalization. "ahmed" matches "Ahmed" but not
  /// "ahmedy".
  exact,

  /// A contiguous run of words. Word boundaries still apply at both ends, so
  /// "final report" does not match "semifinal reporting".
  phrase,

  /// Edit-distance tolerant, for OCR noise. Deliberately the narrowest of the
  /// three in what it will accept — see the Phase 5 safeguards.
  fuzzy,

  /// A user-supplied pattern, validated and bounded before use.
  regex;

  static KeywordMatchMode fromName(String? name) => KeywordMatchMode.values
      .firstWhere((m) => m.name == name, orElse: () => KeywordMatchMode.exact);
}

/// Script context, detected rather than asked for — a user typing an Arabic
/// keyword should not have to also tell us it is Arabic.
enum KeywordLanguage {
  ar,
  en,
  mixed;

  static KeywordLanguage fromName(String? name) => KeywordLanguage.values
      .firstWhere((l) => l.name == name, orElse: () => KeywordLanguage.mixed);

  /// Arabic block, Arabic Supplement, Arabic Extended-A, and the presentation
  /// forms some keyboards and PDF extractors still emit.
  static final _arabic = RegExp(
    r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]',
  );
  static final _latin = RegExp(r'[A-Za-z]');

  static KeywordLanguage detect(String text) {
    final hasArabic = _arabic.hasMatch(text);
    final hasLatin = _latin.hasMatch(text);
    if (hasArabic && hasLatin) return KeywordLanguage.mixed;
    if (hasArabic) return KeywordLanguage.ar;
    if (hasLatin) return KeywordLanguage.en;
    // Digits or symbols only — an invoice number pattern, most likely.
    return KeywordLanguage.mixed;
  }
}

/// Why a rule was rejected. Carried as a value rather than a thrown string so
/// the UI can localize it; the message is for logs and tests.
class KeywordRuleError implements Exception {
  const KeywordRuleError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'KeywordRuleError($code): $message';
}

class KeywordRule {
  const KeywordRule({
    required this.id,
    required this.ownerUserId,
    required this.conversationScope,
    required this.displayRepresentation,
    required this.normalizedRepresentation,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.enabled = true,
    this.matchMode = KeywordMatchMode.exact,
    this.priority = KeywordPriority.medium,
    this.caseSensitive = false,
    this.regexPattern,
    this.category,
    this.maxAlertsPerDay,
    this.notes,
  });

  final String id;
  final String ownerUserId;

  /// The conversation this rule watches. Rules are deliberately not global:
  /// a keyword that matters when talking to a lawyer should not fire on every
  /// photo a family member sends.
  final String conversationScope;

  /// Exactly what the user typed, shown back to them unchanged.
  final String displayRepresentation;

  /// The form actually compared against document text. Computed once at
  /// creation, because normalizing on every match over every page is the
  /// hottest loop in the feature.
  final String normalizedRepresentation;

  final KeywordLanguage language;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool enabled;
  final KeywordMatchMode matchMode;
  final KeywordPriority priority;

  /// Only meaningful for Latin script — Arabic has no case. Left as a flag
  /// rather than inferred, because the case that needs it is a reference code
  /// like "INV-4471" where the user knows what they mean.
  final bool caseSensitive;

  /// Non-null only when [matchMode] is [KeywordMatchMode.regex]. Validated by
  /// [validateRegex] before it is ever compiled against document text.
  final String? regexPattern;

  final String? category;

  /// Soft cap against alert fatigue from a broad rule. Excess matches are
  /// still recorded in history; they simply stop interrupting.
  final int? maxAlertsPerDay;

  final String? notes;

  static const maxKeywordLength = 128;
  static const minKeywordLength = 2;
  static const maxRegexLength = 200;
  static const maxNotesLength = 500;
  static const maxCategoryLength = 40;

  /// Builds a validated rule, or throws [KeywordRuleError].
  ///
  /// [normalize] is injected rather than imported so this file stays free of
  /// the OCR layer: the domain should not depend on the text pipeline, and the
  /// tests should not need it.
  factory KeywordRule.create({
    required String ownerUserId,
    required String conversationScope,
    required String displayRepresentation,
    required String Function(String) normalize,
    required DateTime now,
    bool enabled = true,
    KeywordMatchMode matchMode = KeywordMatchMode.exact,
    KeywordPriority priority = KeywordPriority.medium,
    bool caseSensitive = false,
    String? regexPattern,
    String? category,
    int? maxAlertsPerDay,
    String? notes,
    String? idOverride,
  }) {
    final display = displayRepresentation.trim();
    if (display.length < minKeywordLength) {
      throw const KeywordRuleError(
        'keyword_too_short',
        'A keyword shorter than two characters matches almost every document.',
      );
    }
    if (display.length > maxKeywordLength) {
      throw const KeywordRuleError(
        'keyword_too_long',
        'Keyword exceeds the maximum length.',
      );
    }
    if (category != null && category.length > maxCategoryLength) {
      throw const KeywordRuleError('category_too_long', 'Category too long.');
    }
    if (notes != null && notes.length > maxNotesLength) {
      throw const KeywordRuleError('notes_too_long', 'Note too long.');
    }
    if (maxAlertsPerDay != null && maxAlertsPerDay < 1) {
      throw const KeywordRuleError(
        'invalid_daily_cap',
        'A cap below one would disable the rule; disable it instead.',
      );
    }

    if (matchMode == KeywordMatchMode.regex) {
      if (regexPattern == null || regexPattern.trim().isEmpty) {
        throw const KeywordRuleError(
          'regex_required',
          'Regex match mode needs a pattern.',
        );
      }
      validateRegex(regexPattern);
    } else if (regexPattern != null && regexPattern.trim().isNotEmpty) {
      throw const KeywordRuleError(
        'regex_unexpected',
        'A pattern was supplied for a non-regex match mode.',
      );
    }

    final normalized = normalize(display);
    if (normalized.isEmpty && matchMode != KeywordMatchMode.regex) {
      // Everything the user typed normalized away — punctuation only, or
      // diacritics with no base letters. It would match every document.
      throw const KeywordRuleError(
        'keyword_not_matchable',
        'Nothing in that keyword can be matched against document text.',
      );
    }

    return KeywordRule(
      id: idOverride ??
          deriveId(
            ownerUserId: ownerUserId,
            conversationScope: conversationScope,
            normalized: normalized,
            matchMode: matchMode,
            createdAt: now,
          ),
      ownerUserId: ownerUserId,
      conversationScope: conversationScope,
      displayRepresentation: display,
      normalizedRepresentation: normalized,
      language: KeywordLanguage.detect(display),
      createdAt: now,
      updatedAt: now,
      enabled: enabled,
      matchMode: matchMode,
      priority: priority,
      caseSensitive: caseSensitive,
      regexPattern: regexPattern?.trim(),
      category: category?.trim().isEmpty ?? true ? null : category!.trim(),
      maxAlertsPerDay: maxAlertsPerDay,
      notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
    );
  }

  /// A stable id derived from the rule's identity rather than a random UUID.
  ///
  /// There is no uuid package here, but more usefully: deriving the id means
  /// the same rule recreated on a second device — during a restore, say —
  /// carries the same id, so its alert history and its daily cap survive
  /// instead of splitting in two. The timestamp is included so that deleting a
  /// rule and deliberately recreating it starts a fresh history.
  static String deriveId({
    required String ownerUserId,
    required String conversationScope,
    required String normalized,
    required KeywordMatchMode matchMode,
    required DateTime createdAt,
  }) {
    final material = [
      ownerUserId,
      conversationScope,
      normalized,
      matchMode.name,
      createdAt.toUtc().millisecondsSinceEpoch.toString(),
    ].join(' ');
    return 'kw_${sha256.convert(utf8.encode(material)).toString().substring(0, 24)}';
  }

  /// Rejects patterns that are either unparseable or dangerous to run.
  ///
  /// Dart's RegExp backtracks, so a pattern like `(a+)+$` against a long line
  /// of OCR text takes exponential time and freezes the isolate. That is a
  /// denial of service the user can inflict on themselves by pasting a clever
  /// pattern from the internet, and it happens on the phone rather than on a
  /// server someone is watching.
  ///
  /// The defence is layered: this check rejects the classic nested-quantifier
  /// shapes and caps pattern length, and the matcher separately bounds the
  /// input it will run a pattern over. Neither alone is sufficient — this
  /// heuristic cannot catch every catastrophic pattern, and it is not claimed
  /// to.
  static void validateRegex(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      throw const KeywordRuleError('regex_required', 'Empty pattern.');
    }
    if (trimmed.length > maxRegexLength) {
      throw const KeywordRuleError(
        'regex_too_long',
        'Pattern exceeds the maximum length.',
      );
    }

    // A quantified group whose body itself ends in a quantifier: (a+)+, (a*)*,
    // (\d+)*, (?:x+)+ — the canonical catastrophic-backtracking shapes.
    final nestedQuantifier = RegExp(r'\((?:\?:)?[^()]*[+*][^()]*\)\s*[+*{]');
    if (nestedQuantifier.hasMatch(trimmed)) {
      throw const KeywordRuleError(
        'regex_nested_quantifier',
        'That pattern can take exponential time to evaluate.',
      );
    }

    // Backreferences combined with quantifiers are the other well-known
    // blow-up, and nothing this feature does needs them.
    if (RegExp(r'\\[1-9]').hasMatch(trimmed)) {
      throw const KeywordRuleError(
        'regex_backreference',
        'Backreferences are not permitted in keyword patterns.',
      );
    }

    try {
      RegExp(trimmed);
    } on FormatException catch (e) {
      throw KeywordRuleError('regex_invalid_pattern', e.message);
    }
  }

  KeywordRule copyWith({
    String? displayRepresentation,
    String? normalizedRepresentation,
    KeywordLanguage? language,
    bool? enabled,
    KeywordMatchMode? matchMode,
    KeywordPriority? priority,
    bool? caseSensitive,
    String? regexPattern,
    String? category,
    int? maxAlertsPerDay,
    String? notes,
    required DateTime updatedAt,
    bool clearRegex = false,
    bool clearCategory = false,
    bool clearCap = false,
    bool clearNotes = false,
  }) =>
      KeywordRule(
        id: id,
        ownerUserId: ownerUserId,
        conversationScope: conversationScope,
        displayRepresentation:
            displayRepresentation ?? this.displayRepresentation,
        normalizedRepresentation:
            normalizedRepresentation ?? this.normalizedRepresentation,
        language: language ?? this.language,
        createdAt: createdAt,
        updatedAt: updatedAt,
        enabled: enabled ?? this.enabled,
        matchMode: matchMode ?? this.matchMode,
        priority: priority ?? this.priority,
        caseSensitive: caseSensitive ?? this.caseSensitive,
        regexPattern: clearRegex ? null : (regexPattern ?? this.regexPattern),
        category: clearCategory ? null : (category ?? this.category),
        maxAlertsPerDay:
            clearCap ? null : (maxAlertsPerDay ?? this.maxAlertsPerDay),
        notes: clearNotes ? null : (notes ?? this.notes),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'conversation_scope': conversationScope,
        'display_representation': displayRepresentation,
        'normalized_representation': normalizedRepresentation,
        'language': language.name,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'enabled': enabled ? 1 : 0,
        'match_mode': matchMode.name,
        'priority': priority.name,
        'case_sensitive': caseSensitive ? 1 : 0,
        'regex_pattern': regexPattern,
        'category': category,
        'max_alerts_per_day': maxAlertsPerDay,
        'notes': notes,
      };

  static KeywordRule fromRow(Map<String, Object?> r) => KeywordRule(
        id: r['id'] as String,
        ownerUserId: r['owner_user_id'] as String,
        conversationScope: r['conversation_scope'] as String,
        displayRepresentation: r['display_representation'] as String,
        normalizedRepresentation: r['normalized_representation'] as String,
        language: KeywordLanguage.fromName(r['language'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            r['created_at'] as int,
            isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            r['updated_at'] as int,
            isUtc: true),
        enabled: (r['enabled'] as int? ?? 1) == 1,
        matchMode: KeywordMatchMode.fromName(r['match_mode'] as String?),
        priority: KeywordPriority.fromName(r['priority'] as String?),
        caseSensitive: (r['case_sensitive'] as int? ?? 0) == 1,
        regexPattern: r['regex_pattern'] as String?,
        category: r['category'] as String?,
        maxAlertsPerDay: r['max_alerts_per_day'] as int?,
        notes: r['notes'] as String?,
      );

  @override
  bool operator ==(Object other) => other is KeywordRule && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
