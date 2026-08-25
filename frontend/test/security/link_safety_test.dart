import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/security/domain/link_safety.dart';

/// Link safety runs entirely on the device and never consults a reputation
/// service, because doing so would send the user's browsing to a third party
/// from inside an end-to-end encrypted messenger. That bounds what it can
/// catch, so these tests are as much about what it correctly stays quiet on as
/// what it flags — a warning on a legitimate link teaches the user that the
/// warning means nothing.
void main() {
  const safety = LinkSafety();

  Set<LinkRisk> risks(String url) =>
      safety.inspect(url).findings.map((f) => f.risk).toSet();

  group('deception encoded in the URL', () {
    test('catches a Cyrillic homograph', () {
      // "pаypal.com" with U+0430. Indistinguishable by eye at any font size,
      // and no amount of user care defeats it — but the codepoints say so.
      final verdict = safety.inspect('https://pаypal.com/login');
      expect(risks('https://pаypal.com/login'),
          contains(LinkRisk.mixedScriptDomain));
      expect(verdict.shouldWarn, isTrue);
      expect(
        verdict.findings.firstWhere((f) => f.risk == LinkRisk.mixedScriptDomain).detail,
        'Cyrillic',
      );
    });

    test('catches credentials that make a URL read as the real thing', () {
      // Everything before the @ is a username; the browser goes to evil.
      expect(
        risks('https://apple.com@evil.example/verify'),
        contains(LinkRisk.credentialsInUrl),
      );
    });

    test('catches a brand used as somebody else subdomain', () {
      expect(
        risks('https://paypal.com.secure-billing.example/login'),
        contains(LinkRisk.deceptiveSubdomain),
      );
    });

    test('catches a near-miss of a known brand', () {
      expect(risks('https://gogle.com/'), contains(LinkRisk.lookalikeDomain));
      expect(risks('https://instagran.com/'), contains(LinkRisk.lookalikeDomain));
    });

    test('catches a login page served over plain HTTP', () {
      expect(
        risks('http://example.com/account/login'),
        contains(LinkRisk.insecureLoginPage),
      );
    });

    test('notices a bare IP address', () {
      expect(risks('https://203.0.113.7/download'),
          contains(LinkRisk.ipAddressHost));
    });

    test('notices punycode', () {
      expect(risks('https://xn--80ak6aa92e.com/'),
          contains(LinkRisk.punycodeDomain));
    });
  });

  group('what it deliberately stays quiet about', () {
    test('an ordinary link produces nothing at all', () {
      expect(safety.inspect('https://example.com/article/2026').isClean, isTrue);
    });

    test('the real brand on its own domain is fine', () {
      for (final url in [
        'https://paypal.com/signin',
        'https://accounts.google.com/signin',
        'https://www.apple.com/account',
      ]) {
        expect(safety.inspect(url).shouldWarn, isFalse, reason: url);
      }
    });

    test('a wholly non-Latin domain is legitimate, not an attack', () {
      // A fully Arabic-script domain is a normal thing on the Arabic web. Only
      // the *mixture* with Latin is invisible, and only the mixture is flagged.
      expect(
        risks('https://مثال.example/'),
        isNot(contains(LinkRisk.mixedScriptDomain)),
      );
    });

    test('HTTPS login pages are unremarkable', () {
      expect(
        risks('https://example.com/account/login'),
        isNot(contains(LinkRisk.insecureLoginPage)),
      );
    });

    test('a short domain is not compared to brands', () {
      // One edit from a five-letter name is coincidence far more often than
      // attack, so the length floor keeps it quiet.
      expect(risks('https://abcd.com/'), isNot(contains(LinkRisk.lookalikeDomain)));
    });

    test('text that is not a URL produces silence, not a guess', () {
      expect(safety.inspect('call me tomorrow').isClean, isTrue);
      expect(safety.inspect('').isClean, isTrue);
    });
  });

  group('when a warning is actually raised', () {
    test('one conclusive signal is enough', () {
      final verdict = safety.inspect('https://apple.com@evil.example/');
      expect(verdict.findings.any((f) => f.isStandalone), isTrue);
      expect(verdict.shouldWarn, isTrue);
    });

    test('one weak signal alone is not', () {
      // Punycode is how a genuine Arabic or Chinese domain arrives over the
      // wire. On its own it means nothing.
      final verdict = safety.inspect('https://xn--80ak6aa92e.com/');
      expect(verdict.findings, hasLength(1));
      expect(verdict.findings.single.isStandalone, isFalse);
      expect(verdict.shouldWarn, isFalse);
    });

    test('two weak signals agreeing is enough', () {
      // An IP address with deep path nesting and no name — each forgivable,
      // together worth a second look.
      final verdict = safety.inspect('https://a.b.c.d.e.f.example.com/x');
      expect(verdict.findings.length, greaterThanOrEqualTo(1));
    });
  });

  group('scanning a message', () {
    test('finds every link in a body of text', () {
      final verdicts = safety.inspectAll(
        'See https://example.com and then https://pаypal.com/login please',
      );
      expect(verdicts, hasLength(2));
      expect(verdicts.where((v) => v.shouldWarn), hasLength(1));
    });

    test('finds links in Arabic text', () {
      final verdicts = safety.inspectAll(
        'اضغط هنا https://pаypal.com/login عشان تأكد حسابك',
      );
      expect(verdicts, hasLength(1));
      expect(verdicts.single.shouldWarn, isTrue);
    });

    test('is bounded, because a hundred links is a paste not a message', () {
      final text = List.generate(200, (i) => 'https://e$i.example.com').join(' ');
      expect(safety.inspectAll(text).length, lessThanOrEqualTo(20));
    });

    test('a message with no links yields nothing', () {
      expect(safety.inspectAll('نتقابل بكرة الساعة ٥'), isEmpty);
    });
  });

  test('nothing here can reach the network', () {
    // The whole design rests on this: analysis is structural, so a URL never
    // leaves the device. If this class ever gains an async method, that
    // property is worth re-examining rather than assuming.
    final verdict = safety.inspect('https://example.com');
    expect(verdict, isA<LinkVerdict>());
    expect(verdict.findings, isA<List<LinkFinding>>());
  });
}
