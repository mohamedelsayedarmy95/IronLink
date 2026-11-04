import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/chat/widgets/waveform.dart';

/// The waveform used to be `List.generate(20, ...)` — decoration that looked
/// like information. These cover the properties that make the bars actually
/// correspond to the audio.
void main() {
  group('normalizing one reading', () {
    test('full scale is the top of the range', () {
      expect(Waveform.normalize(0), 1.0);
    });

    test('the floor and anything below it are silence', () {
      expect(Waveform.normalize(Waveform.floorDb), 0.0);
      expect(Waveform.normalize(-120), 0.0);
    });

    test('a mid reading lands in the middle', () {
      expect(Waveform.normalize(Waveform.floorDb / 2), closeTo(0.5, 0.001));
    });

    test('readings stay within range', () {
      for (final db in [5.0, 0.0, -10.0, -50.0, -200.0]) {
        final v = Waveform.normalize(db);
        expect(v, inInclusiveRange(0.0, 1.0), reason: '$db');
      }
    });

    test('a missing reading is silence, not a crash', () {
      // Platforms occasionally report these when the mic has not warmed up.
      expect(Waveform.normalize(double.nan), 0.0);
      expect(Waveform.normalize(double.negativeInfinity), 0.0);
      expect(Waveform.normalize(double.infinity), 0.0);
    });
  });

  group('resampling to a fixed number of bars', () {
    test('a long recording is reduced to exactly the bar count', () {
      final samples = List<double>.generate(5000, (i) => (i % 100) / 100);
      expect(Waveform.resample(samples), hasLength(Waveform.bars));
    });

    test('peaks survive being resampled', () {
      // A short loud burst in a quiet recording is the thing you most want
      // to see. Averaging would erase it.
      final samples = List<double>.filled(1000, 0.1);
      samples[500] = 1.0;

      final bars = Waveform.resample(samples);
      expect(bars.reduce((a, b) => a > b ? a : b), 1.0);
    });

    test('a short recording is padded, not stretched', () {
      final bars = Waveform.resample([1.0, 1.0, 1.0]);

      expect(bars, hasLength(Waveform.bars));
      // A one-second note must not look as long as a one-minute one.
      expect(bars.take(3), everyElement(1.0));
      expect(bars.skip(3), everyElement(0.0));
    });

    test('no samples gives a flat line rather than an error', () {
      expect(Waveform.resample(const []), hasLength(Waveform.bars));
      expect(Waveform.resample(const []), everyElement(0.0));
    });

    test('values stay in range even if inputs do not', () {
      final bars = Waveform.resample(
        List<double>.generate(200, (i) => i.isEven ? 5.0 : -3.0),
      );
      expect(bars, everyElement(inInclusiveRange(0.0, 1.0)));
    });
  });

  group('loudness', () {
    test('a quiet recording is scaled up to be visible', () {
      final bars = Waveform.normalizeLoudness([0.1, 0.2, 0.05]);

      // Otherwise a softly spoken note renders as a barely visible strip.
      expect(bars.reduce((a, b) => a > b ? a : b), 1.0);
      // Relative shape is preserved.
      expect(bars[0] / bars[1], closeTo(0.5, 0.001));
    });

    test('silence is left alone rather than amplified into a fake waveform',
        () {
      final bars = Waveform.normalizeLoudness([0.0, 0.01, 0.0]);
      expect(bars.reduce((a, b) => a > b ? a : b), lessThan(0.05));
    });

    test('an already loud recording is unchanged', () {
      expect(Waveform.normalizeLoudness([1.0, 0.5]), [1.0, 0.5]);
    });
  });

  group('the whole pipeline', () {
    test('real dBFS readings become drawable bars', () {
      // Speech with pauses: the quiet stretches have to be longer than one
      // bar's window, or peak-picking legitimately reports every bar as loud.
      // 300 readings across 40 bars is 7.5 readings per bar, so the gaps here
      // are 30 long.
      final readings = <double>[
        for (var i = 0; i < 300; i++) (i ~/ 30).isEven ? -45.0 : -15.0,
      ];

      final bars = Waveform.fromDecibels(readings);

      expect(bars, hasLength(Waveform.bars));
      expect(bars, everyElement(inInclusiveRange(0.0, 1.0)));
      // Speech has shape; a constant result would mean the readings were
      // being ignored, which is what the old mock did.
      expect(bars.toSet().length, greaterThan(1));
    });

    test('a silent recording does not produce an invented waveform', () {
      final bars = Waveform.fromDecibels(List<double>.filled(200, -80));
      expect(bars, everyElement(lessThan(0.05)));
    });

    test('no readings at all is handled', () {
      expect(Waveform.fromDecibels(const []), hasLength(Waveform.bars));
    });
  });
}
