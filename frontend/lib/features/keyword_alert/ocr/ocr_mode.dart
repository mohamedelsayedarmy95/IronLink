import '../domain/keyword_alert.dart';

/// The local-versus-cloud decision (§3.3).
///
/// The spec's wording is that the engine must apply this order
/// "deterministically, never opportunistically", and the reason is worth
/// stating plainly: cloud OCR means the user's document leaves their phone and
/// is read by someone else's computer. That can be a reasonable trade when the
/// user has chosen it, and it is a betrayal when it happens because local
/// extraction was slow and something decided to be helpful.
///
/// So this is a pure function over the four inputs that matter, with no
/// ambient state and no room for a "just this once". It returns a decision;
/// it does not perform one.

enum OcrModeOutcome {
  /// Run on-device. The only outcome possible while cloud OCR is off.
  local,

  /// Send to the cloud, with the processing mode visible in the UI while it
  /// happens — never silently.
  cloud,

  /// Cloud was needed and there is no network. The request waits (§8.5)
  /// rather than being dropped or quietly downgraded.
  waitForNetwork,

  /// Nothing can read this document here, and cloud is not permitted.
  unavailable,
}

class OcrModeDecision {
  const OcrModeDecision(this.outcome, this.reason);

  final OcrModeOutcome outcome;

  /// A code for logs and the Security Center. Never a user-facing sentence.
  final String reason;

  ProcessingSource? get source => switch (outcome) {
        OcrModeOutcome.local => ProcessingSource.local,
        OcrModeOutcome.cloud => ProcessingSource.cloud,
        _ => null,
      };

  /// Applies the §3.3 decision matrix in order.
  ///
  /// [localSucceeded] is the outcome of actually trying locally, not a guess
  /// at whether it would work. The matrix is explicit that cloud is never
  /// invoked when the local attempt succeeded — not to save money, but to
  /// avoid a transmission that turned out to be unnecessary.
  static OcrModeDecision decide({
    required bool cloudEnabled,
    required bool localAvailable,
    required bool localSucceeded,
    required bool networkAvailable,
  }) {
    if (localSucceeded) {
      return const OcrModeDecision(OcrModeOutcome.local, 'local_succeeded');
    }

    // The default, and the branch that must never be reachable past this
    // point by any other route.
    if (!cloudEnabled) {
      return localAvailable
          ? const OcrModeDecision(OcrModeOutcome.unavailable, 'local_failed')
          : const OcrModeDecision(
              OcrModeOutcome.unavailable, 'no_local_engine');
    }

    if (!networkAvailable) {
      return const OcrModeDecision(
          OcrModeOutcome.waitForNetwork, 'cloud_needs_network');
    }

    return const OcrModeDecision(OcrModeOutcome.cloud, 'local_failed');
  }
}

/// The deterministic local retry ladder (§3.3).
///
/// "Local fail → retry with preprocessing → retry alternate config → still
/// failing → unable to read". Three attempts, in a fixed order, and then an
/// honest admission. Never an escalation to the cloud, which is a different
/// decision made by a different function above.
enum LocalRetryStep {
  /// The document as it arrived.
  asIs,

  /// Deskewed, contrast-normalized, denoised — the §3.1 preprocessing that
  /// costs time and is therefore not done speculatively on the first pass.
  preprocessed,

  /// A different engine configuration: single-block layout, or a script hint,
  /// for a page whose structure defeated the default.
  alternateConfiguration;

  LocalRetryStep? get next => switch (this) {
        LocalRetryStep.asIs => LocalRetryStep.preprocessed,
        LocalRetryStep.preprocessed => LocalRetryStep.alternateConfiguration,
        LocalRetryStep.alternateConfiguration => null,
      };

  static const first = LocalRetryStep.asIs;
}
