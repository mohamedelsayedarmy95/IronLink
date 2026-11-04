/// Text normalization for Arabic and Latin script, with offsets preserved.
///
/// WHAT WAS THERE BEFORE
///
/// The server's normalizer was `text.toLowerCase()` followed by
/// `re.sub(r'[^a-z0-9\s]', ' ', text)`. Every Arabic codepoint falls outside
/// `a-z0-9`, so every one of them was replaced by a space. An Arabic keyword
/// could not match an Arabic document — in an Arabic-first product. That is
/// the defect this file exists to fix, and it is why the rules here are
/// written out and tested individually rather than delegated to a regex.
///
/// WHY OFFSETS ARE CARRIED ALONG
///
/// Normalization deletes characters (diacritics), substitutes them (أ → ا),
/// and occasionally expands one into two (the lam-alef ligature). A match
/// found in normalized text therefore sits at an index that means nothing in
/// the document the user is about to look at. Carrying a per-character map
/// back to the source is what lets an alert quote the document's own words and
/// lets the viewer highlight the right span — §4.4 is explicit that "Keyword
/// found." is not an acceptable alert.
///
/// WHY NORMALIZATION STOPS WHERE IT DOES
///
/// §2.3: never over-normalize into false positives — names and codes must
/// survive. Folding ة to ه and ى to ي is conventional and repairs real OCR and
/// keyboard variation. Folding further (stripping hamza from ء entirely, say,
/// or collapsing ح/خ) would start merging distinct names, which costs
/// precision, and precision is the principle this feature is built on.
library;

/// Normalized text plus the map back to where each character came from.
class NormalizedText {
  const NormalizedText(this.value, this.sourceOffsets, this.source);

  /// The normalized form, used for matching.
  final String value;

  /// `sourceOffsets[i]` is the index in [source] that produced `value[i]`.
  /// Two normalized characters can share one source index, where a ligature
  /// was expanded.
  final List<int> sourceOffsets;

  /// The original text, kept intact. §2.3 requires the two be stored
  /// separately rather than the original being thrown away.
  final String source;

  bool get isEmpty => value.isEmpty;

  /// Maps a span in the normalized text back to a span in the source.
  ///
  /// The end is the source offset of the last matched character plus one,
  /// not the offset of the character after it — the character after may have
  /// been deleted during normalization and so have no offset at all.
  ({int start, int end}) toSourceSpan(int start, int end) {
    if (sourceOffsets.isEmpty) return (start: 0, end: 0);
    final s = sourceOffsets[start.clamp(0, sourceOffsets.length - 1)];
    final lastIndex = (end - 1).clamp(0, sourceOffsets.length - 1);
    final e = sourceOffsets[lastIndex] + 1;
    return (start: s, end: e < s ? s : e);
  }
}

class TextNormalizer {
  const TextNormalizer({this.caseSensitive = false});

  /// Only meaningful for Latin script — Arabic has no case. Kept as a flag so
  /// a reference code like "INV-4471" can be matched exactly.
  final bool caseSensitive;

  /// Normalizes [input], recording where each output character came from.
  NormalizedText normalize(String input) {
    final buffer = StringBuffer();
    final offsets = <int>[];

    final runes = input.runes.toList(growable: false);
    // Rune index and UTF-16 index differ once astral characters appear, and
    // every offset consumed downstream is a UTF-16 index into the source.
    var sourceIndex = 0;

    for (final rune in runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      final at = sourceIndex;
      sourceIndex += width;

      if (_isRemovable(rune)) continue;

      final replacement = _fold(rune);
      if (replacement == null) {
        // Not a character this normalizer changes. Anything that is neither
        // a letter nor a digit becomes a single space, so that punctuation
        // separates tokens instead of joining them — but it is a space, not
        // a deletion, so "ahmed,ali" does not become one word.
        final char = String.fromCharCode(rune);
        final out = _isWordCharacter(rune)
            ? (caseSensitive ? char : char.toLowerCase())
            : ' ';
        for (var i = 0; i < out.length; i++) {
          offsets.add(at);
        }
        buffer.write(out);
        continue;
      }

      final out = caseSensitive ? replacement : replacement.toLowerCase();
      for (var i = 0; i < out.length; i++) {
        offsets.add(at);
      }
      buffer.write(out);
    }

    // Collapse runs of whitespace, keeping the offset of the first character
    // of each run so a match that begins after a run still points at real text.
    final collapsed = StringBuffer();
    final collapsedOffsets = <int>[];
    final raw = buffer.toString();
    var previousWasSpace = true; // leading whitespace is dropped outright
    for (var i = 0; i < raw.length; i++) {
      final isSpace = raw.codeUnitAt(i) == 0x20;
      if (isSpace && previousWasSpace) continue;
      collapsed.writeCharCode(isSpace ? 0x20 : raw.codeUnitAt(i));
      collapsedOffsets.add(offsets[i]);
      previousWasSpace = isSpace;
    }

    var value = collapsed.toString();
    var finalOffsets = collapsedOffsets;
    if (value.endsWith(' ')) {
      value = value.substring(0, value.length - 1);
      finalOffsets = finalOffsets.sublist(0, finalOffsets.length - 1);
    }

    return NormalizedText(value, finalOffsets, input);
  }

  /// Convenience for callers that only need the string — rule creation, mostly,
  /// where there is no document to point back into.
  String normalizeToString(String input) => normalize(input).value;

  // ── Character classes ──────────────────────────────────────────────────────

  /// Characters that carry no matching signal and are deleted outright.
  static bool _isRemovable(int rune) {
    // Arabic diacritics: fathatan through sukun, plus the superscript alef and
    // the Quranic annotation marks. Optional in writing and inconsistently
    // produced by OCR, so matching on them would fail more often than it helps.
    if (rune >= 0x064B && rune <= 0x065F) return true;
    if (rune == 0x0670) return true;
    if (rune >= 0x06D6 && rune <= 0x06ED) return true;
    // Tatweel — a typographic stretch with no phonetic content. "مـــحمد" and
    // "محمد" are the same word.
    if (rune == 0x0640) return true;
    // The shaped forms of those same diacritics, from the presentation block.
    if (rune >= 0xFE70 && rune <= 0xFE7F) return true;
    // Zero-width joiners and marks, and the bidirectional control characters
    // that PDF extractors sprinkle through right-to-left text.
    if (rune == 0x200B || rune == 0x200C || rune == 0x200D) return true;
    if (rune >= 0x200E && rune <= 0x200F) return true;
    if (rune >= 0x202A && rune <= 0x202E) return true;
    if (rune == 0xFEFF) return true;
    return false;
  }

  static bool _isWordCharacter(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return true; // 0-9
    if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
    if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
    if (rune >= 0x00C0 && rune <= 0x024F) return true; // Latin-1 + extended
    if (rune >= 0x0620 && rune <= 0x063F) return true; // Arabic letters
    if (rune >= 0x0641 && rune <= 0x064A) return true;
    if (rune >= 0x066E && rune <= 0x06D3) return true; // extended Arabic
    return false;
  }

  /// Returns the folded form of [rune], or null if it is unchanged.
  static String? _fold(int rune) {
    // Arabic-Indic and Extended Arabic-Indic digits. An invoice number scanned
    // from an Arabic document comes back as ٤٤٧١; the user typed 4471.
    if (rune >= 0x0660 && rune <= 0x0669) {
      return String.fromCharCode(0x30 + (rune - 0x0660));
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      return String.fromCharCode(0x30 + (rune - 0x06F0));
    }

    // Letter variants. Deliberately conservative — see the library comment.
    switch (rune) {
      case 0x0622: // آ
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0671: // ٱ
        return 'ا'; // ا
      case 0x0649: // ى  alef maqsura
        return 'ي'; // ي
      case 0x0629: // ة  ta marbuta
        return 'ه'; // ه
      case 0x0624: // ؤ
        return 'و'; // و
      case 0x0626: // ئ
        return 'ي'; // ي
    }

    // Presentation forms. PDF text extraction, and some keyboards, emit the
    // shaped glyph rather than the base letter: visually identical, a
    // different codepoint, and no match without this.
    final presentation = _presentationForms[rune];
    if (presentation != null) return presentation;

    return null;
  }

  /// U+FE80–U+FEFC, the Arabic Presentation Forms-B block, mapped straight to
  /// the *already-folded* base letter.
  ///
  /// Mapping to the unfolded letter would be a bug: [_fold] returns as soon as
  /// it finds a replacement, so a presentation form of أ that produced أ would
  /// never go on to become ا, and the shaped text would normalize differently
  /// from the plain text it is identical to on screen.
  ///
  /// Each letter occupies a run in block order — two forms (isolated, final)
  /// for the letters that never join to the left, four (isolated, final,
  /// initial, medial) for the rest — so the table is generated from the runs.
  static final Map<int, String> _presentationForms = _buildPresentationForms();

  static Map<int, String> _buildPresentationForms() {
    // (start codepoint, number of forms, folded base) in block order.
    const runs = <(int, int, String)>[
      (0xFE80, 1, 'ء'),
      (0xFE81, 2, 'ا'), // آ folds to ا
      (0xFE83, 2, 'ا'), // أ
      (0xFE85, 2, 'و'), // ؤ folds to و
      (0xFE87, 2, 'ا'), // إ
      (0xFE89, 4, 'ي'), // ئ folds to ي
      (0xFE8D, 2, 'ا'),
      (0xFE8F, 4, 'ب'),
      (0xFE93, 2, 'ه'), // ة folds to ه
      (0xFE95, 4, 'ت'),
      (0xFE99, 4, 'ث'),
      (0xFE9D, 4, 'ج'),
      (0xFEA1, 4, 'ح'),
      (0xFEA5, 4, 'خ'),
      (0xFEA9, 2, 'د'),
      (0xFEAB, 2, 'ذ'),
      (0xFEAD, 2, 'ر'),
      (0xFEAF, 2, 'ز'),
      (0xFEB1, 4, 'س'),
      (0xFEB5, 4, 'ش'),
      (0xFEB9, 4, 'ص'),
      (0xFEBD, 4, 'ض'),
      (0xFEC1, 4, 'ط'),
      (0xFEC5, 4, 'ظ'),
      (0xFEC9, 4, 'ع'),
      (0xFECD, 4, 'غ'),
      (0xFED1, 4, 'ف'),
      (0xFED5, 4, 'ق'),
      (0xFED9, 4, 'ك'),
      (0xFEDD, 4, 'ل'),
      (0xFEE1, 4, 'م'),
      (0xFEE5, 4, 'ن'),
      (0xFEE9, 4, 'ه'),
      (0xFEED, 2, 'و'),
      (0xFEEF, 2, 'ي'), // ى folds to ي
      (0xFEF1, 4, 'ي'),
      // Lam-alef ligatures: one glyph standing for two letters. Expanding them
      // is the reason the offset map allows two output characters to share a
      // single source index.
      (0xFEF5, 8, 'لا'),
    ];

    final map = <int, String>{};
    for (final (start, count, base) in runs) {
      for (var i = 0; i < count; i++) {
        map[start + i] = base;
      }
    }
    return map;
  }
}

/// Connector words excluded from standalone matching (§2.1).
///
/// A rule that is nothing but "the" or "في" would fire on essentially every
/// document, which is alert fatigue rather than a filter. They are only
/// excluded as *whole rules* and as standalone tokens — inside a phrase they
/// are preserved, because "in the matter of" depends on them.
/// Written in already-normalized form, because that is what they are compared
/// against — "إلى" and "الى" both fold to "الي", so only the folded spelling
/// belongs here.
const arabicStopWords = <String>{
  'في', 'من', 'الي', 'علي', 'عن', 'مع', 'هذا', 'هذه', 'ذلك',
  'التي', 'الذي', 'ان', 'كان', 'قد', 'لا', 'ما', 'و', 'او',
  'ثم', 'كل', 'بعد', 'قبل', 'بين', 'عند', 'هو', 'هي',
};

const englishStopWords = <String>{
  'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'at', 'for', 'with',
  'is', 'are', 'was', 'were', 'be', 'been', 'by', 'as', 'that', 'this', 'it',
  'from', 'not', 'but', 'has', 'have', 'had', 'will', 'would', 'can', 'could',
};

/// Expects an already-normalized token — the lists above are written in the
/// same shape, so normalizing again here would be redundant work on the
/// hottest loop in the feature.
bool isStopWord(String normalizedToken) =>
    englishStopWords.contains(normalizedToken) ||
    arabicStopWords.contains(normalizedToken);
