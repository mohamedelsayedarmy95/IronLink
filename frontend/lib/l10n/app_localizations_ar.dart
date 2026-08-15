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

  @override
  String get entrySettingsTitle => 'إعدادات الانضمام';

  @override
  String get joinModeSection => 'طريقة الانضمام';

  @override
  String get modeOpen => 'مفتوحة';

  @override
  String get modeOpenHint => 'أي شخص ينضم فورًا بدون موافقة.';

  @override
  String get modeInviteOnly => 'بالدعوة فقط';

  @override
  String get modeInviteOnlyHint => 'لا يمكن الانضمام إلا عبر رابط دعوة.';

  @override
  String get modeRequestApproval => 'طلب وموافقة';

  @override
  String get modeRequestApprovalHint =>
      'يملأ المتقدّم نموذج تحقق وينتظر موافقة المشرف.';

  @override
  String get verificationFormSection => 'نموذج التحقق';

  @override
  String get noFormAttached => 'لا يوجد نموذج';

  @override
  String get noFormAttachedHint =>
      'المجموعة مغلقة لكنها لا تسأل أي شيء. أنشئ نموذجًا.';

  @override
  String fieldCount(int count) {
    return '$count حقل';
  }

  @override
  String get requestHandlingSection => 'معالجة الطلبات';

  @override
  String get requestExpiryTitle => 'انتهاء صلاحية الطلب';

  @override
  String get requestExpiryHint =>
      'الطلبات التي لا يُتخذ فيها قرار خلال هذه المدة تنتهي تلقائيًا.';

  @override
  String get expiryNever => 'بلا انتهاء';

  @override
  String expiryDays(int count) {
    return '$count يوم';
  }

  @override
  String get allowRejoinTitle => 'السماح بإعادة التقديم';

  @override
  String get allowRejoinHint => 'يمكن لمن رُفض طلبه تقديم طلب جديد.';

  @override
  String get saveChanges => 'حفظ التغييرات';

  @override
  String get settingsSaved => 'تم حفظ الإعدادات';

  @override
  String get formBuilderTitle => 'بنّاء النموذج';

  @override
  String get formBuilderEmptyTitle => 'لم تُضف أي حقول بعد';

  @override
  String get formBuilderEmptyHint =>
      'أضف الحقول التي يجب على المتقدّم استكمالها قبل الانضمام.';

  @override
  String get addField => 'إضافة حقل';

  @override
  String get saveAndActivate => 'حفظ وتفعيل';

  @override
  String get previewForm => 'معاينة';

  @override
  String get editForm => 'تحرير';

  @override
  String get previewNotice => 'هذا ما سيراه المتقدّم بالضبط.';

  @override
  String get formNameLabel => 'اسم النموذج';

  @override
  String get formNameHint => 'مثال: تحقق الوحدة';

  @override
  String get formNeedsName => 'أدخل اسمًا للنموذج';

  @override
  String get formNeedsFields => 'أضف حقلًا واحدًا على الأقل';

  @override
  String fieldNumber(int number) {
    return 'الحقل $number';
  }

  @override
  String get fieldNeedsLabel => 'هذا الحقل يحتاج عنوانًا';

  @override
  String get fieldNeedsOptions => 'أضف خيارًا واحدًا على الأقل';

  @override
  String get untitledField => 'حقل بلا عنوان';

  @override
  String get chooseFieldType => 'اختر نوع الحقل';

  @override
  String get fieldLabelLabel => 'السؤال';

  @override
  String get fieldLabelHint => 'مثال: الاسم الرباعي بالعربي';

  @override
  String get fieldPlaceholderLabel => 'نص توضيحي داخل الحقل (اختياري)';

  @override
  String get fieldHelperLabel => 'إرشاد أسفل الحقل (اختياري)';

  @override
  String get fieldRequiredLabel => 'حقل مطلوب';

  @override
  String get fieldOptionsLabel => 'الخيارات';

  @override
  String get addOptionHint => 'أضف خيارًا';

  @override
  String get optionExists => 'هذا الخيار موجود بالفعل';

  @override
  String get done => 'تم';

  @override
  String get fieldTypeTextShort => 'نص قصير';

  @override
  String get fieldTypeTextLong => 'نص طويل';

  @override
  String get fieldTypeNumber => 'رقم';

  @override
  String get fieldTypeSelectSingle => 'اختيار واحد';

  @override
  String get fieldTypeSelectMulti => 'اختيار متعدد';

  @override
  String get fieldTypeDate => 'تاريخ';

  @override
  String get fieldTypePhone => 'رقم هاتف';

  @override
  String get fieldTypeFile => 'ملف';

  @override
  String get fieldTypeImage => 'صورة';

  @override
  String get fieldTypeCheckbox => 'مربع اختيار';

  @override
  String get fieldTypeUrl => 'رابط';

  @override
  String get fieldTypeEmail => 'بريد إلكتروني';

  @override
  String get auditLogTitle => 'سجل التدقيق';

  @override
  String get auditLogEmpty => 'لم يُسجَّل أي نشاط بعد';

  @override
  String get auditLogEmptyHint =>
      'ستظهر هنا كل الإجراءات الحساسة على المجموعة.';

  @override
  String get auditLogLoadFailedTitle => 'تعذّر تحميل السجل';

  @override
  String get loadMore => 'تحميل المزيد';

  @override
  String get filterAll => 'الكل';

  @override
  String get filterApprovals => 'الموافقات';

  @override
  String get filterRejections => 'الرفض';

  @override
  String get filterBans => 'الحظر';

  @override
  String get filterSettings => 'الإعدادات';

  @override
  String get auditApproved => 'تمت الموافقة على طلب انضمام';

  @override
  String get auditRejected => 'تم رفض طلب انضمام';

  @override
  String get auditMoreInfo => 'طُلبت معلومات إضافية';

  @override
  String auditBulkApproved(int count) {
    return 'تمت الموافقة على $count طلب دفعة واحدة';
  }

  @override
  String auditBulkRejected(int count) {
    return 'تم رفض $count طلب دفعة واحدة';
  }

  @override
  String get auditBanned => 'تم حظر عضو';

  @override
  String get auditUnbanned => 'تم رفع الحظر عن عضو';

  @override
  String get auditRemoved => 'تمت إزالة عضو';

  @override
  String get auditJoinModeChanged => 'تم تغيير طريقة الانضمام';

  @override
  String get auditFormUpdated => 'تم تحديث نموذج التحقق';

  @override
  String get auditModeratorAssigned => 'تم تعيين منسق';

  @override
  String get auditReopened => 'تمت إعادة فتح طلب';

  @override
  String get auditExported => 'تم تصدير سجل التدقيق';

  @override
  String get uploading => 'جارٍ الرفع…';

  @override
  String get fileAttached => 'تم إرفاق ملف';

  @override
  String get choose => 'اختيار';

  @override
  String get replace => 'استبدال';

  @override
  String get amendRequest => 'تعديل الطلب';

  @override
  String get cancelRequestTitle => 'إلغاء الطلب';

  @override
  String get cancelRequestConfirm =>
      'سيُحذف طلبك وإجاباتك. يمكنك التقديم من جديد لاحقًا.';

  @override
  String get keepRequest => 'الإبقاء عليه';

  @override
  String get groupRequiresApproval =>
      'هذه المجموعة تتطلّب موافقة المشرف قبل الانضمام.';

  @override
  String get statusPendingBody => 'طلبك قيد المراجعة من قِبل المشرف.';

  @override
  String get statusApprovedBody =>
      'تمت الموافقة على طلبك! يمكنك الآن المشاركة في المجموعة.';

  @override
  String get statusRejectedBody => 'لم تتم الموافقة على طلبك.';

  @override
  String get statusMoreInfoBody =>
      'يحتاج المشرف إلى معلومات إضافية. يرجى تعديل طلبك.';

  @override
  String get statusExpiredBody => 'انتهت صلاحية طلبك. يمكنك تقديم طلب جديد.';

  @override
  String get contactsTitle => 'جهات الاتصال';

  @override
  String get findContactsTitle => 'اكتشاف جهات اتصالك';

  @override
  String get findContactsHeadline => 'اعثر على من تعرفهم';

  @override
  String get findContactsBody =>
      'نطابق دفتر عناوينك مع مستخدمي آيرون لينك، من غير ما نعرف أرقامك.';

  @override
  String get contactsPointHashedTitle => 'التجزئة تتم على جهازك';

  @override
  String get contactsPointHashedBody =>
      'كل رقم يتحوّل إلى بصمة مشفّرة قبل أن يغادر الهاتف.';

  @override
  String get contactsPointNoNumbersTitle => 'لا تُرسَل أرقام أبدًا';

  @override
  String get contactsPointNoNumbersBody =>
      'الخادم يستقبل بصمات فقط، ولا يمكنه استرجاع الرقم منها.';

  @override
  String get contactsPointReversibleTitle => 'قابل للتراجع في أي وقت';

  @override
  String get contactsPointReversibleBody =>
      'يمكنك حذف كل ما تم مطابقته بضغطة واحدة.';

  @override
  String get contactsDeniedHint =>
      'بدون الإذن لن نستطيع اقتراح من تعرفهم. يمكنك تفعيله لاحقًا من إعدادات النظام.';

  @override
  String get allowContactAccess => 'السماح بالوصول';

  @override
  String get notNow => 'ليس الآن';

  @override
  String get contactSyncOff => 'المزامنة غير مفعّلة';

  @override
  String get contactSyncOffHint => 'فعّلها لاكتشاف من تعرفهم على آيرون لينك.';

  @override
  String get enableContactSync => 'تفعيل المزامنة';

  @override
  String get syncNow => 'مزامنة الآن';

  @override
  String syncFoundNew(int count) {
    return 'تم العثور على $count جهة اتصال جديدة';
  }

  @override
  String get syncNoNewContacts => 'لا توجد جهات اتصال جديدة';

  @override
  String get noContactsFound => 'لم نجد أحدًا بعد';

  @override
  String get noContactsFoundHint =>
      'لا أحد من جهات اتصالك على آيرون لينك حاليًا.';

  @override
  String get contactsLoadFailedTitle => 'تعذّر تحميل جهات الاتصال';

  @override
  String onIronLink(int count) {
    return 'على آيرون لينك ($count)';
  }

  @override
  String get badgeNew => 'جديد';

  @override
  String get contactPrivacyTitle => 'خصوصية جهات الاتصال';

  @override
  String get whoCanFindMe => 'من يمكنه العثور عليّ برقم هاتفي';

  @override
  String get discoverEveryone => 'الجميع';

  @override
  String get discoverEveryoneHint => 'أي شخص لديه رقمك يمكنه اكتشافك.';

  @override
  String get discoverMutual => 'من أعرفهم فقط';

  @override
  String get discoverMutualHint => 'فقط من يظهر رقمك عندهم وتظهر أرقامهم عندك.';

  @override
  String get discoverNobody => 'لا أحد';

  @override
  String get discoverNobodyHint => 'لن يعثر عليك أحد عبر رقم هاتفك.';

  @override
  String storedHashesNotice(int count) {
    return 'نحتفظ بـ $count بصمة مشفّرة، بدون أي أرقام.';
  }

  @override
  String get deleteContactData => 'حذف بيانات جهات الاتصال';

  @override
  String get deleteContactDataTitle => 'حذف كل البيانات';

  @override
  String get deleteContactDataConfirm =>
      'سيتم حذف كل البصمات والمطابقات نهائيًا، وستختفي من قوائم اكتشاف الآخرين.';

  @override
  String get deleteEverything => 'حذف الكل';

  @override
  String get contactDataDeleted => 'تم حذف بيانات جهات الاتصال';

  @override
  String get blockUser => 'حظر المستخدم';

  @override
  String get unblockUser => 'إلغاء الحظر';

  @override
  String blockUserTitle(String name) {
    return 'حظر $name؟';
  }

  @override
  String get blockUserBody =>
      'لن يستطيع مراسلتك ولن تستطيع مراسلته. ولن يتم إبلاغه بأنك حظرته.';

  @override
  String get blockedUsers => 'المستخدمون المحظورون';

  @override
  String get blockedUsersEmpty => 'لم تحظر أحدًا';

  @override
  String get blockedUsersEmptyHint =>
      'من تحظرهم سيظهرون هنا، ويمكنك التراجع في أي وقت.';

  @override
  String blockedOn(String date) {
    return 'محظور منذ $date';
  }

  @override
  String userBlocked(String name) {
    return 'تم حظر $name';
  }

  @override
  String userUnblocked(String name) {
    return 'تم إلغاء حظر $name';
  }

  @override
  String get blockedBannerTitle => 'أنت حظرت هذا الشخص';

  @override
  String get blockedBannerBody => 'ألغِ الحظر لاستئناف إرسال واستقبال الرسائل.';

  @override
  String get reportUser => 'الإبلاغ عن المستخدم';

  @override
  String get reportTitle => 'إبلاغ';

  @override
  String get reportReasonQuestion => 'ما المشكلة؟';

  @override
  String get reportDetails => 'تفاصيل إضافية (اختياري)';

  @override
  String get reportSubmit => 'إرسال البلاغ';

  @override
  String get reportSubmitted => 'تم إرسال البلاغ';

  @override
  String get reportSubmittedBody =>
      'سيراجعه أحد المسؤولين. يمكنك أيضًا حظر هذا الشخص حتى لا يتواصل معك في أثناء ذلك.';

  @override
  String get reportAlsoBlock => 'احظره أيضًا';

  @override
  String get reportAlreadySent => 'سبق أن أبلغت عن هذه الرسالة';

  @override
  String get reportEvidenceNotice =>
      'تُرفق نسخة من الرسالة المُبلَّغ عنها، لتبقى متاحة حتى لو تم حذفها.';

  @override
  String get reasonSpam => 'رسائل مزعجة';

  @override
  String get reasonHarassment => 'تحرش أو إساءة';

  @override
  String get reasonImpersonation => 'انتحال شخصية';

  @override
  String get reasonScam => 'احتيال أو نصب';

  @override
  String get reasonIllegalContent => 'محتوى غير قانوني';

  @override
  String get reasonLeakedClassified => 'مواد سرية';

  @override
  String get reasonOther => 'شيء آخر';

  @override
  String get analyzeContent => 'تحليل المحتوى';

  @override
  String get myReports => 'بلاغاتي';

  @override
  String get reportStatusOpen => 'قيد المراجعة';

  @override
  String get reportStatusReviewing => 'تحت المراجعة';

  @override
  String get reportStatusActioned => 'تم اتخاذ إجراء';

  @override
  String get reportStatusDismissed => 'لم يُتخذ إجراء';

  @override
  String get searchMessages => 'البحث في الرسائل';

  @override
  String get searchMessagesTitle => 'البحث في الرسائل';

  @override
  String get searchMessagesHint => 'ابحث داخل هذه المحادثة';

  @override
  String get searchMessagesOnDeviceNotice =>
      'البحث يتم على هذا الجهاز فقط. الرسائل مُشفّرة ولا يستطيع الخادم قراءتها، لذلك تشمل النتائج ما نزّله هذا الجهاز.';

  @override
  String get searchNoResults => 'لا توجد نتائج';

  @override
  String get searchNoResultsHint => 'جرّب كلمة أقصر أو إملاءً مختلفًا.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نتيجة',
      few: '$count نتائج',
      two: 'نتيجتان',
      one: 'نتيجة واحدة',
      zero: 'لا نتائج',
    );
    return '$_temp0';
  }

  @override
  String get secureIdentityChanged =>
      'رمز الأمان الخاص بهذا الشخص تغيّر. لم يتم إرسال الرسالة.';

  @override
  String get secureIdentityChangedBody =>
      'يحدث هذا عند إعادة تثبيت التطبيق، وهو أيضًا شكل انتحال الشخصية. تأكّد منه عبر وسيلة أخرى قبل المتابعة.';

  @override
  String get secureAcceptNewIdentity => 'تحققت منه — تابع';

  @override
  String get securePeerHasNoKeys =>
      'هذا الشخص لا يستطيع استقبال رسائل سرية بعد.';

  @override
  String get securePeerHasNoKeysBody =>
      'جهازه لم ينشر مفاتيح التشفير. اطلب منه فتح IronLink مرة واحدة.';

  @override
  String get secureEncryptFailed => 'لم تُرسل الرسالة، لأنه تعذّر تشفيرها.';

  @override
  String get secureDecryptFailed => 'تعذّر فك تشفير إحدى الرسائل.';

  @override
  String get secureMessageUnreadable => 'تعذّر فك تشفير الرسالة';

  @override
  String get secretChatOn => 'المحادثة السرية مفعّلة';

  @override
  String get secretChatOff => 'المحادثة السرية غير مفعّلة';

  @override
  String get secretChatNotice =>
      'رسائل هذه المحادثة مشفّرة من طرف إلى طرف. الخادم يحفظ نصًا مشفّرًا لا يستطيع قراءته.';

  @override
  String get secretChatAttachmentWarning =>
      'المرفقات ليست مشفّرة من طرف إلى طرف بعد — التشفير يشمل التعليقات فقط.';

  @override
  String get attachmentLoadFailed => 'تعذّر تحميل المرفق';

  @override
  String get attachmentTampered => 'هذا المرفق تم التلاعب به ولم يُفتح';

  @override
  String get attachmentEncrypted => 'مرفق مشفّر';

  @override
  String get chatNotEncryptedNotice =>
      'رسائل هذه المحادثة ليست مشفّرة من طرف إلى طرف. هي محميّة أثناء النقل، لكن الخادم يستطيع قراءتها.';

  @override
  String get messageNotEncrypted => 'غير مشفّرة من طرف إلى طرف';
}
