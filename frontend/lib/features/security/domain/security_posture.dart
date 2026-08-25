/// IronShield — the account's security posture, computed from facts.
///
/// WHY THIS IS A DOMAIN OBJECT AND NOT A SCREEN
///
/// A "security score" is the easiest thing in a product to fake. Pick some
/// weights, show a reassuring number, and the user learns nothing while feeling
/// safer — which is worse than showing nothing at all.
///
/// So every input here is something the system actually knows, and every output
/// names the fact behind it. There is no telemetry, no heuristic model, and no
/// server call: the inputs are the session list the server already returns and
/// state this device already holds. If a signal cannot be established, it is
/// absent rather than guessed.
library;

/// One thing that is true about the account, and what the user can do about it.
class SecurityFinding {
  const SecurityFinding({
    required this.code,
    required this.severity,
    required this.action,
  });

  /// A stable identifier, localized at the edge. Never a sentence — a finding
  /// that cannot be translated is a finding that will be shown in English to an
  /// Arabic-speaking user.
  final String code;

  final FindingSeverity severity;

  /// What the user can do, or null when the finding is informational. §5 of the
  /// engineering standard: an alert with no action is noise.
  final SecurityAction? action;
}

enum FindingSeverity {
  /// Needs attention now.
  critical,

  /// Worth reviewing.
  warning,

  /// Stated so the user can see the system checked, not because anything is
  /// wrong. "Nothing to report" is information.
  informational,
}

/// Actions IronShield can offer. Deliberately a closed set: a security screen
/// that can perform arbitrary operations is an attack surface, and every one of
/// these maps to an endpoint that already exists.
enum SecurityAction {
  /// Revoke one session — `DELETE /auth/sessions/{id}`.
  revokeSession,

  /// Revoke every session but this one. Composed from the same endpoint rather
  /// than a new bulk one, so there is no new server capability to secure.
  revokeOtherSessions,

  /// Open the list so the user can look for themselves.
  reviewSessions,
}

/// A session as the server reports it. Mirrors `SessionOut` exactly — no
/// invented fields, no fields dropped.
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.ipAddress,
    required this.createdAt,
    required this.isCurrent,
    this.deviceType,
    this.deviceName,
    this.geoCity,
    this.lastActiveAt,
  });

  final String id;
  final String ipAddress;
  final DateTime createdAt;

  /// Set by the server for the session making the request. The screen must
  /// never offer to revoke this one as "another device".
  final bool isCurrent;

  final String? deviceType;
  final String? deviceName;
  final String? geoCity;
  final DateTime? lastActiveAt;

  /// What to call this device when the server gave no name.
  ///
  /// Falls back through name, then type, then nothing — never to the IP
  /// address. An IP is not a device name, and showing one invites the user to
  /// treat a number they cannot interpret as identification.
  String? get displayName => deviceName ?? deviceType;

  /// Whether this session has been idle long enough to be worth a second look.
  ///
  /// Two weeks, and only as a *warning*: a tablet someone uses monthly is not a
  /// compromise, and calling it one teaches the user to dismiss warnings.
  bool isStale(DateTime now) {
    final seen = lastActiveAt ?? createdAt;
    return now.difference(seen) > const Duration(days: 14);
  }

  static ActiveSession fromJson(Map<String, dynamic> json) => ActiveSession(
        id: json['id'] as String,
        ipAddress: json['ip_address'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        isCurrent: json['is_current'] as bool? ?? false,
        deviceType: json['device_type'] as String?,
        deviceName: json['device_name'] as String?,
        geoCity: json['geo_city'] as String?,
        lastActiveAt: json['last_active_at'] == null
            ? null
            : DateTime.parse(json['last_active_at'] as String).toUtc(),
      );
}

/// The overall rating. Three levels, because a percentage implies a precision
/// this cannot have.
enum SecurityLevel { high, medium, low }

class SecurityPosture {
  const SecurityPosture({
    required this.sessions,
    required this.findings,
    required this.level,
  });

  final List<ActiveSession> sessions;
  final List<SecurityFinding> findings;
  final SecurityLevel level;

  List<ActiveSession> get otherSessions =>
      sessions.where((s) => !s.isCurrent).toList(growable: false);

  /// Derives the posture from what is known.
  ///
  /// [encryptionDefault] and [keywordsAreLocal] are passed in rather than read
  /// here, because this file must not depend on the crypto or keyword layers —
  /// and because a caller that cannot establish one of them should pass null
  /// and get an honest absence rather than a default that flatters the score.
  static SecurityPosture from({
    required List<ActiveSession> sessions,
    required DateTime now,
    bool? encryptionDefault,
    bool? keywordsAreLocal,
    bool? cloudOcrEnabled,
  }) {
    final findings = <SecurityFinding>[];

    final others = sessions.where((s) => !s.isCurrent).toList();

    // Several signed-in devices is normal, not a problem. It is stated because
    // "you are signed in on four devices" is the single most useful thing this
    // screen can tell someone whose account was taken — and stating it only
    // when it looks suspicious would mean never stating it in the case that
    // matters.
    if (others.isNotEmpty) {
      findings.add(const SecurityFinding(
        code: 'other_devices_signed_in',
        severity: FindingSeverity.informational,
        action: SecurityAction.reviewSessions,
      ));
    }

    final stale = others.where((s) => s.isStale(now)).toList();
    if (stale.isNotEmpty) {
      findings.add(const SecurityFinding(
        code: 'stale_session',
        severity: FindingSeverity.warning,
        action: SecurityAction.revokeOtherSessions,
      ));
    }

    // Encryption is the product's central claim. If this device cannot confirm
    // it is on, that is the most serious thing the screen can say.
    if (encryptionDefault == false) {
      findings.add(const SecurityFinding(
        code: 'encryption_not_default',
        severity: FindingSeverity.critical,
        action: null,
      ));
    } else if (encryptionDefault == true) {
      findings.add(const SecurityFinding(
        code: 'encryption_on',
        severity: FindingSeverity.informational,
        action: null,
      ));
    }

    // Where keyword rules live is a privacy fact the user is entitled to see
    // stated, not merely promised in a settings description.
    if (keywordsAreLocal == true) {
      findings.add(const SecurityFinding(
        code: 'keywords_stay_on_device',
        severity: FindingSeverity.informational,
        action: null,
      ));
    }

    // Cloud OCR off is the default and the private choice. On is not a
    // misconfiguration — the user chose it — but it is a fact worth surfacing,
    // because §10.3 of the alert specification treats a high opt-in rate as a
    // privacy health failure rather than adoption.
    if (cloudOcrEnabled == true) {
      findings.add(const SecurityFinding(
        code: 'cloud_ocr_enabled',
        severity: FindingSeverity.warning,
        action: null,
      ));
    }

    return SecurityPosture(
      sessions: sessions,
      findings: findings,
      level: _levelFrom(findings),
    );
  }

  /// The worst finding sets the level.
  ///
  /// Not a weighted average: averaging lets four reassuring facts bury one
  /// critical one, which is the exact failure mode of every security score that
  /// tells users what they want to hear.
  static SecurityLevel _levelFrom(List<SecurityFinding> findings) {
    if (findings.any((f) => f.severity == FindingSeverity.critical)) {
      return SecurityLevel.low;
    }
    if (findings.any((f) => f.severity == FindingSeverity.warning)) {
      return SecurityLevel.medium;
    }
    return SecurityLevel.high;
  }
}
