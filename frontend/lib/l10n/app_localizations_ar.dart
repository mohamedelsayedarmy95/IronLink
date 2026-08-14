// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class LAr extends L {
  LAr([String locale = 'ar']) : super(locale);

  @override
  String get authTagline => 'خاص · آمن · بلا حدود';

  @override
  String get authSubtitle => 'منظومة التراسل المؤمَّنة';

  @override
  String get featureE2EE => 'تشفير من طرف لطرف';

  @override
  String get featureVerifiedIdentity => 'هوية موثقة';

  @override
  String get featurePrivacyByDesign => 'خصوصية بالتصميم';

  @override
  String get featureDeviceSecurity => 'أمان على كل جهاز';

  @override
  String get getStarted => 'ابدأ الآن';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟ ';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get devGuestLogin => 'دخول تجريبي بدون سيرفر';

  @override
  String get secureSignInTitle => 'تسجيل الدخول الآمن';

  @override
  String get phoneStepSubtitle => 'أدخل رقم هاتفك المسجل لدى الوحدة';

  @override
  String get otpStepSubtitle => 'أدخل رمز التحقق المرسل إليك عبر رسالة نصية';

  @override
  String get militaryIdStepSubtitle => 'أدخل رقمك العسكري لإتمام التحقق';

  @override
  String get phoneNumberLabel => 'رقم الهاتف';

  @override
  String get otpCodeLabel => 'رمز التحقق';

  @override
  String get sendVerificationCode => 'إرسال رمز التحقق';

  @override
  String get resendCode => 'إعادة إرسال الرمز';

  @override
  String resendCodeCountdown(int seconds) {
    return 'إعادة الإرسال بعد $seconds ثانية';
  }

  @override
  String get militaryIdHint => 'الرقم العسكري';

  @override
  String get showPassword => 'إظهار';

  @override
  String get hidePassword => 'إخفاء';

  @override
  String get confirmSignIn => 'تأكيد الدخول';

  @override
  String get errorFirebaseTokenFailed =>
      'تعذر الحصول على رمز التحقق من Firebase';

  @override
  String get errorNetwork => 'تعذر الاتصال بالخادم — تحقق من الشبكة';

  @override
  String get errorUnexpected => 'حدث خطأ غير متوقع';

  @override
  String get errorInvalidPhone => 'رقم الهاتف غير صالح';

  @override
  String get errorTooManyRequests => 'محاولات كثيرة جدًا — حاول لاحقًا';

  @override
  String get errorInvalidCode => 'رمز التحقق غير صحيح';

  @override
  String get errorSessionExpired => 'انتهت صلاحية الرمز — أعد الإرسال';

  @override
  String get errorPhoneVerificationFailed => 'حدث خطأ أثناء التحقق من الهاتف';

  @override
  String get noChatsYet => 'لا توجد محادثات بعد';

  @override
  String get onlineNow => 'متصل الآن';

  @override
  String get startSecretChat => 'بدء محادثة سرية';

  @override
  String get secretChatComingSoon =>
      'تم تفعيل المحادثة السرية (سيتم تطبيقها في التحديث التالي)';

  @override
  String get messageDeleted => 'تم حذف هذه الرسالة';

  @override
  String get translate => 'ترجمة';

  @override
  String get reportMessage => 'إبلاغ عن رسالة';

  @override
  String get deleteForEveryone => 'حذف لدى الجميع';

  @override
  String get deleteForEveryoneHint => 'متاح خلال 5 دقائق من الإرسال';

  @override
  String typingIndicator(String name) {
    return '$name يكتب';
  }

  @override
  String get attach => 'إرفاق';

  @override
  String get messageHint => 'اكتب رسالة…';

  @override
  String get send => 'إرسال';

  @override
  String get notInAnyGroupYet => 'لست عضواً في أي مجموعة بعد';

  @override
  String groupMembersTitle(String name, int count) {
    return '$name — $count عضو';
  }

  @override
  String get announcementChannelReadOnly => 'قناة إعلانات — للقراءة فقط';

  @override
  String memberCount(int count) {
    return '$count عضو';
  }

  @override
  String get roleOwner => 'مالك المجموعة';

  @override
  String get roleAdmin => 'مشرف';

  @override
  String get roleModerator => 'منسق';

  @override
  String get roleObserver => 'مراقب — قراءة فقط';

  @override
  String get roleMember => 'عضو';

  @override
  String get channelsTitle => 'القنوات';

  @override
  String get createChannel => 'إنشاء قناة';

  @override
  String get noChannelsYet => 'لا توجد قنوات بعد';

  @override
  String subscriberCount(int count) {
    return '$count مشترك';
  }

  @override
  String get ocrKeywordsTitle => 'كلمات المسح الضوئي المفتاحية (OCR)';

  @override
  String get ocrKeywordsDescription =>
      'يتم تنبيهك تلقائيًا إذا ظهرت أي من هذه الكلمات في نص ممسوح ضوئيًا (OCR) داخل صورة أو مستند.';

  @override
  String get newKeywordLabel => 'كلمة مفتاحية جديدة';

  @override
  String get newKeywordHint => 'اكتب كلمة وأضفها';

  @override
  String get noKeywordsYet => 'لا توجد كلمات مفتاحية بعد';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get delete => 'حذف';

  @override
  String ocrLoadFailed(String error) {
    return 'تعذّر تحميل الكلمات المفتاحية: $error';
  }

  @override
  String ocrAddFailed(String error) {
    return 'تعذّرت إضافة الكلمة: $error';
  }

  @override
  String ocrRemoveFailed(String error) {
    return 'تعذّر حذف الكلمة: $error';
  }

  @override
  String get tabChats => 'المحادثات';

  @override
  String get tabGroups => 'المجموعات';

  @override
  String get tabBroadcasts => 'التعميمات';

  @override
  String get tabSettings => 'الإعدادات';

  @override
  String get comingSoon => 'قريباً';

  @override
  String get releaseToCancel => 'اترك للإلغاء';

  @override
  String get dragToCancel => '← اسحب للإلغاء';

  @override
  String get voiceUploadFailed => 'فشل رفع التسجيل الصوتي';

  @override
  String get acknowledged => 'علمت';
}
