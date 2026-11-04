/// Every capability that is not finished, in one place (§9.4).
///
/// WHY A REGISTRY RATHER THAN SCATTERED BOOLEANS
///
/// §9.4's rule is that incomplete capabilities stay hidden and are never
/// exposed as production-ready. A boolean buried in whichever class needed it
/// satisfies that for as long as everyone remembers; a registry makes the
/// answer to "what is experimental right now?" a thing you can read, and a
/// thing a test can assert about.
///
/// R12 also requires that disabling a flag fully reverts behaviour with no
/// partial state left behind. That is why none of these flags controls
/// storage: turning fuzzy matching off stops new fuzzy matches, and the alerts
/// it already raised remain valid alerts about real documents. There is no
/// half-migrated state to unwind, because no flag here migrates anything.
class KeywordFeatureFlags {
  const KeywordFeatureFlags({
    this.fuzzyMatching = false,
    this.cloudOcr = false,
    this.semanticMatching = false,
    this.synonymExpansion = false,
    this.officeDocuments = false,
  });

  /// EXPERIMENTAL. Edit-distance matching trades precision for recall, and
  /// precision is the principle this feature is built on (P-2). Implemented
  /// and tested; off until it earns its way in through the §10.4 staged
  /// rollout, with false-positive rate as the guardrail.
  final bool fuzzyMatching;

  /// Requires explicit consent, and §10.3 treats an opt-in rate above 20% as
  /// a privacy health failure rather than adoption. The decision matrix that
  /// governs it is implemented; the cloud engine behind it is not.
  final bool cloudOcr;

  /// NOT IMPLEMENTED. The flag exists so that the matcher's MatchType.semantic
  /// branch cannot be reached by accident, and so this file is an honest
  /// inventory rather than a list of only the things that happen to exist.
  final bool semanticMatching;

  /// NOT IMPLEMENTED. Same reasoning.
  final bool synonymExpansion;

  /// NOT IMPLEMENTED. DOCX, XLSX and PPTX extraction. Plain text and PDF are
  /// implemented and are not behind a flag, because they work.
  final bool officeDocuments;

  /// What ships. Everything unfinished is off, which is the only defensible
  /// default: a flag that defaults on is not a flag, it is a release.
  static const production = KeywordFeatureFlags();

  /// Capabilities that exist in code but are not production-ready, by name.
  /// Used by the Security Center and by the test that stops a half-built
  /// feature reaching users.
  static const experimental = <String>{
    'fuzzyMatching',
    'cloudOcr',
    'semanticMatching',
    'synonymExpansion',
    'officeDocuments',
  };

  /// Whether anything experimental is on, for the honest label in settings.
  bool get anyExperimentalEnabled =>
      fuzzyMatching ||
      cloudOcr ||
      semanticMatching ||
      synonymExpansion ||
      officeDocuments;

  Map<String, bool> asMap() => {
        'fuzzyMatching': fuzzyMatching,
        'cloudOcr': cloudOcr,
        'semanticMatching': semanticMatching,
        'synonymExpansion': synonymExpansion,
        'officeDocuments': officeDocuments,
      };

  KeywordFeatureFlags copyWith({
    bool? fuzzyMatching,
    bool? cloudOcr,
    bool? semanticMatching,
    bool? synonymExpansion,
    bool? officeDocuments,
  }) =>
      KeywordFeatureFlags(
        fuzzyMatching: fuzzyMatching ?? this.fuzzyMatching,
        cloudOcr: cloudOcr ?? this.cloudOcr,
        semanticMatching: semanticMatching ?? this.semanticMatching,
        synonymExpansion: synonymExpansion ?? this.synonymExpansion,
        officeDocuments: officeDocuments ?? this.officeDocuments,
      );
}
