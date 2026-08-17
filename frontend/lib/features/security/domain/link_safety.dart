/// IronShield — link safety, entirely on this device.
///
/// WHY THERE IS NO BLOCKLIST
///
/// The obvious implementation is to check each URL against a reputation
/// service. That would mean sending every link the user receives to a third
/// party, which is a browsing history — of an end-to-end encrypted messenger,
/// assembled by the one component whose job is protecting it. Google Safe
/// Browsing's hash-prefix protocol exists to soften exactly that and still
/// leaks enough to be worth avoiding here.
///
/// So this is structural analysis only. It reads the URL, and nothing leaves.
/// That bounds what it can find: it cannot know a domain registered yesterday
/// is serving malware. What it *can* do is catch deception encoded in the URL
/// itself, which is how the overwhelming majority of phishing links reach a
/// person in a chat app.
///
/// WHY IT NEVER BLOCKS
///
/// Every finding is an annotation. A messenger that refuses to open links is a
/// messenger people route around, and a false positive on a legitimate link
/// teaches the user that the warning means nothing. Precision over volume, and
/// the user decides.
library;

/// What is wrong with a link. Codes, localized at the edge.
enum LinkRisk {
  /// The visible domain mixes scripts — Cyrillic "а" inside "pаypal.com".
  /// Invisible to the eye and the single most effective phishing technique
  /// against a reader who checks carefully.
  mixedScriptDomain,

  /// Punycode: the URL is an encoded internationalised domain. Legitimate for
  /// genuinely non-Latin sites, and also how a homograph arrives over the wire.
  punycodeDomain,

  /// `https://apple.com@evil.example` — everything before the @ is a username,
  /// and the browser goes to evil.example. Reads as the real thing.
  credentialsInUrl,

  /// A bare IP address instead of a name. Real services have names.
  ipAddressHost,

  /// `paypal.com.evil.example` — the brand is a subdomain of somewhere else.
  deceptiveSubdomain,

  /// A near-miss of a well-known domain: `paypa1.com`, `goggle.com`.
  lookalikeDomain,

  /// A login-looking page over plain HTTP. Credentials in the clear.
  insecureLoginPage,

  /// Deeply nested subdomains, which push the real domain off the end of a
  /// narrow screen.
  excessiveSubdomains,
}

class LinkFinding {
  const LinkFinding(this.risk, {this.detail});

  final LinkRisk risk;

  /// The specific evidence — the impersonated brand, the script that was
  /// mixed in. Shown to the user, so it must never be a stack trace or a
  /// scheme-internal token.
  final String? detail;

  /// Whether this alone is enough to warn about.
  ///
  /// Punycode and deep subdomains are suspicious in company and unremarkable
  /// alone: a genuine Arabic-script domain is punycode, and plenty of real
  /// services nest three levels deep.
  bool get isStandalone => switch (risk) {
        LinkRisk.mixedScriptDomain ||
        LinkRisk.credentialsInUrl ||
        LinkRisk.deceptiveSubdomain ||
        LinkRisk.lookalikeDomain ||
        LinkRisk.insecureLoginPage =>
          true,
        LinkRisk.punycodeDomain ||
        LinkRisk.ipAddressHost ||
        LinkRisk.excessiveSubdomains =>
          false,
      };
}

class LinkVerdict {
  const LinkVerdict({required this.url, required this.findings});

  final String url;
  final List<LinkFinding> findings;

  /// Warn only when something is conclusive on its own, or when two weaker
  /// signals agree. One weak signal is not worth interrupting anyone over.
  bool get shouldWarn =>
      findings.any((f) => f.isStandalone) || findings.length >= 2;

  bool get isClean => findings.isEmpty;
}

class LinkSafety {
  const LinkSafety();

  /// Domains worth protecting by name.
  ///
  /// Deliberately short. A long brand list is a maintenance burden that decays
  /// into false positives — and the structural checks above catch the general
  /// case without knowing any brand at all. These are here because
  /// credential-phishing concentrates overwhelmingly on a handful of targets,
  /// and because this product's own domain belongs on any such list.
  static const _protectedDomains = <String>{
    'google.com',
    'gmail.com',
    'apple.com',
    'icloud.com',
    'microsoft.com',
    'outlook.com',
    'facebook.com',
    'instagram.com',
    'whatsapp.com',
    'telegram.org',
    'paypal.com',
    'ironlink.app',
  };

  /// Words that make a page a credential target rather than a page.
  static const _loginWords = <String>{
    'login', 'signin', 'sign-in', 'account', 'verify', 'password',
    'secure', 'auth', 'wallet', 'recover', 'unlock', 'confirm',
  };

  /// Analyses one URL. Never touches the network.
  LinkVerdict inspect(String raw) {
    final findings = <LinkFinding>[];

    final url = raw.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      // Not a URL this can reason about. Silence rather than a guess — a
      // finding on something that is not a link is pure noise.
      return LinkVerdict(url: url, findings: const []);
    }

    // Dart percent-encodes non-ASCII hosts rather than punycoding them, so
    // "pаypal.com" arrives here as "p%D0%B0ypal.com" and every character looks
    // like ASCII. Decoding first is what makes the homograph check possible at
    // all; without it this class silently passed its most important case.
    final host = _decodeHost(uri.host).toLowerCase();

    // Everything before an @ in the authority is credentials, and the browser
    // ignores it when deciding where to go.
    if (uri.userInfo.isNotEmpty) {
      findings.add(LinkFinding(LinkRisk.credentialsInUrl, detail: host));
    }

    if (_isIpLiteral(host)) {
      findings.add(LinkFinding(LinkRisk.ipAddressHost, detail: host));
    }

    final mixedIn = _mixedScript(host);
    if (mixedIn != null) {
      findings.add(LinkFinding(LinkRisk.mixedScriptDomain, detail: mixedIn));
    }

    if (host.contains('xn--')) {
      findings.add(const LinkFinding(LinkRisk.punycodeDomain));
    }

    final labels = host.split('.');
    if (labels.length > 4) {
      findings.add(LinkFinding(
        LinkRisk.excessiveSubdomains,
        detail: '${labels.length}',
      ));
    }

    final registrable = _registrableDomain(host);

    // A protected brand appearing anywhere *except* as the registrable domain
    // means the brand is a subdomain of somebody else's site.
    for (final brand in _protectedDomains) {
      final brandName = brand.split('.').first;
      final impersonates = labels.contains(brandName) ||
          host.contains('$brandName.') && registrable != brand;
      if (impersonates && registrable != brand) {
        findings.add(LinkFinding(LinkRisk.deceptiveSubdomain, detail: brand));
        break;
      }
    }

    // And a near-miss of a brand, which no subdomain check would catch.
    if (!_protectedDomains.contains(registrable)) {
      final lookalike = _nearestBrand(registrable);
      if (lookalike != null) {
        findings.add(LinkFinding(LinkRisk.lookalikeDomain, detail: lookalike));
      }
    }

    final looksLikeLogin = _loginWords.any(
      (w) => url.toLowerCase().contains(w),
    );
    if (looksLikeLogin && uri.scheme == 'http') {
      findings.add(LinkFinding(LinkRisk.insecureLoginPage, detail: host));
    }

    return LinkVerdict(url: url, findings: findings);
  }

  /// Every link in a body of text, analysed.
  ///
  /// Bounded at 20 because a message with a hundred links is either spam — in
  /// which case the first few already established it — or a paste, and the
  /// user is scrolling past either way.
  List<LinkVerdict> inspectAll(String text, {int max = 20}) {
    final matches = _urlPattern.allMatches(text).take(max);
    return [
      for (final m in matches) inspect(m.group(0)!),
    ];
  }

  static final _urlPattern = RegExp(
    r'\bhttps?://[^\s<>"' r"'" r']+',
    caseSensitive: false,
  );

  static bool _isIpLiteral(String host) {
    if (host.startsWith('[')) return true; // IPv6 literal
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static String _decodeHost(String host) {
    try {
      return Uri.decodeComponent(host);
    } catch (_) {
      // Malformed escapes. Analysing the raw form is worse than useless, so
      // this returns it unchanged and the other checks carry the weight.
      return host;
    }
  }

  /// The script mixed into a single domain label, if any.
  ///
  /// This is the check that earns its place. "pаypal.com" with a Cyrillic а is
  /// indistinguishable by eye at any font size, and no amount of user care
  /// defeats it — but the codepoints say so immediately.
  ///
  /// Per *label*, not per host, and that distinction is the whole accuracy of
  /// it. Every internationalised domain has a Latin TLD — "مثال.example" is a
  /// perfectly ordinary Arabic-web address — so a whole-host comparison would
  /// flag the entire non-Latin internet. What is never legitimate is one label
  /// containing two scripts, because that combination exists to be misread.
  static String? _mixedScript(String host) {
    for (final label in host.split('.')) {
      var hasLatin = false;
      String? foreign;

      for (final rune in label.runes) {
        if ((rune >= 0x61 && rune <= 0x7A) || (rune >= 0x41 && rune <= 0x5A)) {
          hasLatin = true;
          continue;
        }
        if (rune < 0x80) continue; // digits, hyphens

        if (rune >= 0x0400 && rune <= 0x04FF) {
          foreign ??= 'Cyrillic';
        } else if (rune >= 0x0370 && rune <= 0x03FF) {
          foreign ??= 'Greek';
        } else if (rune >= 0x0600 && rune <= 0x06FF) {
          foreign ??= 'Arabic';
        } else {
          foreign ??= 'non-Latin';
        }
      }

      if (hasLatin && foreign != null) return foreign;
    }
    return null;
  }

  /// The last two labels. Not a public-suffix implementation — that needs a
  /// list this cannot ship without also shipping its staleness — so
  /// `example.co.uk` reads as `co.uk`. Stated rather than hidden, because it
  /// is why the brand checks favour false negatives.
  static String _registrableDomain(String host) {
    final labels = host.split('.').where((l) => l.isNotEmpty).toList();
    if (labels.length < 2) return host;
    return labels.sublist(labels.length - 2).join('.');
  }

  /// A protected domain one small edit away from this one.
  ///
  /// Edit distance of one, and only for names long enough that one substitution
  /// is unlikely to be coincidence — the same length floor the keyword matcher
  /// uses, for the same reason.
  static String? _nearestBrand(String registrable) {
    final name = registrable.split('.').first;
    if (name.length < 5) return null;

    for (final brand in _protectedDomains) {
      final brandName = brand.split('.').first;
      if (brandName == name) continue;
      if ((brandName.length - name.length).abs() > 1) continue;
      if (_withinOneEdit(brandName, name)) return brand;
    }
    return null;
  }

  static bool _withinOneEdit(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;

    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (b.length > a.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}
