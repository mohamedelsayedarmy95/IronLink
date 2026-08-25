import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/keyword_alert/text/text_normalizer.dart';

/// The server's normalizer replaced every character outside `a-z0-9` with a
/// space, which deleted all of Arabic. These tests exist first to prove that
/// is gone, and second to hold the line on the opposite failure: normalizing
/// so aggressively that distinct names collapse into each other.
void main() {
  const n = TextNormalizer();
  String norm(String s) => n.normalizeToString(s);

  group('Arabic survives at all', () {
    test('an Arabic word normalizes to itself, not to nothing', () {
      // The single defect that made the whole feature useless in Arabic.
      expect(norm('محمد'), 'محمد');
      expect(norm('محمد'), isNotEmpty);
    });

    test('an Arabic sentence keeps its words', () {
      // ة → ه and ئ → ي, applied to both the document and the keyword, so the
      // folded spelling is what both sides are compared in.
      expect(norm('تقرير المراجعة النهائي'), 'تقرير المراجعه النهايي');
    });
  });

  group('Arabic variants fold together', () {
    test('alef variants all become bare alef', () {
      for (final variant in ['أحمد', 'إحمد', 'آحمد', 'ٱحمد']) {
        expect(norm(variant), 'احمد', reason: variant);
      }
    });

    test('alef maqsura folds to ya', () {
      expect(norm('مصطفى'), norm('مصطفي'));
    });

    test('ta marbuta folds to ha', () {
      expect(norm('مراجعة'), 'مراجعه');
    });

    test('hamza carriers fold to their base letters', () {
      expect(norm('مسؤول'), 'مسوول');
      expect(norm('مسئول'), 'مسيول');
    });

    test('diacritics are dropped', () {
      // Optional in writing and inconsistently produced by OCR, so matching
      // on them would fail more often than it helps.
      expect(norm('مُحَمَّد'), 'محمد');
    });

    test('tatweel is dropped', () {
      expect(norm('مـــحمد'), 'محمد');
    });

    test('bidi control characters from PDF extraction are dropped', () {
      // Written as escapes rather than literals: an embedded RLE/PDF character
      // reorders this source line in every editor that opens it, which is why
      // the analyzer rejects it in a string literal.
      final rle = String.fromCharCode(0x202B);
      final pdf = String.fromCharCode(0x202C);
      final embedded = '$rleمحمد$pdf';
      expect(norm(embedded), 'محمد');
    });
  });

  group('presentation forms', () {
    test('shaped glyphs normalize the same as the plain letters', () {
      // A PDF extractor emits the shaped glyph; the user typed the plain
      // letter. They look identical on screen and, without this, never match.
      // U+FEE3 U+FEE0 U+FEE8 = م ل ن in medial/final forms.
      expect(norm('ﻣﻠﻨ'), 'ملن');
    });

    test('a lam-alef ligature expands into two letters', () {
      expect(norm('ﻻ'), 'لا');
    });

    test('a hamza-bearing presentation form folds all the way down', () {
      // U+FE84 is the final form of أ, which must reach ا rather than stop
      // at أ — otherwise shaped text normalizes differently from plain text.
      expect(norm('ﺄ'), 'ا');
    });

    test('shaped tashkeel is dropped like ordinary diacritics', () {
      expect(norm('ﹶ'), '');
    });
  });

  group('numerals', () {
    test('Arabic-Indic digits fold to Latin', () {
      // An invoice number scanned from an Arabic document comes back as
      // ٤٤٧١; the user typed 4471.
      expect(norm('٤٤٧١'), '4471');
    });

    test('extended Arabic-Indic digits fold to Latin', () {
      expect(norm('۴۴۷۱'), '4471');
    });

    test('a mixed reference code survives intact', () {
      expect(norm('INV-٠٠١٢٣٤'), 'inv 001234');
    });
  });

  group('what must NOT be folded together', () {
    test('distinct letters stay distinct', () {
      // Over-normalization is the other way to break this feature: it merges
      // names and destroys precision.
      expect(norm('حسن'), isNot(norm('خسن')));
      expect(norm('سعيد'), isNot(norm('صعيد')));
      expect(norm('علي'), isNot(norm('عالي')));
    });

    test('a bare hamza is preserved', () {
      expect(norm('ماء'), 'ماء');
    });
  });

  group('Latin script', () {
    test('lowercases by default', () {
      expect(norm('Contract'), 'contract');
    });

    test('preserves case when asked', () {
      // For a reference code the user knows the shape of.
      expect(
        const TextNormalizer(caseSensitive: true).normalizeToString('INV-4471'),
        'INV 4471',
      );
    });

    test('accented Latin is kept, not stripped to ASCII', () {
      expect(norm('Café'), 'café');
    });
  });

  group('separators', () {
    test('punctuation separates rather than joins', () {
      // Deleting it outright would turn "ahmed,ali" into one word and match a
      // keyword that is in neither.
      expect(norm('ahmed,ali'), 'ahmed ali');
    });

    test('Arabic punctuation separates too', () {
      expect(norm('محمد، أحمد'), 'محمد احمد');
    });

    test('runs of whitespace collapse', () {
      expect(norm('  final    report  '), 'final report');
    });

    test('newlines become a single space', () {
      expect(norm('final\n\nreport'), 'final report');
    });
  });

  group('offsets back to the source', () {
    test('a match in normalized text maps onto the original words', () {
      const source = 'The FINAL report is attached';
      final result = n.normalize(source);
      final at = result.value.indexOf('final');
      final span = result.toSourceSpan(at, at + 'final'.length);

      expect(source.substring(span.start, span.end), 'FINAL');
    });

    test('survives characters that normalization deleted', () {
      // Diacritics shift every subsequent index; without the map the quoted
      // span would drift further off with each one.
      const source = 'تقرير مُحَمَّد النهائي';
      final result = n.normalize(source);
      final at = result.value.indexOf('محمد');
      final span = result.toSourceSpan(at, at + 'محمد'.length);

      expect(source.substring(span.start, span.end), 'مُحَمَّد');
    });

    test('survives a ligature that expanded into two characters', () {
      final result = n.normalize('ﻻ ok');
      final span = result.toSourceSpan(0, 2);
      expect(span.start, 0);
      expect(span.end, 1);
    });

    test('every normalized character has an offset', () {
      final result = n.normalize('  Café ٤٤٧١  مُحَمَّدﻻ ');
      expect(result.sourceOffsets, hasLength(result.value.length));
      expect(
        result.sourceOffsets.every((o) => o >= 0 && o < result.source.length),
        isTrue,
      );
    });

    test('offsets never run backwards', () {
      final result = n.normalize('تقرير مُحَمَّد rev.2 النهائي');
      for (var i = 1; i < result.sourceOffsets.length; i++) {
        expect(result.sourceOffsets[i],
            greaterThanOrEqualTo(result.sourceOffsets[i - 1]));
      }
    });
  });

  group('stop words', () {
    test('recognises common connectors in both languages', () {
      expect(isStopWord('the'), isTrue);
      expect(isStopWord('في'), isTrue);
      expect(isStopWord('و'), isTrue);
    });

    test('the Arabic list is written in normalized form', () {
      // Otherwise "إلى" would fold to "الي" and miss the list entirely.
      expect(isStopWord(norm('إلى')), isTrue);
      expect(isStopWord(norm('على')), isTrue);
    });

    test('a real keyword is not a stop word', () {
      expect(isStopWord('contract'), isFalse);
      expect(isStopWord('محمد'), isFalse);
    });
  });

  group('degenerate input', () {
    test('empty text normalizes to empty', () {
      expect(norm(''), '');
      expect(n.normalize('').sourceOffsets, isEmpty);
    });

    test('punctuation-only text normalizes to empty', () {
      expect(norm('...!!!'), '');
    });

    test('emoji do not derail the offset map', () {
      // Astral characters occupy two UTF-16 units; an offset map that counted
      // runes would drift from here on.
      final result = n.normalize('report 🚀 final');
      final at = result.value.indexOf('final');
      final span = result.toSourceSpan(at, at + 5);
      expect(result.source.substring(span.start, span.end), 'final');
    });
  });
}
