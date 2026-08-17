import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/security/domain/scam_signals.dart';

/// A scam detector that fires on ordinary conversation is worse than none:
/// every false positive spends trust, and once the banner is learned as noise
/// the one real warning goes with it.
///
/// So the larger half of this file is ordinary messages that must produce
/// silence. If a change makes the detector cleverer and breaks those, the
/// change is wrong.
void main() {
  const scam = ScamIntelligence();

  Set<ScamSignal> signals(String text) => scam.assess(text).signals;
  bool warns(String text) => scam.assess(text).shouldWarn;

  group('ordinary messages must produce silence', () {
    const innocent = [
      // English
      'can you send me the file when you get a chance',
      'transfer is done, thanks',
      'I am from the Cairo office, we met last week',
      'this is urgent, the client is waiting on the deck',
      'what is the code review process here?',
      'pay you back tomorrow for lunch',
      'message me on here whenever',
      // Arabic
      'ابعتلي الملف لما تفضى',
      'حولت الفلوس امبارح',
      'انا من مكتب القاهرة، اتقابلنا الاسبوع اللي فات',
      'الموضوع ضروري، العميل مستني',
      'هدفعلك بكرة بدل الغدا',
      'كلمني بكرة الصبح',
    ];

    for (final message in innocent) {
      test('silent on: "$message"', () {
        expect(warns(message), isFalse, reason: message);
      });
    }
  });

  group('the one signal that warns alone', () {
    test('asking for a verification code, in English', () {
      // No innocent reading in a chat app that sends codes.
      expect(warns('hey send me the code you just got'), isTrue);
      expect(signals('what is the otp?'),
          contains(ScamSignal.credentialRequest));
    });

    test('asking for a verification code, in Arabic', () {
      // This is how the attack actually arrives for this product's users, so
      // it matters more than the English side.
      expect(warns('ابعتلي الكود اللي وصلك حالا'), isTrue);
      expect(signals('ايه الكود اللي جالك؟'),
          contains(ScamSignal.credentialRequest));
      expect(warns('محتاج كود التحقق ضروري'), isTrue);
    });

    test('a code request is enough on its own', () {
      final assessment = scam.assess('send me the code');
      expect(assessment.signals, hasLength(1));
      expect(assessment.shouldWarn, isTrue);
    });
  });

  group('everything else needs corroboration', () {
    test('urgency alone is a busy colleague', () {
      expect(signals('need this urgently'), contains(ScamSignal.urgency));
      expect(warns('need this urgently'), isFalse);
    });

    test('a payment request alone is a friend splitting a bill', () {
      final s = signals('can you transfer me 200');
      expect(s, contains(ScamSignal.paymentRequest));
      expect(warns('can you transfer me 200'), isFalse);
    });

    test('claiming to be support alone is not enough', () {
      expect(warns('this is the support team following up'), isFalse);
    });

    test('but urgency plus payment is a pattern', () {
      expect(
        warns('urgent — transfer the amount immediately before it is closed'),
        isTrue,
      );
    });

    test('and it works in Arabic too', () {
      expect(
        warns('ضروري جدا حوّل المبلغ بسرعة قبل ما الحساب يتقفل'),
        isTrue,
      );
    });

    test('authority plus payment is a pattern', () {
      expect(
        warns('انا من البنك، محتاج رقم الحساب عشان نحول المبلغ'),
        isTrue,
      );
    });
  });

  group('links feed into the assessment', () {
    test('a deceptive link is a signal', () {
      final s = signals('check https://apple.com@evil.example/verify');
      expect(s, contains(ScamSignal.suspiciousLink));
    });

    test('a deceptive link plus urgency warns', () {
      expect(
        warns('urgent: verify at https://pаypal.com/login right now'),
        isTrue,
      );
    });

    test('an ordinary link contributes nothing', () {
      expect(
        signals('here it is https://example.com/report'),
        isNot(contains(ScamSignal.suspiciousLink)),
      );
    });

    test('the verdicts are exposed so the UI can explain which link', () {
      final assessment =
          scam.assess('see https://example.com and https://pаypal.com/login');
      expect(assessment.linkVerdicts, hasLength(2));
      expect(assessment.linkVerdicts.where((v) => v.shouldWarn), hasLength(1));
    });
  });

  group('the explanation names the most specific thing found', () {
    test('a code request leads over urgency', () {
      final assessment = scam.assess('urgent! send me the code now');
      expect(assessment.primary, ScamSignal.credentialRequest);
    });

    test('a bad link leads over a payment request', () {
      final assessment = scam.assess(
        'transfer the money at https://apple.com@evil.example/pay',
      );
      expect(assessment.primary, ScamSignal.suspiciousLink);
    });

    test('nothing found means nothing to lead with', () {
      expect(scam.assess('see you at 5').primary, isNull);
    });
  });

  group('off-platform moves', () {
    test('are noticed', () {
      expect(
        signals('contact me on whatsapp instead'),
        contains(ScamSignal.offPlatformMove),
      );
      expect(
        signals('كلمني على واتساب'),
        contains(ScamSignal.offPlatformMove),
      );
    });

    test('but do not warn alone — people move conversations legitimately', () {
      expect(warns('contact me on whatsapp instead'), isFalse);
    });
  });

  test('an empty message is silent', () {
    expect(warns(''), isFalse);
    expect(scam.assess('').signals, isEmpty);
  });

  test('assessment is a pure function of the text', () {
    // No network, no storage, no counters. The specification's privacy
    // boundary for this capability is the phrase "on-device only", and even a
    // metric saying "a payment-scam pattern matched" would report on the
    // content of a message the server may not read.
    final a = scam.assess('send me the code');
    final b = scam.assess('send me the code');
    expect(a.signals, b.signals);
  });
}
