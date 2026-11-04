import 'dart:math';

/// Turns recorded amplitudes into the bars drawn under a voice note.
///
/// Pure functions, kept apart from the widgets so the behaviour that matters —
/// that a quiet recording does not render as a flat line, and that a long one
/// still fits — can be tested without a microphone.
class Waveform {
  const Waveform._();

  /// Bars stored per voice note. Enough to show shape, small enough that the
  /// list stays cheap inside the encrypted envelope.
  static const bars = 40;

  /// Anything at or below this is treated as silence.
  ///
  /// dBFS is negative, 0 being full scale. Real speech on a phone microphone
  /// sits around -30, and the noise floor well below -50, so a wider floor
  /// would spend most of the visible range on room tone.
  static const floorDb = -50.0;

  /// Maps one dBFS reading to 0..1.
  static double normalize(double db) {
    if (db.isNaN || db.isInfinite) return 0;
    final clamped = db.clamp(floorDb, 0.0);
    return (clamped - floorDb) / -floorDb;
  }

  /// Resamples [samples] to exactly [bars] values.
  ///
  /// Each output bar is the loudest input it covers, not the average: peaks
  /// are what makes speech legible as a shape, and averaging flattens them
  /// into an indistinct band.
  static List<double> resample(List<double> samples, {int bars = bars}) {
    if (bars <= 0) return const [];
    if (samples.isEmpty) return List<double>.filled(bars, 0);
    if (samples.length <= bars) {
      // Short recording: pad rather than stretch, so a one-second note does
      // not claim the same visual length as a one-minute one.
      return [
        ...samples.map((s) => s.clamp(0.0, 1.0).toDouble()),
        ...List<double>.filled(bars - samples.length, 0),
      ];
    }

    final out = <double>[];
    final step = samples.length / bars;
    for (var i = 0; i < bars; i++) {
      final start = (i * step).floor();
      final end = min(((i + 1) * step).ceil(), samples.length);
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        if (samples[j] > peak) peak = samples[j];
      }
      out.add(peak.clamp(0.0, 1.0).toDouble());
    }
    return out;
  }

  /// Scales so the loudest bar reaches full height.
  ///
  /// Without this a softly spoken note is a barely visible strip. Recordings
  /// that are silence throughout are left alone — amplifying nothing just
  /// turns the noise floor into a fake waveform.
  static List<double> normalizeLoudness(List<double> bars) {
    if (bars.isEmpty) return bars;
    final peak = bars.reduce(max);
    if (peak < 0.05) return bars;
    return [for (final b in bars) (b / peak).clamp(0.0, 1.0).toDouble()];
  }

  /// The full pipeline: dBFS readings in, drawable bars out.
  static List<double> fromDecibels(List<double> readings) =>
      normalizeLoudness(resample(readings.map(normalize).toList()));
}
