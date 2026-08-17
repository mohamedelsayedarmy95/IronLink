import 'dart:math' as math;

import '../domain/keyword_alert.dart';
import '../domain/keyword_rule.dart';
import '../domain/processing_job.dart';
import '../ocr/extracted_document.dart';
import '../text/text_normalizer.dart';

/// The matching pipeline (§2.1).
///
/// The rule the spec states in capitals is `NEVER if OCRText.contains(keyword)`
/// — which is what the old server code did, and it is wrong in both
/// directions at once. It finds "art" inside "contract", and it misses "أحمد"
/// written with a different alef. Precision and recall both fail on the same
/// line of code.
///
/// So: normalize, tokenize, match on word boundaries, score the result against
/// several independent factors, and only then decide whether the user is worth
/// interrupting. Precision over volume (P-2) — the thresholds here err toward
/// saying nothing rather than crying wolf, because a filter the user learns to
/// ignore has failed completely.

/// §2.5 thresholds.
class ConfidenceThresholds {
  const ConfidenceThresholds._();

  /// Alert without further conditions.
  static const high = 0.85;

  /// Alert only when the surrounding evidence is strong.
  static const medium = 0.50;
}

enum ConfidenceLevel {
  high,
  medium,
  low;

  static ConfidenceLevel of(double score) {
    if (score >= ConfidenceThresholds.high) return ConfidenceLevel.high;
    if (score >= ConfidenceThresholds.medium) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }
}

/// The factors behind a score, kept separate so a bad result can be explained
/// in a log or a test rather than argued about.
///
/// Never shown to the user: §2.5 forbids exposing meaningless numeric scores,
/// and "we are 0.83 sure" is not information anyone can act on.
class ConfidenceBreakdown {
  const ConfidenceBreakdown({
    required this.engineConfidence,
    required this.matchTypeFactor,
    required this.lengthFactor,
    required this.contextFactor,
    required this.qualityFactor,
  });

  /// The engine's own certainty over the matched span. Primary weight — every
  /// other factor here modifies it rather than replacing it.
  final double engineConfidence;

  /// Exact and phrase matches are trusted as read; fuzzy is not.
  final double matchTypeFactor;

  /// Tie-breaker only. A long, specific keyword is less likely to have been
  /// hit by chance than a short one, but the effect is deliberately small —
  /// keyword length is evidence about the rule, not about this document.
  final double lengthFactor;

  /// Whether the match sits among text that was read confidently, or alone in
  /// a field of noise. A modifier, never a trigger on its own.
  final double contextFactor;

  /// Down-weighting for a poor scan. Can only reduce.
  final double qualityFactor;

  double get score => (engineConfidence *
          matchTypeFactor *
          lengthFactor *
          contextFactor *
          qualityFactor)
      .clamp(0.0, 1.0);

  ConfidenceLevel get level => ConfidenceLevel.of(score);
}

/// One hit, before it is turned into an alert.
class ScoredMatch {
  const ScoredMatch({
    required this.rule,
    required this.matchType,
    required this.breakdown,
    required this.matchedText,
    required this.contextText,
    required this.pageNumber,
    required this.sourceStart,
    required this.sourceEnd,
    this.region,
  });

  final KeywordRule rule;
  final MatchType matchType;
  final ConfidenceBreakdown breakdown;

  /// The document's own words, not the rule's. They differ under fuzzy and
  /// regex matching, and the document's wording is what makes an alert legible.
  final String matchedText;
  final String contextText;
  final int pageNumber;
  final int sourceStart;
  final int sourceEnd;
  final DocumentRegion? region;

  double get confidence => breakdown.score;

  DocumentMatch toDocumentMatch() => DocumentMatch(
        rule: rule,
        matchType: matchType,
        confidence: confidence,
        matchedText: matchedText,
        contextText: contextText,
        documentPage: pageNumber,
        documentRegion: region,
      );
}

/// A word in normalized text, with the span it occupies.
class _Token {
  const _Token(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

class KeywordMatcher {
  const KeywordMatcher({
    this.fuzzyEnabled = false,
    this.contextRadius = 48,
    this.maxContextLength = 140,
    this.maxRegexInputLength = 20000,
  });

  /// EXPERIMENTAL (§9.4, Phase 5). Off by default: edit-distance matching
  /// trades precision for recall, and precision is the principle here.
  final bool fuzzyEnabled;

  /// Characters of context either side of a hit (§4.4).
  final int contextRadius;

  /// Hard ceiling on the stored snippet. A context window wide enough to be
  /// genuinely useful is also wide enough to reconstruct the document from
  /// enough alerts, and §4.5 stores minimal derived metadata only.
  final int maxContextLength;

  /// Regex is run against the source text, which can be a whole page. Bounding
  /// the input is the second half of the defence the rule validator starts —
  /// no heuristic catches every catastrophic pattern, so nothing is allowed to
  /// run over unbounded input.
  final int maxRegexInputLength;

  /// Every match of every rule against every page, best first.
  List<ScoredMatch> match({
    required List<KeywordRule> rules,
    required ExtractedDocument document,
  }) {
    final results = <ScoredMatch>[];
    for (final page in document.pages) {
      if (page.isEmpty) continue;
      for (final rule in rules) {
        if (!rule.enabled) continue;
        results.addAll(_matchRuleOnPage(rule, page));
      }
    }

    // Deduplicate: the same rule hitting the same span twice — once as an
    // exact match and once fuzzily, say — is one finding, and the stronger
    // reading is the one to keep.
    final best = <String, ScoredMatch>{};
    for (final m in results) {
      final key = '${m.rule.id}|${m.pageNumber}|${m.sourceStart}|${m.sourceEnd}';
      final existing = best[key];
      if (existing == null || m.confidence > existing.confidence) {
        best[key] = m;
      }
    }

    return best.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  List<ScoredMatch> _matchRuleOnPage(KeywordRule rule, ExtractedPage page) {
    // A rule that is nothing but a connector would fire on every document
    // ever sent. Excluded as a whole rule only — inside a phrase, stop words
    // are preserved, because "in the matter of" depends on them (§2.1).
    if (rule.matchMode != KeywordMatchMode.regex &&
        isStopWord(rule.normalizedRepresentation)) {
      return const [];
    }

    if (rule.matchMode == KeywordMatchMode.regex) {
      return _matchRegex(rule, page);
    }

    final normalizer = TextNormalizer(caseSensitive: rule.caseSensitive);
    final normalized = normalizer.normalize(page.text);
    if (normalized.isEmpty) return const [];

    final tokens = _tokenize(normalized.value);
    final needle = _tokenize(rule.normalizedRepresentation);
    if (needle.isEmpty) return const [];

    final hits = <ScoredMatch>[];

    // Exact and phrase differ in intent, not in mechanism: both are a
    // contiguous run of whole words. A single-word "phrase" is an exact match,
    // and a multi-word "exact" rule is a phrase — treating them as one
    // sequence search avoids two code paths that must agree and eventually
    // will not.
    for (var i = 0; i + needle.length <= tokens.length; i++) {
      var matched = true;
      var fuzzyUsed = false;

      for (var j = 0; j < needle.length; j++) {
        final token = tokens[i + j].text;
        final want = needle[j].text;
        if (token == want) continue;

        if (fuzzyEnabled && _isFuzzyMatch(token, want)) {
          fuzzyUsed = true;
          continue;
        }
        matched = false;
        break;
      }
      if (!matched) continue;

      final startInNormalized = tokens[i].start;
      final endInNormalized = tokens[i + needle.length - 1].end;
      final span =
          normalized.toSourceSpan(startInNormalized, endInNormalized);

      hits.add(_score(
        rule: rule,
        page: page,
        matchType: fuzzyUsed
            ? MatchType.fuzzy
            : needle.length > 1
                ? MatchType.phrase
                : (page.text.substring(span.start, span.end) ==
                        rule.displayRepresentation
                    ? MatchType.exact
                    : MatchType.normalized),
        sourceStart: span.start,
        sourceEnd: span.end,
        tokens: tokens,
        hitIndex: i,
        hitLength: needle.length,
      ));
    }

    return hits;
  }

  List<ScoredMatch> _matchRegex(KeywordRule rule, ExtractedPage page) {
    final pattern = rule.regexPattern;
    if (pattern == null) return const [];

    // Run against the source rather than the normalized text: a pattern like
    // INV-\d{6} is written about the document's actual punctuation and casing,
    // and normalizing first would silently change what it means.
    final input = page.text.length > maxRegexInputLength
        ? page.text.substring(0, maxRegexInputLength)
        : page.text;

    final RegExp regex;
    try {
      regex = RegExp(pattern, caseSensitive: rule.caseSensitive);
    } on FormatException {
      // Validated at creation; a pattern that fails here came from a store
      // written by a different build. Losing the rule beats crashing the pass.
      return const [];
    }

    return [
      for (final m in regex.allMatches(input))
        if (m.start != m.end)
          _score(
            rule: rule,
            page: page,
            matchType: MatchType.regex,
            sourceStart: m.start,
            sourceEnd: m.end,
            tokens: const [],
            hitIndex: -1,
            hitLength: 0,
          ),
    ];
  }

  ScoredMatch _score({
    required KeywordRule rule,
    required ExtractedPage page,
    required MatchType matchType,
    required int sourceStart,
    required int sourceEnd,
    required List<_Token> tokens,
    required int hitIndex,
    required int hitLength,
  }) {
    final engineConfidence = page.confidenceOver(sourceStart, sourceEnd);

    final breakdown = ConfidenceBreakdown(
      engineConfidence: engineConfidence,
      matchTypeFactor: _matchTypeFactor(matchType),
      lengthFactor: _lengthFactor(rule.normalizedRepresentation.length),
      contextFactor: _contextFactor(page, sourceStart, sourceEnd),
      qualityFactor: _qualityFactor(page.quality),
    );

    return ScoredMatch(
      rule: rule,
      matchType:
          breakdown.level == ConfidenceLevel.low ? MatchType.lowConfidence : matchType,
      breakdown: breakdown,
      matchedText: page.text.substring(sourceStart, sourceEnd),
      contextText: _context(page.text, sourceStart, sourceEnd),
      pageNumber: page.pageNumber,
      sourceStart: sourceStart,
      sourceEnd: sourceEnd,
      region: page.regionOver(sourceStart, sourceEnd),
    );
  }

  static double _matchTypeFactor(MatchType type) => switch (type) {
        MatchType.exact => 1.0,
        MatchType.normalized => 1.0,
        MatchType.phrase => 1.0,
        MatchType.regex => 0.98,
        // Fuzzy accepted a word the document did not actually contain. That is
        // useful on a bad scan and a guess everywhere else.
        MatchType.fuzzy => 0.72,
        // Capped by §2.2 so a probabilistic technique can never be promoted to
        // HIGH however sure its own model claims to be.
        MatchType.semantic => 0.65,
        MatchType.lowConfidence => 0.4,
      };

  /// Longer keywords are less likely to be hit by chance. Kept between 0.94
  /// and 1.0 so it can break a tie and never decide an alert by itself.
  static double _lengthFactor(int length) =>
      (0.94 + math.min(length, 12) * 0.005).clamp(0.94, 1.0);

  /// How confidently the engine read the text *around* the hit.
  ///
  /// A keyword found alone in a field of noise is more likely to be an
  /// artefact of the noise than the same keyword found in a clean paragraph.
  /// Bounded at 1.0 so good context cannot promote a weak match — it can only
  /// fail to rescue one.
  double _contextFactor(ExtractedPage page, int start, int end) {
    final windowStart = math.max(0, start - contextRadius * 2);
    final windowEnd = math.min(page.text.length, end + contextRadius * 2);

    var total = 0.0;
    var count = 0;
    for (final word in page.words) {
      if (word.end <= windowStart || word.start >= windowEnd) continue;
      if (word.start >= start && word.end <= end) continue; // the hit itself
      total += word.confidence;
      count++;
    }
    if (count == 0) return 1.0; // nothing to judge by; do not invent a penalty
    final mean = total / count;
    return (0.85 + mean * 0.15).clamp(0.85, 1.0);
  }

  /// Poor scans reduce trust and can never increase it.
  static double _qualityFactor(PageQuality quality) =>
      (0.70 + quality.score * 0.30).clamp(0.70, 1.0);

  /// A readable window around the hit, cut at word boundaries.
  String _context(String text, int start, int end) {
    var from = math.max(0, start - contextRadius);
    var to = math.min(text.length, end + contextRadius);

    // Nudge outward to whitespace so the snippet does not begin mid-word.
    while (from > 0 && !_isSpace(text.codeUnitAt(from))) {
      from--;
    }
    while (to < text.length && !_isSpace(text.codeUnitAt(to - 1))) {
      to++;
    }

    var snippet = text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (snippet.length > maxContextLength) {
      snippet = '${snippet.substring(0, maxContextLength).trimRight()}…';
    }
    if (from > 0) snippet = '…$snippet';
    if (to < text.length && !snippet.endsWith('…')) snippet = '$snippet…';
    return snippet;
  }

  static bool _isSpace(int codeUnit) =>
      codeUnit == 0x20 || codeUnit == 0x0A || codeUnit == 0x0D || codeUnit == 0x09;

  /// Tokenizes on single spaces. The normalizer has already collapsed every
  /// other separator into one, so this does not need to re-derive what counts
  /// as a word boundary — and cannot disagree with the normalizer about it.
  static List<_Token> _tokenize(String normalized) {
    final tokens = <_Token>[];
    var start = -1;
    for (var i = 0; i <= normalized.length; i++) {
      final isBoundary = i == normalized.length || normalized.codeUnitAt(i) == 0x20;
      if (isBoundary) {
        if (start >= 0) {
          tokens.add(_Token(normalized.substring(start, i), start, i));
          start = -1;
        }
      } else if (start < 0) {
        start = i;
      }
    }
    return tokens;
  }

  /// EXPERIMENTAL. Edit distance of one, and only for words long enough that
  /// one substitution does not turn them into a different word entirely.
  ///
  /// "cat" and "car" are one edit apart and unrelated; "contract" and
  /// "coniract" are one edit apart and the same word misread. The length floor
  /// is what separates the two cases.
  static bool _isFuzzyMatch(String a, String b) {
    if (a.length < 5 || b.length < 5) return false;
    if ((a.length - b.length).abs() > 1) return false;
    return _editDistanceWithin(a, b, 1);
  }

  /// Bounded Levenshtein: gives up as soon as the distance exceeds [limit],
  /// so a long pair of unrelated words costs a row of the matrix, not all of it.
  static bool _editDistanceWithin(String a, String b, int limit) {
    if (a == b) return true;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      var rowBest = current[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
        if (current[j] < rowBest) rowBest = current[j];
      }
      if (rowBest > limit) return false;
      previous = current;
    }
    return previous[b.length] <= limit;
  }
}
