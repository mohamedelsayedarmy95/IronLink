import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';

/// A keyword rule is user-supplied input that this app then runs against every
/// document that arrives. Validation is therefore not tidiness — it is the
/// boundary between "the user configured a filter" and "the user handed the
/// phone a way to lock itself up".
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  String normalize(String s) => s.trim().toLowerCase();

  KeywordRule make(
    String keyword, {
    KeywordMatchMode mode = KeywordMatchMode.exact,
    String? pattern,
    int? cap,
    String? category,
    String? notes,
  }) =>
      KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: keyword,
        normalize: normalize,
        now: t0,
        matchMode: mode,
        regexPattern: pattern,
        maxAlertsPerDay: cap,
        category: category,
        notes: notes,
      );

  group('what a rule keeps', () {
    test('shows back exactly what the user typed', () {
      final rule = make('  أحمد  ');
      expect(rule.displayRepresentation, 'أحمد');
      expect(rule.normalizedRepresentation, 'أحمد');
    });

    test('normalizes once, at creation, not on every page', () {
      final rule = make('  Contract  ');
      expect(rule.normalizedRepresentation, 'contract');
    });

    test('defaults to medium priority and enabled', () {
      final rule = make('contract');
      expect(rule.priority, KeywordPriority.medium);
      expect(rule.enabled, isTrue);
      expect(rule.matchMode, KeywordMatchMode.exact);
    });
  });

  group('language detection', () {
    test('recognises Arabic without being told', () {
      expect(make('أحمد').language, KeywordLanguage.ar);
    });

    test('recognises Latin script', () {
      expect(make('contract').language, KeywordLanguage.en);
    });

    test('recognises a mixture', () {
      expect(make('عقد Contract').language, KeywordLanguage.mixed);
    });

    test('handles Arabic presentation forms some PDF extractors emit', () {
      // U+FEA0 etc. — the ligature block, not the standard Arabic block.
      expect(KeywordLanguage.detect('ﺠﺍ'), KeywordLanguage.ar);
    });
  });

  group('rejections', () {
    test('a one-character keyword matches almost every document', () {
      expect(() => make('a'), throwsA(isA<KeywordRuleError>()));
    });

    test('a keyword that normalizes to nothing is refused', () {
      // Punctuation only — it would match everything, and the user would have
      // no way to understand why.
      expect(
        () => KeywordRule.create(
          ownerUserId: 'u1',
          conversationScope: 'c1',
          displayRepresentation: '...',
          normalize: (_) => '',
          now: t0,
        ),
        throwsA(isA<KeywordRuleError>()),
      );
    });

    test('an over-long keyword is refused', () {
      expect(() => make('x' * 200), throwsA(isA<KeywordRuleError>()));
    });

    test('a cap below one would silently disable the rule', () {
      expect(() => make('contract', cap: 0), throwsA(isA<KeywordRuleError>()));
    });

    test('a pattern supplied for a non-regex mode is refused, not ignored', () {
      // Silently dropping it would leave the user believing a pattern is
      // active when nothing is using it.
      expect(
        () => make('contract', pattern: r'INV-\d{6}'),
        throwsA(isA<KeywordRuleError>()),
      );
    });

    test('regex mode without a pattern is refused', () {
      expect(
        () => make('invoice', mode: KeywordMatchMode.regex),
        throwsA(isA<KeywordRuleError>()),
      );
    });
  });

  group('regex sandboxing', () {
    /// Asserts the *specific* rejection reason rather than "some error".
    ///
    /// Written this way after the loose version passed against a keyword that
    /// was rejected for being one character long — the pattern was never
    /// examined at all, and the test would have gone on passing with the
    /// sandbox deleted.
    void expectRejection(String pattern, String code) {
      try {
        make('invoice', mode: KeywordMatchMode.regex, pattern: pattern);
        fail('expected $pattern to be rejected');
      } on KeywordRuleError catch (e) {
        expect(e.code, code, reason: pattern);
      }
    }

    test('accepts an ordinary reference-number pattern', () {
      final rule = make(
        'invoice',
        mode: KeywordMatchMode.regex,
        pattern: r'INV-\d{6}',
      );
      expect(rule.regexPattern, r'INV-\d{6}');
    });

    test('rejects nested quantifiers', () {
      // (a+)+ against a long line of OCR text backtracks exponentially and
      // freezes the isolate — a denial of service the user inflicts on
      // themselves by pasting a pattern from the internet.
      for (final pattern in [r'(a+)+$', r'(a*)*b', r'(\d+)*', r'(?:x+)+']) {
        expectRejection(pattern, 'regex_nested_quantifier');
      }
    });

    test('rejects backreferences', () {
      expectRejection(r'(\w)\1+', 'regex_backreference');
    });

    test('rejects an unparseable pattern', () {
      expectRejection(r'INV-(\d{6}', 'regex_invalid_pattern');
    });

    test('rejects an over-long pattern', () {
      expectRejection('a' * 300, 'regex_too_long');
    });
  });

  group('identity', () {
    test('the same rule recreated during a restore keeps its id', () {
      // Otherwise its alert history and its daily cap split in two.
      expect(make('contract').id, make('contract').id);
    });

    test('the same keyword in another conversation is a different rule', () {
      final a = make('contract');
      final b = KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c2',
        displayRepresentation: 'contract',
        normalize: normalize,
        now: t0,
      );
      expect(a.id, isNot(b.id));
    });

    test('deliberately recreating a deleted rule starts a fresh history', () {
      final later = KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: 'contract',
        normalize: normalize,
        now: t0.add(const Duration(days: 1)),
      );
      expect(make('contract').id, isNot(later.id));
    });
  });

  group('round-trip', () {
    test('every attribute survives storage', () {
      final rule = KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: 'أحمد',
        normalize: normalize,
        now: t0,
        matchMode: KeywordMatchMode.phrase,
        priority: KeywordPriority.critical,
        caseSensitive: true,
        category: 'Legal',
        maxAlertsPerDay: 10,
        notes: 'Q3 audit case',
      );
      final back = KeywordRule.fromRow(rule.toRow());

      expect(back.id, rule.id);
      expect(back.displayRepresentation, 'أحمد');
      expect(back.language, KeywordLanguage.ar);
      expect(back.matchMode, KeywordMatchMode.phrase);
      expect(back.priority, KeywordPriority.critical);
      expect(back.caseSensitive, isTrue);
      expect(back.category, 'Legal');
      expect(back.maxAlertsPerDay, 10);
      expect(back.notes, 'Q3 audit case');
    });

    test('an unknown enum value from a newer build degrades to the default',
        () {
      // A rule written by a later version must not crash an older one.
      final row = make('contract').toRow()..['priority'] = 'apocalyptic';
      expect(KeywordRule.fromRow(row).priority, KeywordPriority.medium);
    });
  });
}
