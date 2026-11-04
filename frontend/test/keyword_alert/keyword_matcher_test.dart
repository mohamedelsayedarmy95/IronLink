import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_alert.dart';
import 'package:ironlink/features/keyword_alert/domain/keyword_rule.dart';
import 'package:ironlink/features/keyword_alert/matching/keyword_matcher.dart';
import 'package:ironlink/features/keyword_alert/ocr/extracted_document.dart';
import 'package:ironlink/features/keyword_alert/text/text_normalizer.dart';

/// The spec states one rule in capitals: never `if OCRText.contains(keyword)`.
/// It is wrong in both directions at once — it finds "art" inside "contract"
/// and misses "أحمد" spelled with a different alef. Both halves are pinned
/// here, along with the scoring that decides whether a hit is worth
/// interrupting anyone over.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);
  const matcher = KeywordMatcher();
  const normalizer = TextNormalizer();

  KeywordRule rule(
    String keyword, {
    KeywordMatchMode mode = KeywordMatchMode.exact,
    String? pattern,
    bool caseSensitive = false,
  }) =>
      KeywordRule.create(
        ownerUserId: 'u1',
        conversationScope: 'c1',
        displayRepresentation: keyword,
        normalize: (s) =>
            TextNormalizer(caseSensitive: caseSensitive).normalizeToString(s),
        now: t0,
        matchMode: mode,
        regexPattern: pattern,
        caseSensitive: caseSensitive,
      );

  /// A page whose every word the engine read with the same confidence.
  ExtractedPage page(
    String text, {
    double confidence = 1.0,
    PageQuality quality = PageQuality.perfect,
    PageTextSource source = PageTextSource.nativeTextLayer,
    int pageNumber = 1,
  }) {
    final words = <RecognizedWord>[];
    final pattern = RegExp(r'\S+');
    for (final m in pattern.allMatches(text)) {
      words.add(RecognizedWord(
        start: m.start,
        end: m.end,
        confidence: confidence,
        region: DocumentRegion(
          left: m.start / text.length,
          top: 0.1,
          width: (m.end - m.start) / text.length,
          height: 0.05,
        ),
      ));
    }
    return ExtractedPage(
      pageNumber: pageNumber,
      text: text,
      words: words,
      source: source,
      quality: quality,
    );
  }

  ExtractedDocument doc(List<ExtractedPage> pages) =>
      ExtractedDocument(pages: pages, engine: 'test');

  List<ScoredMatch> run(
    List<KeywordRule> rules,
    List<ExtractedPage> pages, {
    KeywordMatcher? using,
  }) =>
      (using ?? matcher).match(rules: rules, document: doc(pages));

  group('word boundaries', () {
    test('does not find a keyword inside a longer word', () {
      // The defect the spec bans in capitals: "art" is inside "contract".
      expect(run([rule('art')], [page('the contract is attached')]), isEmpty);
    });

    test('does not match a prefix', () {
      expect(run([rule('contra')], [page('the contract is attached')]), isEmpty);
    });

    test('matches the whole word', () {
      final hits = run([rule('contract')], [page('the contract is attached')]);
      expect(hits, hasLength(1));
      expect(hits.single.matchedText, 'contract');
    });

    test('matches a word touching punctuation', () {
      final hits = run([rule('contract')], [page('re: contract, signed.')]);
      expect(hits.single.matchedText, 'contract');
    });

    test('finds every occurrence', () {
      final hits = run([rule('contract')], [page('contract and contract')]);
      expect(hits, hasLength(2));
    });
  });

  group('Arabic', () {
    test('finds a keyword written with a different alef', () {
      // The other half of the old defect: identical to a reader, different
      // codepoints, and previously no match at all.
      final hits = run([rule('أحمد')], [page('المرفق باسم احمد الشريف')]);
      expect(hits, hasLength(1));
      expect(hits.single.matchedText, 'احمد');
    });

    test('finds a keyword written with diacritics in the document', () {
      final hits = run([rule('محمد')], [page('وقّع مُحَمَّد على التقرير')]);
      expect(hits, hasLength(1));
      expect(hits.single.matchedText, 'مُحَمَّد');
    });

    test('finds a keyword the document shaped as presentation forms', () {
      final hits = run([rule('ملن')], [page('ﻣﻠﻨ here')]);
      expect(hits, hasLength(1));
    });

    test('matches an Arabic-Indic number against a Latin keyword', () {
      final hits = run([rule('4471')], [page('رقم الفاتورة ٤٤٧١ مرفق')]);
      expect(hits, hasLength(1));
      expect(hits.single.matchedText, '٤٤٧١');
    });

    test('does not confuse two different Arabic names', () {
      expect(run([rule('حسن')], [page('التقرير باسم خسن')]), isEmpty);
    });

    test('quotes the document, not the rule', () {
      // §4.4: the alert should read like the document, not like the settings
      // screen.
      final hits = run([rule('أحمد')], [page('باسم احمد الشريف')]);
      expect(hits.single.matchedText, 'احمد');
      expect(hits.single.rule.displayRepresentation, 'أحمد');
    });
  });

  group('phrases', () {
    test('matches a contiguous run of words', () {
      final hits = run(
        [rule('final report', mode: KeywordMatchMode.phrase)],
        [page('please see the final report attached')],
      );
      expect(hits, hasLength(1));
      expect(hits.single.matchType, MatchType.phrase);
    });

    test('does not match the words out of order', () {
      expect(
        run(
          [rule('final report', mode: KeywordMatchMode.phrase)],
          [page('the report is not final')],
        ),
        isEmpty,
      );
    });

    test('does not match across a gap', () {
      expect(
        run(
          [rule('final report', mode: KeywordMatchMode.phrase)],
          [page('the final draft report')],
        ),
        isEmpty,
      );
    });

    test('keeps stop words inside a phrase', () {
      // "in the matter of" depends on them; excluding them would match
      // "matter of" anywhere and defeat the point of a phrase.
      final hits = run(
        [rule('in the matter of', mode: KeywordMatchMode.phrase)],
        [page('filed in the matter of Kassem')],
      );
      expect(hits, hasLength(1));
    });

    test('does not match a phrase whose stop words differ', () {
      expect(
        run(
          [rule('in the matter of', mode: KeywordMatchMode.phrase)],
          [page('filed in a matter of days')],
        ),
        isEmpty,
      );
    });
  });

  group('stop words as whole rules', () {
    test('a rule that is only a connector never fires', () {
      // It would match essentially every document ever sent, which is alert
      // fatigue rather than a filter.
      expect(run([rule('the')], [page('the contract')]), isEmpty);
      expect(run([rule('في')], [page('في التقرير')]), isEmpty);
    });
  });

  group('regex rules', () {
    test('finds a reference-number pattern', () {
      final hits = run(
        [rule('invoice', mode: KeywordMatchMode.regex, pattern: r'INV-\d{6}')],
        [page('please pay INV-004471 by Friday')],
      );
      expect(hits, hasLength(1));
      expect(hits.single.matchedText, 'INV-004471');
      expect(hits.single.matchType, MatchType.regex);
    });

    test('runs against the source, so punctuation and case still mean what they said', () {
      // Normalizing first would turn "INV-004471" into "inv 004471" and
      // silently change what the user's pattern matches.
      final hits = run(
        [rule('invoice', mode: KeywordMatchMode.regex, pattern: r'INV-\d{6}')],
        [page('inv 004471')],
      );
      expect(hits, isEmpty);
    });

    test('a zero-width match is not a hit', () {
      expect(
        run(
          [rule('anything', mode: KeywordMatchMode.regex, pattern: r'x*')],
          [page('nothing here')],
        ),
        isEmpty,
      );
    });

    test('regex input is bounded', () {
      // The second half of the defence the rule validator starts: no
      // heuristic catches every catastrophic pattern, so nothing runs over
      // unbounded input.
      const bounded = KeywordMatcher(maxRegexInputLength: 20);
      final hits = run(
        [rule('late', mode: KeywordMatchMode.regex, pattern: 'needle')],
        [page('${'x' * 100} needle')],
        using: bounded,
      );
      expect(hits, isEmpty);
    });
  });

  group('case sensitivity', () {
    test('is off by default', () {
      expect(run([rule('contract')], [page('CONTRACT attached')]), hasLength(1));
    });

    test('can be demanded for a code', () {
      final sensitive = rule('INV', caseSensitive: true);
      expect(run([sensitive], [page('INV attached')]), hasLength(1));
      expect(run([sensitive], [page('inv attached')]), isEmpty);
    });
  });

  group('confidence (§2.5)', () {
    test('a clean exact match on a text layer scores HIGH', () {
      final hits = run([rule('contract')], [page('the contract is attached')]);
      expect(hits.single.breakdown.level, ConfidenceLevel.high);
    });

    test('the engine\'s own uncertainty carries through', () {
      final hits = run(
        [rule('contract')],
        [page('the contract is attached', confidence: 0.55)],
      );
      expect(hits.single.confidence, lessThan(ConfidenceThresholds.high));
      expect(hits.single.breakdown.engineConfidence, 0.55);
    });

    test('a poor scan is down-weighted', () {
      final clean = run([rule('contract')], [page('the contract is here')]);
      final blurred = run(
        [rule('contract')],
        [
          page('the contract is here',
              quality: const PageQuality(sharpness: 0.3))
        ],
      );
      expect(blurred.single.confidence, lessThan(clean.single.confidence));
    });

    test('page quality can only reduce, never promote', () {
      final hits = run(
        [rule('contract')],
        [page('the contract is here', confidence: 0.6)],
      );
      expect(hits.single.breakdown.qualityFactor, lessThanOrEqualTo(1.0));
      expect(hits.single.confidence, lessThanOrEqualTo(0.6));
    });

    test('the weakest word in the span sets the engine confidence', () {
      // A keyword is only as reliable as its least certain character;
      // averaging would hide exactly the misread worth catching.
      const text = 'the contract is attached';
      final start = text.indexOf('contract');
      final custom = ExtractedPage(
        pageNumber: 1,
        text: text,
        source: PageTextSource.opticalRecognition,
        words: [
          const RecognizedWord(start: 0, end: 3, confidence: 0.99),
          RecognizedWord(start: start, end: start + 8, confidence: 0.40),
          RecognizedWord(start: start + 9, end: start + 11, confidence: 0.99),
        ],
      );
      final hits = run([rule('contract')], [custom]);
      expect(hits.single.breakdown.engineConfidence, 0.40);
    });

    test('a match amid noise scores below the same match amid clean text', () {
      List<ScoredMatch> withNeighbourConfidence(double c) {
        const text = 'aaa contract bbb';
        final start = text.indexOf('contract');
        return run([
          rule('contract')
        ], [
          ExtractedPage(
            pageNumber: 1,
            text: text,
            source: PageTextSource.opticalRecognition,
            words: [
              RecognizedWord(start: 0, end: 3, confidence: c),
              RecognizedWord(start: start, end: start + 8, confidence: 0.95),
              RecognizedWord(start: start + 9, end: text.length, confidence: c),
            ],
          )
        ]);
      }

      expect(
        withNeighbourConfidence(0.2).single.confidence,
        lessThan(withNeighbourConfidence(0.99).single.confidence),
      );
    });

    test('good context cannot rescue a badly read keyword', () {
      // Context is a modifier, never a trigger (§2.5).
      const text = 'clean clean contract clean clean';
      final start = text.indexOf('contract');
      final hits = run([
        rule('contract')
      ], [
        ExtractedPage(
          pageNumber: 1,
          text: text,
          source: PageTextSource.opticalRecognition,
          words: [
            const RecognizedWord(start: 0, end: 11, confidence: 1.0),
            RecognizedWord(start: start, end: start + 8, confidence: 0.30),
            RecognizedWord(start: start + 9, end: text.length, confidence: 1.0),
          ],
        )
      ]);
      expect(hits.single.breakdown.level, ConfidenceLevel.low);
    });

    test('a low-scoring hit is relabelled LOW-CONFIDENCE', () {
      final hits = run(
        [rule('contract')],
        [page('the contract is here', confidence: 0.2)],
      );
      expect(hits.single.matchType, MatchType.lowConfidence);
    });

    test('keyword length breaks ties without deciding anything', () {
      final short = run([rule('acme')], [page('the acme file', confidence: 0.9)]);
      final long =
          run([rule('acmecorporation')], [page('the acmecorporation file', confidence: 0.9)]);
      expect(long.single.confidence, greaterThan(short.single.confidence));
      // …but only just. Length is evidence about the rule, not the document.
      expect(long.single.confidence - short.single.confidence, lessThan(0.05));
    });
  });

  group('fuzzy matching (EXPERIMENTAL, off by default)', () {
    test('is off unless explicitly enabled', () {
      expect(run([rule('contract')], [page('the coniract is here')]), isEmpty);
    });

    test('tolerates a single OCR substitution when enabled', () {
      const fuzzy = KeywordMatcher(fuzzyEnabled: true);
      final hits = run([rule('contract')], [page('the coniract is here')],
          using: fuzzy);
      expect(hits, hasLength(1));
      expect(hits.single.matchType, MatchType.fuzzy);
    });

    test('scores fuzzy below exact', () {
      const fuzzy = KeywordMatcher(fuzzyEnabled: true);
      final exact =
          run([rule('contract')], [page('the contract is here')], using: fuzzy);
      final approx =
          run([rule('contract')], [page('the coniract is here')], using: fuzzy);
      expect(approx.single.confidence, lessThan(exact.single.confidence));
    });

    test('refuses to guess at short words', () {
      // "cat" and "car" are one edit apart and unrelated. The length floor is
      // what separates that from "contract" misread as "coniract".
      const fuzzy = KeywordMatcher(fuzzyEnabled: true);
      expect(run([rule('cat')], [page('the car is here')], using: fuzzy), isEmpty);
    });

    test('does not accept two substitutions', () {
      const fuzzy = KeywordMatcher(fuzzyEnabled: true);
      expect(
        run([rule('contract')], [page('the conirect is here')], using: fuzzy),
        isEmpty,
      );
    });
  });

  group('context extraction (§4.4)', () {
    test('quotes surrounding text, never just the keyword', () {
      final hits = run(
        [rule('contract')],
        [page('Please countersign the contract before Friday and return it')],
      );
      expect(hits.single.contextText, contains('contract'));
      expect(hits.single.contextText.length, greaterThan('contract'.length));
    });

    test('marks where it cut the document', () {
      final hits = run(
        [rule('contract')],
        [page('${'padding word ' * 20}contract${' trailing word' * 20}')],
      );
      expect(hits.single.contextText, startsWith('…'));
      expect(hits.single.contextText, endsWith('…'));
    });

    test('is capped, so alerts cannot reconstruct the document', () {
      const narrow = KeywordMatcher(contextRadius: 500, maxContextLength: 60);
      final hits = run(
        [rule('contract')],
        [page('${'word ' * 200}contract${' word' * 200}')],
        using: narrow,
      );
      expect(hits.single.contextText.length, lessThanOrEqualTo(62));
    });

    test('does not begin mid-word', () {
      final hits = run(
        [rule('contract')],
        [page('${'x' * 30}alongprecedingword the contract here')],
      );
      final snippet = hits.single.contextText.replaceAll('…', '').trim();
      expect(snippet.split(' ').first, isNot(matches(r'^\w{1,3}$')));
    });

    test('collapses newlines so the snippet reads as one line', () {
      final hits = run([rule('contract')], [page('see the\n\ncontract\nattached')]);
      expect(hits.single.contextText, isNot(contains('\n')));
    });
  });

  group('location', () {
    test('records the page a match was found on', () {
      final hits = run(
        [rule('contract')],
        [page('nothing here'), page('the contract', pageNumber: 2)],
      );
      expect(hits.single.pageNumber, 2);
    });

    test('records a bounding box when the engine reported one', () {
      final hits = run([rule('contract')], [page('the contract is here')]);
      expect(hits.single.region, isNotNull);
    });

    test('reports no box when the engine gave no geometry', () {
      final hits = run([
        rule('contract')
      ], [
        const ExtractedPage(
          pageNumber: 1,
          text: 'the contract is here',
          words: [],
          source: PageTextSource.nativeTextLayer,
        )
      ]);
      expect(hits.single.region, isNull);
    });
  });

  group('deduplication', () {
    test('one span is one finding, at its strongest reading', () {
      const fuzzy = KeywordMatcher(fuzzyEnabled: true);
      final hits =
          run([rule('contract')], [page('the contract is here')], using: fuzzy);
      expect(hits, hasLength(1));
      expect(hits.single.matchType, isNot(MatchType.fuzzy));
    });

    test('two rules hitting the same span are two findings', () {
      // They belong to different rules and may have different priorities.
      final hits = run(
        [rule('contract'), rule('contract', mode: KeywordMatchMode.phrase)],
        [page('the contract is here')],
      );
      expect(hits, hasLength(2));
    });
  });

  group('ordering and hygiene', () {
    test('the strongest match leads', () {
      final hits = run(
        [rule('contract'), rule('invoice')],
        [
          page('contract'),
          page('invoice', confidence: 0.55, pageNumber: 2),
        ],
      );
      expect(hits.first.rule.displayRepresentation, 'contract');
    });

    test('a disabled rule is skipped', () {
      final disabled = rule('contract').copyWith(enabled: false, updatedAt: t0);
      expect(run([disabled], [page('the contract is here')]), isEmpty);
    });

    test('an empty page is skipped', () {
      expect(run([rule('contract')], [page('   ')]), isEmpty);
    });

    test('no rules means no work', () {
      expect(run(const [], [page('the contract is here')]), isEmpty);
    });
  });

  test('the normalizer and the matcher agree on word boundaries', () {
    // They must, because the matcher tokenizes on the single space the
    // normalizer guarantees. If the normalizer changed and left another
    // separator behind, this is where it would show.
    final normalized = normalizer.normalizeToString('ahmed,ali;  said\nhello');
    expect(normalized.split(' '), ['ahmed', 'ali', 'said', 'hello']);
  });
}
