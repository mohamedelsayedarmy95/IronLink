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
  String get e2eeNotice =>
      'بياناتك مشفّرة من طرف لطرف ولا يمكن للخادم قراءتها.';

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
  String get noChatsYetHint => 'ابدأ محادثة مؤمَّنة مع أحد جهات اتصالك.';

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
  String get notInAnyGroupYetHint =>
      'أنشئ مجموعة أو انضم إلى واحدة للتنسيق مع فريقك.';

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
  String get noChannelsYetHint => 'اشترك في قناة لتصلك الإعلانات الرسمية.';

  @override
  String get channelsLoadFailedTitle => 'تعذّر تحميل القنوات';

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
  String get add => 'إضافة';

  @override
  String get ocrKeywordExists => 'هذه الكلمة مُضافة بالفعل.';

  @override
  String get ocrKeywordsEmptyHint =>
      'أضف كلمة ليتم تنبيهك عند ظهورها في أي صورة أو مستند ممسوح ضوئيًا.';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get delete => 'حذف';

  @override
  String get ocrLoadFailedTitle => 'تعذّر تحميل الكلمات';

  @override
  String get ocrAddFailed => 'لم تُضَف الكلمة. حاول مرة أخرى.';

  @override
  String get ocrRemoveFailed => 'لم تُحذَف الكلمة. حاول مرة أخرى.';

  @override
  String get failureOffline =>
      'لا يوجد اتصال بالإنترنت. تحقّق من الشبكة ثم أعد المحاولة.';

  @override
  String get failureTimeout =>
      'الخادم يستغرق وقتًا أطول من المعتاد. أعد المحاولة بعد قليل.';

  @override
  String get failureServer =>
      'تعذّر الوصول إلى الخادم حاليًا. أعد المحاولة بعد قليل.';

  @override
  String get failureUnauthorized => 'انتهت صلاحية جلستك. سجّل الدخول مرة أخرى.';

  @override
  String get failureRejected =>
      'تعذّر إتمام الطلب. راجع البيانات وحاول مرة أخرى.';

  @override
  String get failureInsecure =>
      'تعذّر التحقّق من أمان الاتصال. لم تُرسَل أي بيانات.';

  @override
  String get failureUnknown => 'حدث خطأ غير متوقّع. أعد المحاولة.';

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
  String get uploadFailed => 'تعذّر رفع المرفق. حاول مرة أخرى.';

  @override
  String get attachGallery => 'المعرض';

  @override
  String get attachCamera => 'الكاميرا';

  @override
  String get attachDocument => 'مستند PDF';

  @override
  String get attachPdfComingSoon => 'اختيار ملفات PDF غير متاح بعد.';

  @override
  String get captionHint => 'أضف تعليقًا…';

  @override
  String ocrAlertFound(String keyword) {
    return 'رُصدت الكلمة \"$keyword\" في ملف مرفوع.';
  }

  @override
  String get acknowledged => 'علمت';

  @override
  String get completeVerificationForm => 'استكمال نموذج التحقق';

  @override
  String joinRequestFor(String group) {
    return 'طلب انضمام: $group';
  }

  @override
  String get completeFormBelow => 'يرجى استكمال النموذج أدناه.';

  @override
  String get submitRequest => 'إرسال الطلب';

  @override
  String get resubmit => 'إعادة الإرسال';

  @override
  String get requestToJoin => 'طلب الانضمام';

  @override
  String get cancelRequest => 'إلغاء الطلب';

  @override
  String get requestAgain => 'إعادة الطلب';

  @override
  String requiredFieldsProgress(int filled, int total) {
    return '$filled من $total حقول مطلوبة مكتملة';
  }

  @override
  String get draftRestored => 'تم استرجاع إجاباتك السابقة';

  @override
  String get formAnswersEncrypted => 'إجاباتك مشفّرة أثناء النقل وعند التخزين.';

  @override
  String get formLoadFailedTitle => 'تعذّر تحميل النموذج';

  @override
  String get noFormRequired => 'لا يوجد نموذج مطلوب';

  @override
  String get noFormRequiredHint =>
      'هذه المجموعة لا تطلب أي معلومات إضافية. أرسل طلبك مباشرة.';

  @override
  String get selectAnOption => 'اختر خيارًا';

  @override
  String get selectADate => 'اختر تاريخًا';

  @override
  String get noFileSelected => 'لم يتم اختيار ملف';

  @override
  String get fieldTypeUnsupported =>
      'هذا الحقل غير مدعوم في هذا الإصدار. حدّث التطبيق لإكماله.';

  @override
  String get statusPending => 'قيد المراجعة';

  @override
  String get statusApproved => 'تمت الموافقة';

  @override
  String get statusRejected => 'مرفوض';

  @override
  String get statusMoreInfo => 'بحاجة لمعلومات';

  @override
  String get statusExpired => 'منتهي';

  @override
  String get joinRequestsTitle => 'طلبات الانضمام';

  @override
  String get tabPending => 'معلّقة';

  @override
  String get tabExpired => 'منتهية';

  @override
  String get tabHistory => 'السجل';

  @override
  String get select => 'تحديد';

  @override
  String get cancel => 'إلغاء';

  @override
  String get approve => 'موافقة';

  @override
  String get reject => 'رفض';

  @override
  String get approveAll => 'قبول الكل';

  @override
  String get rejectAll => 'رفض الكل';

  @override
  String approveSelected(int count) {
    return 'قبول ($count)';
  }

  @override
  String rejectSelected(int count) {
    return 'رفض ($count)';
  }

  @override
  String get approveAllTitle => 'قبول جميع الطلبات';

  @override
  String get rejectAllTitle => 'رفض جميع الطلبات';

  @override
  String approveAllConfirm(int count) {
    return 'هل أنت متأكد أنك تريد قبول جميع الطلبات المعلّقة وعددها $count؟';
  }

  @override
  String rejectAllConfirm(int count) {
    return 'هل أنت متأكد أنك تريد رفض جميع الطلبات المعلّقة وعددها $count؟ لا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String bulkResult(int count) {
    return 'تمت المعالجة بنجاح لـ $count طلب';
  }

  @override
  String get rejectRequestTitle => 'رفض الطلب';

  @override
  String get rejectionReasonOptional => 'سبب الرفض (اختياري)';

  @override
  String get rejectionReasonLabel => 'سبب الرفض';

  @override
  String get noAnswersSubmitted => 'لم تُقدَّم أي إجابات';

  @override
  String get requestsLoadFailedTitle => 'تعذّر تحميل الطلبات';

  @override
  String get noPendingRequests => 'لا توجد طلبات انضمام معلّقة';

  @override
  String get noPendingRequestsHint =>
      'مجموعتك آمنة. ستظهر الطلبات الجديدة هنا.';

  @override
  String get nothingHere => 'لا يوجد شيء هنا';

  @override
  String get nothingHereHint => 'لا توجد طلبات بهذه الحالة بعد.';

  @override
  String minutesAgo(int count) {
    return 'منذ $count دقيقة';
  }

  @override
  String hoursAgo(int count) {
    return 'منذ $count ساعة';
  }

  @override
  String daysAgo(int count) {
    return 'منذ $count يوم';
  }
}
