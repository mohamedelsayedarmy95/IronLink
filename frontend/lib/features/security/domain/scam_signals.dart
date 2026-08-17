/// IronShield — scam and impersonation signals, on this device only.
///
/// THE DANGER OF BUILDING THIS AT ALL
///
/// A scam detector that fires on ordinary conversation is worse than no scam
/// detector. Every false positive spends the user's trust, and once they have
/// learned to dismiss the banner, the one real warning is dismissed with it.
/// The failure that matters here is not a missed scam; it is a warning nobody
/// reads any more.
///
/// So this is built to under-fire. A single signal never warns. Two must agree,
/// and the combinations that count are the ones that are individually innocent
/// and jointly diagnostic: urgency alone is a busy colleague, a payment request
/// alone is a friend splitting a bill, but urgency *plus* a payment request
/// *plus* a lookalike link is a pattern with one meaning.
///
/// IT NEVER BLOCKS AND NEVER REPORTS
///
/// Analysis happens on decrypted text on the device, and nothing about it
/// leaves — no telemetry counting how often it fires, no sample of what
/// triggered it. The specification's privacy boundary for this capability is
/// the words "on-device only", and a metric that reported "a payment-scam
/// pattern matched" would still be reporting on the content of a message the
/// server is not allowed to read.
///
/// WHY THE PATTERNS ARE BILINGUAL
///
/// This product's primary language is Arabic. A scam detector that only reads
/// English protects the wrong users — and worse, it protects them selectively,
/// which is how a security feature becomes a false assurance.
library;

import 'link_safety.dart';

enum ScamSignal {
  /// "Send me the code", "what was the number you got". The single most
  /// common account-takeover vector against a messenger that sends OTPs, and
  /// the one signal here that is close to diagnostic on its own.
  credentialRequest,

  /// Pressure: "immediately", "within an hour", "before it is closed".
  urgency,

  /// A request to move money or send a transfer.
  paymentRequest,

  /// Claiming to be support, an official account, or an authority.
  authorityClaim,

  /// A link this device already judged deceptive.
  suspiciousLink,

  /// A request to move the conversation somewhere unencrypted.
  offPlatformMove,
}

class ScamAssessment {
  const ScamAssessment({required this.signals, required this.linkVerdicts});

  final Set<ScamSignal> signals;
  final List<LinkVerdict> linkVerdicts;

  /// Whether the user should be told.
  ///
  /// A credential request warns alone, because "send me the code you just
  /// received" has no innocent reading in a chat app that sends codes.
  /// Everything else needs corroboration.
  bool get shouldWarn =>
      signals.contains(ScamSignal.credentialRequest) || signals.length >= 2;

  /// The signal to lead with, so the explanation names the most specific thing
  /// found rather than the first one detected.
  ScamSignal? get primary {
    for (final s in const [
      ScamSignal.credentialRequest,
      ScamSignal.suspiciousLink,
      ScamSignal.paymentRequest,
      ScamSignal.authorityClaim,
      ScamSignal.offPlatformMove,
      ScamSignal.urgency,
    ]) {
      if (signals.contains(s)) return s;
    }
    return null;
  }
}

class ScamIntelligence {
  const ScamIntelligence({this.linkSafety = const LinkSafety()});

  final LinkSafety linkSafety;

  /// Assesses one message. Pure function of its text; touches nothing.
  ScamAssessment assess(String text) {
    final lower = text.toLowerCase();
    final signals = <ScamSignal>{};

    if (_matchesAny(lower, _credentialPatterns)) {
      signals.add(ScamSignal.credentialRequest);
    }
    if (_matchesAny(lower, _urgencyPatterns)) {
      signals.add(ScamSignal.urgency);
    }
    if (_matchesAny(lower, _paymentPatterns)) {
      signals.add(ScamSignal.paymentRequest);
    }
    if (_matchesAny(lower, _authorityPatterns)) {
      signals.add(ScamSignal.authorityClaim);
    }
    if (_matchesAny(lower, _offPlatformPatterns)) {
      signals.add(ScamSignal.offPlatformMove);
    }

    final verdicts = linkSafety.inspectAll(text);
    if (verdicts.any((v) => v.shouldWarn)) {
      signals.add(ScamSignal.suspiciousLink);
    }

    return ScamAssessment(signals: signals, linkVerdicts: verdicts);
  }

  static bool _matchesAny(String text, List<RegExp> patterns) =>
      patterns.any((p) => p.hasMatch(text));

  /// Asking for a code, a password, or a one-time number.
  ///
  /// The Arabic side matters more than the English here: "ابعتلي الكود" is how
  /// this attack actually arrives for this product's users.
  static final _credentialPatterns = <RegExp>[
    // The negative lookahead is not decoration. "what is the code review
    // process" is an ordinary sentence in an engineering chat, and without it
    // this pattern warns on it — a false positive on the exact signal that is
    // allowed to warn alone, which is the worst place to have one.
    RegExp(r'\b(send|share|give|tell)\s+(me\s+)?(the\s+)?(code|otp|pin|password)\b(?!\s+(review|base))'),
    RegExp(r'\b(what|whats|what.s)\s+(is\s+|was\s+)?(the\s+)?(code|otp|pin)\b(?!\s+(review|base))'),
    RegExp(r'\bverification\s+code\b'),
    RegExp(r'ابعت.{0,12}(الكود|الرقم|كلمة السر|الباسورد)'),
    RegExp(r'(ايه|إيه|ما هو).{0,12}(الكود|الرقم السري)'),
    RegExp(r'كود التحقق'),
    RegExp(r'الرمز.{0,10}(اللي|الذي).{0,12}(وصل|جاك|استلمت)'),
  ];

  static final _urgencyPatterns = <RegExp>[
    // "urgently" is far commoner than "urgent" as a bare word, and \b after
    // "urgent" excluded it.
    RegExp(r'\b(urgent(ly)?|immediately|right now|asap|within \d+ (minute|hour))\b'),
    RegExp(r'\b(account|access) will be (closed|blocked|suspended|deleted)\b'),
    RegExp(r'\blast (chance|warning)\b'),
    RegExp(r'(بسرعة|فورا|فوراً|حالا|حالاً|ضروري جدا)'),
    RegExp(r'(هيتقفل|سيتم إغلاق|هيتم حظر|خلال ساعة|آخر تحذير)'),
  ];

  static final _paymentPatterns = <RegExp>[
    RegExp(r'\b(transfer|send|wire)\s+(me\s+)?(the\s+)?(money|amount|\$|\d+)'),
    RegExp(r'\b(bank|iban|wallet)\s+(account|number|address)\b'),
    RegExp(r'\b(pay|payment|fee|deposit)\s+(now|first|in advance)\b'),
    RegExp(r'(حول|حوّل|ابعت).{0,15}(فلوس|مبلغ|جنيه|دولار|ريال)'),
    RegExp(r'(رقم|حساب).{0,10}(البنك|المحفظة|الايبان|الآيبان)'),
    RegExp(r'(ادفع|الدفع).{0,12}(مقدم|الأول|دلوقتي)'),
  ];

  static final _authorityPatterns = <RegExp>[
    RegExp(r'\b(this is|i.m from)\s+(the\s+)?(support|security|admin|bank)\b'),
    RegExp(r'\b(official|verified)\s+(account|support|team)\b'),
    RegExp(r'(انا|أنا)\s*(من)?\s*(الدعم|الأمن|الإدارة|البنك)'),
    RegExp(r'(الحساب|الفريق)\s*(الرسمي|الموثق)'),
  ];

  static final _offPlatformPatterns = <RegExp>[
    RegExp(r'\b(contact|message|write to) (me|us) on (whatsapp|telegram|sms)\b'),
    RegExp(r'\b(continue|talk) (this )?(on|via) (whatsapp|telegram|email)\b'),
    RegExp(r'(كلمني|راسلني|تواصل معايا).{0,15}(واتساب|تليجرام|رسالة)'),
  ];
}
