import 'domain/keyword_alert.dart';
import 'domain/processing_job.dart';
import 'ocr/extracted_document.dart';

/// Metrics about how the feature performs, with no way to describe what it
/// read (§10.1, §10.2).
///
/// WHY THE PROHIBITION IS A TYPE AND NOT A REVIEW
///
/// §10.2 forbids document contents, OCR plaintext, private keywords and
/// message text in telemetry. That prohibition is easy to state and easy to
/// break: a well-meaning `logEvent('match', {'keyword': rule.text})` added
/// during a debugging session ships someone's watchlist to an analytics
/// vendor, and nothing about it looks wrong in review.
///
/// So the events here carry no free-form payload. Every field is an enum, a
/// count, or a duration. There is no `Map<String, dynamic>` to slip a string
/// into, which means a leak would require changing this file — a change whose
/// entire purpose would be visible in the diff.
///
/// A note on what is measured: no metric here counts *which* keyword matched
/// or how many rules a user has. Rule count sounds harmless and is not — over
/// a population it distinguishes the person watching for one name from the
/// person watching for forty.

enum TelemetryDeviceClass {
  /// Judged from how long extraction actually took, not from a model string:
  /// device names go stale, and the number that matters is throughput anyway.
  low,
  medium,
  high,
}

/// One document, processed. Emitted whether or not anything matched, because
/// the failure and no-match rates are the interesting ones.
class DocumentProcessedEvent {
  const DocumentProcessedEvent({
    required this.outcome,
    required this.source,
    required this.textSource,
    required this.duration,
    required this.pageCount,
    required this.matchCount,
    required this.deviceClass,
    required this.retryCount,
    this.failureReason,
  });

  final JobStatus outcome;
  final ProcessingSource source;

  /// Native text layer versus optical recognition — the split that tells you
  /// whether §3.2's "never OCR a text-native PDF" is holding in the field.
  final PageTextSource textSource;

  final Duration duration;
  final int pageCount;

  /// How many matches, never which. The count is a performance signal; the
  /// identity would be the user's watchlist.
  final int matchCount;

  final TelemetryDeviceClass deviceClass;
  final int retryCount;

  /// A code from a closed set, never a message. An exception string can carry
  /// a file path, and a file path can carry a name.
  final String? failureReason;

  Map<String, Object?> toJson() => {
        'outcome': outcome.name,
        'source': source.name,
        'text_source': textSource.name,
        'duration_ms': duration.inMilliseconds,
        'page_count': pageCount,
        'match_count': matchCount,
        'device_class': deviceClass.name,
        'retry_count': retryCount,
        if (failureReason != null) 'failure_reason': failureReason,
      };
}

/// An alert's journey, for the acknowledgement-completion and
/// alert-to-acknowledge metrics (§10.3).
class AlertLifecycleEvent {
  const AlertLifecycleEvent({
    required this.status,
    required this.priority,
    required this.matchType,
    required this.confidenceBand,
    this.timeToOpen,
    this.timeToAcknowledge,
  });

  final AlertStatus status;
  final String priority;
  final MatchType matchType;

  /// A band, not a number. The exact score is meaningless to anyone reading a
  /// dashboard, and shipping it invites tuning against a population average
  /// rather than against measured precision.
  final String confidenceBand;

  final Duration? timeToOpen;
  final Duration? timeToAcknowledge;

  Map<String, Object?> toJson() => {
        'status': status.name,
        'priority': priority,
        'match_type': matchType.name,
        'confidence_band': confidenceBand,
        if (timeToOpen != null) 'time_to_open_ms': timeToOpen!.inMilliseconds,
        if (timeToAcknowledge != null)
          'time_to_acknowledge_ms': timeToAcknowledge!.inMilliseconds,
      };

  static String bandFor(double? confidence) {
    if (confidence == null) return 'unknown';
    if (confidence >= 0.85) return 'high';
    if (confidence >= 0.50) return 'medium';
    return 'low';
  }
}

/// The user told us a match was wrong. The feedback loop §11 Phase 7 requires,
/// and the only input that can actually improve precision.
class MatchFeedbackEvent {
  const MatchFeedbackEvent({
    required this.wasCorrect,
    required this.matchType,
    required this.confidenceBand,
  });

  final bool wasCorrect;
  final MatchType matchType;
  final String confidenceBand;

  Map<String, Object?> toJson() => {
        'was_correct': wasCorrect,
        'match_type': matchType.name,
        'confidence_band': confidenceBand,
      };
}

/// Where events go.
///
/// An interface rather than a concrete client, because the destination is a
/// deployment decision and because a sink that does nothing is the correct
/// default: telemetry that nobody configured should be absent, not buffered.
abstract interface class KeywordTelemetrySink {
  void documentProcessed(DocumentProcessedEvent event);
  void alertLifecycle(AlertLifecycleEvent event);
  void matchFeedback(MatchFeedbackEvent event);
}

/// The default. Emits nothing, which is what an unconfigured build should do.
class NullTelemetrySink implements KeywordTelemetrySink {
  const NullTelemetrySink();

  @override
  void documentProcessed(DocumentProcessedEvent event) {}

  @override
  void alertLifecycle(AlertLifecycleEvent event) {}

  @override
  void matchFeedback(MatchFeedbackEvent event) {}
}

/// Keeps events in memory, for tests and for the local diagnostics screen.
class RecordingTelemetrySink implements KeywordTelemetrySink {
  final List<Map<String, Object?>> events = [];

  @override
  void documentProcessed(DocumentProcessedEvent event) =>
      events.add({'event': 'document_processed', ...event.toJson()});

  @override
  void alertLifecycle(AlertLifecycleEvent event) =>
      events.add({'event': 'alert_lifecycle', ...event.toJson()});

  @override
  void matchFeedback(MatchFeedbackEvent event) =>
      events.add({'event': 'match_feedback', ...event.toJson()});
}

/// The §10.3 guardrails, evaluated locally so a regression halts a rollout
/// rather than waiting for someone to notice a dashboard (§10.4).
class GuardrailCheck {
  const GuardrailCheck({
    required this.falsePositiveRate,
    required this.dismissalRate,
    required this.crashFreeRate,
    required this.p95ProcessingSeconds,
  });

  final double falsePositiveRate;
  final double dismissalRate;
  final double crashFreeRate;
  final double p95ProcessingSeconds;

  /// Targets from §10.3. Breaching any of them halts a staged rollout
  /// automatically — §10.4 is explicit that this is not a review-time
  /// judgement call.
  static const maxFalsePositiveRate = 0.02;
  static const maxDismissalRate = 0.10;
  static const minCrashFreeRate = 0.995;
  static const maxP95Seconds = 30.0;

  List<String> get breaches => [
        if (falsePositiveRate > maxFalsePositiveRate) 'false_positive_rate',
        if (dismissalRate > maxDismissalRate) 'dismissal_rate',
        if (crashFreeRate < minCrashFreeRate) 'crash_free_rate',
        if (p95ProcessingSeconds > maxP95Seconds) 'processing_p95',
      ];

  bool get passes => breaches.isEmpty;
}
