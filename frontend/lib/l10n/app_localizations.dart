import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @authTagline.
  ///
  /// In ar, this message translates to:
  /// **'خاص · آمن · بلا حدود'**
  String get authTagline;

  /// No description provided for @authSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'منظومة التراسل المؤمَّنة'**
  String get authSubtitle;

  /// No description provided for @featureE2EE.
  ///
  /// In ar, this message translates to:
  /// **'تشفير من طرف لطرف'**
  String get featureE2EE;

  /// No description provided for @featureVerifiedIdentity.
  ///
  /// In ar, this message translates to:
  /// **'هوية موثقة'**
  String get featureVerifiedIdentity;

  /// No description provided for @featurePrivacyByDesign.
  ///
  /// In ar, this message translates to:
  /// **'خصوصية بالتصميم'**
  String get featurePrivacyByDesign;

  /// No description provided for @featureDeviceSecurity.
  ///
  /// In ar, this message translates to:
  /// **'أمان على كل جهاز'**
  String get featureDeviceSecurity;

  /// No description provided for @getStarted.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الآن'**
  String get getStarted;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In ar, this message translates to:
  /// **'لديك حساب بالفعل؟ '**
  String get alreadyHaveAccount;

  /// No description provided for @signIn.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get signIn;

  /// No description provided for @devGuestLogin.
  ///
  /// In ar, this message translates to:
  /// **'دخول تجريبي بدون سيرفر'**
  String get devGuestLogin;

  /// No description provided for @secureSignInTitle.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول الآمن'**
  String get secureSignInTitle;

  /// No description provided for @phoneStepSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم هاتفك المسجل لدى الوحدة'**
  String get phoneStepSubtitle;

  /// No description provided for @otpStepSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رمز التحقق المرسل إليك عبر رسالة نصية'**
  String get otpStepSubtitle;

  /// No description provided for @militaryIdStepSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقمك العسكري لإتمام التحقق'**
  String get militaryIdStepSubtitle;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get phoneNumberLabel;

  /// No description provided for @otpCodeLabel.
  ///
  /// In ar, this message translates to:
  /// **'رمز التحقق'**
  String get otpCodeLabel;

  /// No description provided for @sendVerificationCode.
  ///
  /// In ar, this message translates to:
  /// **'إرسال رمز التحقق'**
  String get sendVerificationCode;

  /// No description provided for @resendCode.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إرسال الرمز'**
  String get resendCode;

  /// No description provided for @resendCodeCountdown.
  ///
  /// In ar, this message translates to:
  /// **'إعادة الإرسال بعد {seconds} ثانية'**
  String resendCodeCountdown(int seconds);

  /// No description provided for @militaryIdHint.
  ///
  /// In ar, this message translates to:
  /// **'الرقم العسكري'**
  String get militaryIdHint;

  /// No description provided for @showPassword.
  ///
  /// In ar, this message translates to:
  /// **'إظهار'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In ar, this message translates to:
  /// **'إخفاء'**
  String get hidePassword;

  /// No description provided for @confirmSignIn.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الدخول'**
  String get confirmSignIn;

  /// No description provided for @e2eeNotice.
  ///
  /// In ar, this message translates to:
  /// **'بياناتك مشفّرة من طرف لطرف ولا يمكن للخادم قراءتها.'**
  String get e2eeNotice;

  /// No description provided for @errorFirebaseTokenFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر الحصول على رمز التحقق من Firebase'**
  String get errorFirebaseTokenFailed;

  /// No description provided for @errorNetwork.
  ///
  /// In ar, this message translates to:
  /// **'تعذر الاتصال بالخادم — تحقق من الشبكة'**
  String get errorNetwork;

  /// No description provided for @errorUnexpected.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع'**
  String get errorUnexpected;

  /// No description provided for @errorInvalidPhone.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف غير صالح'**
  String get errorInvalidPhone;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In ar, this message translates to:
  /// **'محاولات كثيرة جدًا — حاول لاحقًا'**
  String get errorTooManyRequests;

  /// No description provided for @errorInvalidCode.
  ///
  /// In ar, this message translates to:
  /// **'رمز التحقق غير صحيح'**
  String get errorInvalidCode;

  /// No description provided for @errorSessionExpired.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحية الرمز — أعد الإرسال'**
  String get errorSessionExpired;

  /// No description provided for @errorPhoneVerificationFailed.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ أثناء التحقق من الهاتف'**
  String get errorPhoneVerificationFailed;

  /// No description provided for @noChatsYet.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد محادثات بعد'**
  String get noChatsYet;

  /// No description provided for @noChatsYetHint.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ محادثة مؤمَّنة مع أحد جهات اتصالك.'**
  String get noChatsYetHint;

  /// No description provided for @onlineNow.
  ///
  /// In ar, this message translates to:
  /// **'متصل الآن'**
  String get onlineNow;

  /// No description provided for @startSecretChat.
  ///
  /// In ar, this message translates to:
  /// **'بدء محادثة سرية'**
  String get startSecretChat;

  /// No description provided for @secretChatComingSoon.
  ///
  /// In ar, this message translates to:
  /// **'تم تفعيل المحادثة السرية (سيتم تطبيقها في التحديث التالي)'**
  String get secretChatComingSoon;

  /// No description provided for @messageDeleted.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف هذه الرسالة'**
  String get messageDeleted;

  /// No description provided for @translate.
  ///
  /// In ar, this message translates to:
  /// **'ترجمة'**
  String get translate;

  /// No description provided for @reportMessage.
  ///
  /// In ar, this message translates to:
  /// **'إبلاغ عن رسالة'**
  String get reportMessage;

  /// No description provided for @deleteForEveryone.
  ///
  /// In ar, this message translates to:
  /// **'حذف لدى الجميع'**
  String get deleteForEveryone;

  /// No description provided for @deleteForEveryoneHint.
  ///
  /// In ar, this message translates to:
  /// **'متاح خلال 5 دقائق من الإرسال'**
  String get deleteForEveryoneHint;

  /// No description provided for @typingIndicator.
  ///
  /// In ar, this message translates to:
  /// **'{name} يكتب'**
  String typingIndicator(String name);

  /// No description provided for @attach.
  ///
  /// In ar, this message translates to:
  /// **'إرفاق'**
  String get attach;

  /// No description provided for @messageHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب رسالة…'**
  String get messageHint;

  /// No description provided for @send.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get send;

  /// No description provided for @notInAnyGroupYet.
  ///
  /// In ar, this message translates to:
  /// **'لست عضواً في أي مجموعة بعد'**
  String get notInAnyGroupYet;

  /// No description provided for @notInAnyGroupYetHint.
  ///
  /// In ar, this message translates to:
  /// **'أنشئ مجموعة أو انضم إلى واحدة للتنسيق مع فريقك.'**
  String get notInAnyGroupYetHint;

  /// No description provided for @groupMembersTitle.
  ///
  /// In ar, this message translates to:
  /// **'{name} — {count} عضو'**
  String groupMembersTitle(String name, int count);

  /// No description provided for @announcementChannelReadOnly.
  ///
  /// In ar, this message translates to:
  /// **'قناة إعلانات — للقراءة فقط'**
  String get announcementChannelReadOnly;

  /// No description provided for @memberCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} عضو'**
  String memberCount(int count);

  /// No description provided for @roleOwner.
  ///
  /// In ar, this message translates to:
  /// **'مالك المجموعة'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In ar, this message translates to:
  /// **'مشرف'**
  String get roleAdmin;

  /// No description provided for @roleModerator.
  ///
  /// In ar, this message translates to:
  /// **'منسق'**
  String get roleModerator;

  /// No description provided for @roleObserver.
  ///
  /// In ar, this message translates to:
  /// **'مراقب — قراءة فقط'**
  String get roleObserver;

  /// No description provided for @roleMember.
  ///
  /// In ar, this message translates to:
  /// **'عضو'**
  String get roleMember;

  /// No description provided for @channelsTitle.
  ///
  /// In ar, this message translates to:
  /// **'القنوات'**
  String get channelsTitle;

  /// No description provided for @createChannel.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء قناة'**
  String get createChannel;

  /// No description provided for @noChannelsYet.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد قنوات بعد'**
  String get noChannelsYet;

  /// No description provided for @noChannelsYetHint.
  ///
  /// In ar, this message translates to:
  /// **'اشترك في قناة لتصلك الإعلانات الرسمية.'**
  String get noChannelsYetHint;

  /// No description provided for @channelsLoadFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل القنوات'**
  String get channelsLoadFailedTitle;

  /// No description provided for @subscriberCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} مشترك'**
  String subscriberCount(int count);

  /// No description provided for @ocrKeywordsTitle.
  ///
  /// In ar, this message translates to:
  /// **'كلمات المسح الضوئي المفتاحية (OCR)'**
  String get ocrKeywordsTitle;

  /// No description provided for @ocrKeywordsDescription.
  ///
  /// In ar, this message translates to:
  /// **'يتم تنبيهك تلقائيًا إذا ظهرت أي من هذه الكلمات في نص ممسوح ضوئيًا (OCR) داخل صورة أو مستند.'**
  String get ocrKeywordsDescription;

  /// No description provided for @newKeywordLabel.
  ///
  /// In ar, this message translates to:
  /// **'كلمة مفتاحية جديدة'**
  String get newKeywordLabel;

  /// No description provided for @newKeywordHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب كلمة وأضفها'**
  String get newKeywordHint;

  /// No description provided for @noKeywordsYet.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد كلمات مفتاحية بعد'**
  String get noKeywordsYet;

  /// No description provided for @add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة'**
  String get add;

  /// No description provided for @ocrKeywordExists.
  ///
  /// In ar, this message translates to:
  /// **'هذه الكلمة مُضافة بالفعل.'**
  String get ocrKeywordExists;

  /// No description provided for @ocrKeywordsEmptyHint.
  ///
  /// In ar, this message translates to:
  /// **'أضف كلمة ليتم تنبيهك عند ظهورها في أي صورة أو مستند ممسوح ضوئيًا.'**
  String get ocrKeywordsEmptyHint;

  /// No description provided for @retry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get retry;

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @ocrLoadFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل الكلمات'**
  String get ocrLoadFailedTitle;

  /// No description provided for @ocrAddFailed.
  ///
  /// In ar, this message translates to:
  /// **'لم تُضَف الكلمة. حاول مرة أخرى.'**
  String get ocrAddFailed;

  /// No description provided for @ocrRemoveFailed.
  ///
  /// In ar, this message translates to:
  /// **'لم تُحذَف الكلمة. حاول مرة أخرى.'**
  String get ocrRemoveFailed;

  /// No description provided for @failureOffline.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد اتصال بالإنترنت. تحقّق من الشبكة ثم أعد المحاولة.'**
  String get failureOffline;

  /// No description provided for @failureTimeout.
  ///
  /// In ar, this message translates to:
  /// **'الخادم يستغرق وقتًا أطول من المعتاد. أعد المحاولة بعد قليل.'**
  String get failureTimeout;

  /// No description provided for @failureServer.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الوصول إلى الخادم حاليًا. أعد المحاولة بعد قليل.'**
  String get failureServer;

  /// No description provided for @failureUnauthorized.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحية جلستك. سجّل الدخول مرة أخرى.'**
  String get failureUnauthorized;

  /// No description provided for @failureRejected.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر إتمام الطلب. راجع البيانات وحاول مرة أخرى.'**
  String get failureRejected;

  /// No description provided for @failureInsecure.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر التحقّق من أمان الاتصال. لم تُرسَل أي بيانات.'**
  String get failureInsecure;

  /// No description provided for @failureUnknown.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقّع. أعد المحاولة.'**
  String get failureUnknown;

  /// No description provided for @tabChats.
  ///
  /// In ar, this message translates to:
  /// **'المحادثات'**
  String get tabChats;

  /// No description provided for @tabGroups.
  ///
  /// In ar, this message translates to:
  /// **'المجموعات'**
  String get tabGroups;

  /// No description provided for @tabBroadcasts.
  ///
  /// In ar, this message translates to:
  /// **'التعميمات'**
  String get tabBroadcasts;

  /// No description provided for @tabSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get tabSettings;

  /// No description provided for @comingSoon.
  ///
  /// In ar, this message translates to:
  /// **'قريباً'**
  String get comingSoon;

  /// No description provided for @releaseToCancel.
  ///
  /// In ar, this message translates to:
  /// **'اترك للإلغاء'**
  String get releaseToCancel;

  /// No description provided for @dragToCancel.
  ///
  /// In ar, this message translates to:
  /// **'← اسحب للإلغاء'**
  String get dragToCancel;

  /// No description provided for @voiceUploadFailed.
  ///
  /// In ar, this message translates to:
  /// **'فشل رفع التسجيل الصوتي'**
  String get voiceUploadFailed;

  /// No description provided for @uploadFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر رفع المرفق. حاول مرة أخرى.'**
  String get uploadFailed;

  /// No description provided for @attachGallery.
  ///
  /// In ar, this message translates to:
  /// **'المعرض'**
  String get attachGallery;

  /// No description provided for @attachCamera.
  ///
  /// In ar, this message translates to:
  /// **'الكاميرا'**
  String get attachCamera;

  /// No description provided for @attachDocument.
  ///
  /// In ar, this message translates to:
  /// **'مستند PDF'**
  String get attachDocument;

  /// No description provided for @attachPdfComingSoon.
  ///
  /// In ar, this message translates to:
  /// **'اختيار ملفات PDF غير متاح بعد.'**
  String get attachPdfComingSoon;

  /// No description provided for @captionHint.
  ///
  /// In ar, this message translates to:
  /// **'أضف تعليقًا…'**
  String get captionHint;

  /// No description provided for @ocrAlertFound.
  ///
  /// In ar, this message translates to:
  /// **'رُصدت الكلمة \"{keyword}\" في ملف مرفوع.'**
  String ocrAlertFound(String keyword);

  /// No description provided for @acknowledged.
  ///
  /// In ar, this message translates to:
  /// **'علمت'**
  String get acknowledged;

  /// No description provided for @completeVerificationForm.
  ///
  /// In ar, this message translates to:
  /// **'استكمال نموذج التحقق'**
  String get completeVerificationForm;

  /// No description provided for @joinRequestFor.
  ///
  /// In ar, this message translates to:
  /// **'طلب انضمام: {group}'**
  String joinRequestFor(String group);

  /// No description provided for @completeFormBelow.
  ///
  /// In ar, this message translates to:
  /// **'يرجى استكمال النموذج أدناه.'**
  String get completeFormBelow;

  /// No description provided for @submitRequest.
  ///
  /// In ar, this message translates to:
  /// **'إرسال الطلب'**
  String get submitRequest;

  /// No description provided for @resubmit.
  ///
  /// In ar, this message translates to:
  /// **'إعادة الإرسال'**
  String get resubmit;

  /// No description provided for @requestToJoin.
  ///
  /// In ar, this message translates to:
  /// **'طلب الانضمام'**
  String get requestToJoin;

  /// No description provided for @cancelRequest.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الطلب'**
  String get cancelRequest;

  /// No description provided for @requestAgain.
  ///
  /// In ar, this message translates to:
  /// **'إعادة الطلب'**
  String get requestAgain;

  /// No description provided for @requiredFieldsProgress.
  ///
  /// In ar, this message translates to:
  /// **'{filled} من {total} حقول مطلوبة مكتملة'**
  String requiredFieldsProgress(int filled, int total);

  /// No description provided for @draftRestored.
  ///
  /// In ar, this message translates to:
  /// **'تم استرجاع إجاباتك السابقة'**
  String get draftRestored;

  /// No description provided for @formAnswersEncrypted.
  ///
  /// In ar, this message translates to:
  /// **'إجاباتك مشفّرة أثناء النقل وعند التخزين.'**
  String get formAnswersEncrypted;

  /// No description provided for @formLoadFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل النموذج'**
  String get formLoadFailedTitle;

  /// No description provided for @noFormRequired.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد نموذج مطلوب'**
  String get noFormRequired;

  /// No description provided for @noFormRequiredHint.
  ///
  /// In ar, this message translates to:
  /// **'هذه المجموعة لا تطلب أي معلومات إضافية. أرسل طلبك مباشرة.'**
  String get noFormRequiredHint;

  /// No description provided for @selectAnOption.
  ///
  /// In ar, this message translates to:
  /// **'اختر خيارًا'**
  String get selectAnOption;

  /// No description provided for @selectADate.
  ///
  /// In ar, this message translates to:
  /// **'اختر تاريخًا'**
  String get selectADate;

  /// No description provided for @noFileSelected.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم اختيار ملف'**
  String get noFileSelected;

  /// No description provided for @fieldTypeUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل غير مدعوم في هذا الإصدار. حدّث التطبيق لإكماله.'**
  String get fieldTypeUnsupported;

  /// No description provided for @statusPending.
  ///
  /// In ar, this message translates to:
  /// **'قيد المراجعة'**
  String get statusPending;

  /// No description provided for @statusApproved.
  ///
  /// In ar, this message translates to:
  /// **'تمت الموافقة'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In ar, this message translates to:
  /// **'مرفوض'**
  String get statusRejected;

  /// No description provided for @statusMoreInfo.
  ///
  /// In ar, this message translates to:
  /// **'بحاجة لمعلومات'**
  String get statusMoreInfo;

  /// No description provided for @statusExpired.
  ///
  /// In ar, this message translates to:
  /// **'منتهي'**
  String get statusExpired;

  /// No description provided for @joinRequestsTitle.
  ///
  /// In ar, this message translates to:
  /// **'طلبات الانضمام'**
  String get joinRequestsTitle;

  /// No description provided for @tabPending.
  ///
  /// In ar, this message translates to:
  /// **'معلّقة'**
  String get tabPending;

  /// No description provided for @tabExpired.
  ///
  /// In ar, this message translates to:
  /// **'منتهية'**
  String get tabExpired;

  /// No description provided for @tabHistory.
  ///
  /// In ar, this message translates to:
  /// **'السجل'**
  String get tabHistory;

  /// No description provided for @select.
  ///
  /// In ar, this message translates to:
  /// **'تحديد'**
  String get select;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @approve.
  ///
  /// In ar, this message translates to:
  /// **'موافقة'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In ar, this message translates to:
  /// **'رفض'**
  String get reject;

  /// No description provided for @approveAll.
  ///
  /// In ar, this message translates to:
  /// **'قبول الكل'**
  String get approveAll;

  /// No description provided for @rejectAll.
  ///
  /// In ar, this message translates to:
  /// **'رفض الكل'**
  String get rejectAll;

  /// No description provided for @approveSelected.
  ///
  /// In ar, this message translates to:
  /// **'قبول ({count})'**
  String approveSelected(int count);

  /// No description provided for @rejectSelected.
  ///
  /// In ar, this message translates to:
  /// **'رفض ({count})'**
  String rejectSelected(int count);

  /// No description provided for @approveAllTitle.
  ///
  /// In ar, this message translates to:
  /// **'قبول جميع الطلبات'**
  String get approveAllTitle;

  /// No description provided for @rejectAllTitle.
  ///
  /// In ar, this message translates to:
  /// **'رفض جميع الطلبات'**
  String get rejectAllTitle;

  /// No description provided for @approveAllConfirm.
  ///
  /// In ar, this message translates to:
  /// **'هل أنت متأكد أنك تريد قبول جميع الطلبات المعلّقة وعددها {count}؟'**
  String approveAllConfirm(int count);

  /// No description provided for @rejectAllConfirm.
  ///
  /// In ar, this message translates to:
  /// **'هل أنت متأكد أنك تريد رفض جميع الطلبات المعلّقة وعددها {count}؟ لا يمكن التراجع عن هذا الإجراء.'**
  String rejectAllConfirm(int count);

  /// No description provided for @bulkResult.
  ///
  /// In ar, this message translates to:
  /// **'تمت المعالجة بنجاح لـ {count} طلب'**
  String bulkResult(int count);

  /// No description provided for @rejectRequestTitle.
  ///
  /// In ar, this message translates to:
  /// **'رفض الطلب'**
  String get rejectRequestTitle;

  /// No description provided for @rejectionReasonOptional.
  ///
  /// In ar, this message translates to:
  /// **'سبب الرفض (اختياري)'**
  String get rejectionReasonOptional;

  /// No description provided for @rejectionReasonLabel.
  ///
  /// In ar, this message translates to:
  /// **'سبب الرفض'**
  String get rejectionReasonLabel;

  /// No description provided for @noAnswersSubmitted.
  ///
  /// In ar, this message translates to:
  /// **'لم تُقدَّم أي إجابات'**
  String get noAnswersSubmitted;

  /// No description provided for @requestsLoadFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل الطلبات'**
  String get requestsLoadFailedTitle;

  /// No description provided for @noPendingRequests.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد طلبات انضمام معلّقة'**
  String get noPendingRequests;

  /// No description provided for @noPendingRequestsHint.
  ///
  /// In ar, this message translates to:
  /// **'مجموعتك آمنة. ستظهر الطلبات الجديدة هنا.'**
  String get noPendingRequestsHint;

  /// No description provided for @nothingHere.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد شيء هنا'**
  String get nothingHere;

  /// No description provided for @nothingHereHint.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد طلبات بهذه الحالة بعد.'**
  String get nothingHereHint;

  /// No description provided for @minutesAgo.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} دقيقة'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} ساعة'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} يوم'**
  String daysAgo(int count);

  /// No description provided for @entrySettingsTitle.
  ///
  /// In ar, this message translates to:
  /// **'إعدادات الانضمام'**
  String get entrySettingsTitle;

  /// No description provided for @joinModeSection.
  ///
  /// In ar, this message translates to:
  /// **'طريقة الانضمام'**
  String get joinModeSection;

  /// No description provided for @modeOpen.
  ///
  /// In ar, this message translates to:
  /// **'مفتوحة'**
  String get modeOpen;

  /// No description provided for @modeOpenHint.
  ///
  /// In ar, this message translates to:
  /// **'أي شخص ينضم فورًا بدون موافقة.'**
  String get modeOpenHint;

  /// No description provided for @modeInviteOnly.
  ///
  /// In ar, this message translates to:
  /// **'بالدعوة فقط'**
  String get modeInviteOnly;

  /// No description provided for @modeInviteOnlyHint.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن الانضمام إلا عبر رابط دعوة.'**
  String get modeInviteOnlyHint;

  /// No description provided for @modeRequestApproval.
  ///
  /// In ar, this message translates to:
  /// **'طلب وموافقة'**
  String get modeRequestApproval;

  /// No description provided for @modeRequestApprovalHint.
  ///
  /// In ar, this message translates to:
  /// **'يملأ المتقدّم نموذج تحقق وينتظر موافقة المشرف.'**
  String get modeRequestApprovalHint;

  /// No description provided for @verificationFormSection.
  ///
  /// In ar, this message translates to:
  /// **'نموذج التحقق'**
  String get verificationFormSection;

  /// No description provided for @noFormAttached.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد نموذج'**
  String get noFormAttached;

  /// No description provided for @noFormAttachedHint.
  ///
  /// In ar, this message translates to:
  /// **'المجموعة مغلقة لكنها لا تسأل أي شيء. أنشئ نموذجًا.'**
  String get noFormAttachedHint;

  /// No description provided for @fieldCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} حقل'**
  String fieldCount(int count);

  /// No description provided for @requestHandlingSection.
  ///
  /// In ar, this message translates to:
  /// **'معالجة الطلبات'**
  String get requestHandlingSection;

  /// No description provided for @requestExpiryTitle.
  ///
  /// In ar, this message translates to:
  /// **'انتهاء صلاحية الطلب'**
  String get requestExpiryTitle;

  /// No description provided for @requestExpiryHint.
  ///
  /// In ar, this message translates to:
  /// **'الطلبات التي لا يُتخذ فيها قرار خلال هذه المدة تنتهي تلقائيًا.'**
  String get requestExpiryHint;

  /// No description provided for @expiryNever.
  ///
  /// In ar, this message translates to:
  /// **'بلا انتهاء'**
  String get expiryNever;

  /// No description provided for @expiryDays.
  ///
  /// In ar, this message translates to:
  /// **'{count} يوم'**
  String expiryDays(int count);

  /// No description provided for @allowRejoinTitle.
  ///
  /// In ar, this message translates to:
  /// **'السماح بإعادة التقديم'**
  String get allowRejoinTitle;

  /// No description provided for @allowRejoinHint.
  ///
  /// In ar, this message translates to:
  /// **'يمكن لمن رُفض طلبه تقديم طلب جديد.'**
  String get allowRejoinHint;

  /// No description provided for @saveChanges.
  ///
  /// In ar, this message translates to:
  /// **'حفظ التغييرات'**
  String get saveChanges;

  /// No description provided for @settingsSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ الإعدادات'**
  String get settingsSaved;

  /// No description provided for @formBuilderTitle.
  ///
  /// In ar, this message translates to:
  /// **'بنّاء النموذج'**
  String get formBuilderTitle;

  /// No description provided for @formBuilderEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لم تُضف أي حقول بعد'**
  String get formBuilderEmptyTitle;

  /// No description provided for @formBuilderEmptyHint.
  ///
  /// In ar, this message translates to:
  /// **'أضف الحقول التي يجب على المتقدّم استكمالها قبل الانضمام.'**
  String get formBuilderEmptyHint;

  /// No description provided for @addField.
  ///
  /// In ar, this message translates to:
  /// **'إضافة حقل'**
  String get addField;

  /// No description provided for @saveAndActivate.
  ///
  /// In ar, this message translates to:
  /// **'حفظ وتفعيل'**
  String get saveAndActivate;

  /// No description provided for @previewForm.
  ///
  /// In ar, this message translates to:
  /// **'معاينة'**
  String get previewForm;

  /// No description provided for @editForm.
  ///
  /// In ar, this message translates to:
  /// **'تحرير'**
  String get editForm;

  /// No description provided for @previewNotice.
  ///
  /// In ar, this message translates to:
  /// **'هذا ما سيراه المتقدّم بالضبط.'**
  String get previewNotice;

  /// No description provided for @formNameLabel.
  ///
  /// In ar, this message translates to:
  /// **'اسم النموذج'**
  String get formNameLabel;

  /// No description provided for @formNameHint.
  ///
  /// In ar, this message translates to:
  /// **'مثال: تحقق الوحدة'**
  String get formNameHint;

  /// No description provided for @formNeedsName.
  ///
  /// In ar, this message translates to:
  /// **'أدخل اسمًا للنموذج'**
  String get formNeedsName;

  /// No description provided for @formNeedsFields.
  ///
  /// In ar, this message translates to:
  /// **'أضف حقلًا واحدًا على الأقل'**
  String get formNeedsFields;

  /// No description provided for @fieldNumber.
  ///
  /// In ar, this message translates to:
  /// **'الحقل {number}'**
  String fieldNumber(int number);

  /// No description provided for @fieldNeedsLabel.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل يحتاج عنوانًا'**
  String get fieldNeedsLabel;

  /// No description provided for @fieldNeedsOptions.
  ///
  /// In ar, this message translates to:
  /// **'أضف خيارًا واحدًا على الأقل'**
  String get fieldNeedsOptions;

  /// No description provided for @untitledField.
  ///
  /// In ar, this message translates to:
  /// **'حقل بلا عنوان'**
  String get untitledField;

  /// No description provided for @chooseFieldType.
  ///
  /// In ar, this message translates to:
  /// **'اختر نوع الحقل'**
  String get chooseFieldType;

  /// No description provided for @fieldLabelLabel.
  ///
  /// In ar, this message translates to:
  /// **'السؤال'**
  String get fieldLabelLabel;

  /// No description provided for @fieldLabelHint.
  ///
  /// In ar, this message translates to:
  /// **'مثال: الاسم الرباعي بالعربي'**
  String get fieldLabelHint;

  /// No description provided for @fieldPlaceholderLabel.
  ///
  /// In ar, this message translates to:
  /// **'نص توضيحي داخل الحقل (اختياري)'**
  String get fieldPlaceholderLabel;

  /// No description provided for @fieldHelperLabel.
  ///
  /// In ar, this message translates to:
  /// **'إرشاد أسفل الحقل (اختياري)'**
  String get fieldHelperLabel;

  /// No description provided for @fieldRequiredLabel.
  ///
  /// In ar, this message translates to:
  /// **'حقل مطلوب'**
  String get fieldRequiredLabel;

  /// No description provided for @fieldOptionsLabel.
  ///
  /// In ar, this message translates to:
  /// **'الخيارات'**
  String get fieldOptionsLabel;

  /// No description provided for @addOptionHint.
  ///
  /// In ar, this message translates to:
  /// **'أضف خيارًا'**
  String get addOptionHint;

  /// No description provided for @optionExists.
  ///
  /// In ar, this message translates to:
  /// **'هذا الخيار موجود بالفعل'**
  String get optionExists;

  /// No description provided for @done.
  ///
  /// In ar, this message translates to:
  /// **'تم'**
  String get done;

  /// No description provided for @fieldTypeTextShort.
  ///
  /// In ar, this message translates to:
  /// **'نص قصير'**
  String get fieldTypeTextShort;

  /// No description provided for @fieldTypeTextLong.
  ///
  /// In ar, this message translates to:
  /// **'نص طويل'**
  String get fieldTypeTextLong;

  /// No description provided for @fieldTypeNumber.
  ///
  /// In ar, this message translates to:
  /// **'رقم'**
  String get fieldTypeNumber;

  /// No description provided for @fieldTypeSelectSingle.
  ///
  /// In ar, this message translates to:
  /// **'اختيار واحد'**
  String get fieldTypeSelectSingle;

  /// No description provided for @fieldTypeSelectMulti.
  ///
  /// In ar, this message translates to:
  /// **'اختيار متعدد'**
  String get fieldTypeSelectMulti;

  /// No description provided for @fieldTypeDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ'**
  String get fieldTypeDate;

  /// No description provided for @fieldTypePhone.
  ///
  /// In ar, this message translates to:
  /// **'رقم هاتف'**
  String get fieldTypePhone;

  /// No description provided for @fieldTypeFile.
  ///
  /// In ar, this message translates to:
  /// **'ملف'**
  String get fieldTypeFile;

  /// No description provided for @fieldTypeImage.
  ///
  /// In ar, this message translates to:
  /// **'صورة'**
  String get fieldTypeImage;

  /// No description provided for @fieldTypeCheckbox.
  ///
  /// In ar, this message translates to:
  /// **'مربع اختيار'**
  String get fieldTypeCheckbox;

  /// No description provided for @fieldTypeUrl.
  ///
  /// In ar, this message translates to:
  /// **'رابط'**
  String get fieldTypeUrl;

  /// No description provided for @fieldTypeEmail.
  ///
  /// In ar, this message translates to:
  /// **'بريد إلكتروني'**
  String get fieldTypeEmail;

  /// No description provided for @auditLogTitle.
  ///
  /// In ar, this message translates to:
  /// **'سجل التدقيق'**
  String get auditLogTitle;

  /// No description provided for @auditLogEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لم يُسجَّل أي نشاط بعد'**
  String get auditLogEmpty;

  /// No description provided for @auditLogEmptyHint.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر هنا كل الإجراءات الحساسة على المجموعة.'**
  String get auditLogEmptyHint;

  /// No description provided for @auditLogLoadFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل السجل'**
  String get auditLogLoadFailedTitle;

  /// No description provided for @loadMore.
  ///
  /// In ar, this message translates to:
  /// **'تحميل المزيد'**
  String get loadMore;

  /// No description provided for @filterAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get filterAll;

  /// No description provided for @filterApprovals.
  ///
  /// In ar, this message translates to:
  /// **'الموافقات'**
  String get filterApprovals;

  /// No description provided for @filterRejections.
  ///
  /// In ar, this message translates to:
  /// **'الرفض'**
  String get filterRejections;

  /// No description provided for @filterBans.
  ///
  /// In ar, this message translates to:
  /// **'الحظر'**
  String get filterBans;

  /// No description provided for @filterSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get filterSettings;

  /// No description provided for @auditApproved.
  ///
  /// In ar, this message translates to:
  /// **'تمت الموافقة على طلب انضمام'**
  String get auditApproved;

  /// No description provided for @auditRejected.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض طلب انضمام'**
  String get auditRejected;

  /// No description provided for @auditMoreInfo.
  ///
  /// In ar, this message translates to:
  /// **'طُلبت معلومات إضافية'**
  String get auditMoreInfo;

  /// No description provided for @auditBulkApproved.
  ///
  /// In ar, this message translates to:
  /// **'تمت الموافقة على {count} طلب دفعة واحدة'**
  String auditBulkApproved(int count);

  /// No description provided for @auditBulkRejected.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض {count} طلب دفعة واحدة'**
  String auditBulkRejected(int count);

  /// No description provided for @auditBanned.
  ///
  /// In ar, this message translates to:
  /// **'تم حظر عضو'**
  String get auditBanned;

  /// No description provided for @auditUnbanned.
  ///
  /// In ar, this message translates to:
  /// **'تم رفع الحظر عن عضو'**
  String get auditUnbanned;

  /// No description provided for @auditRemoved.
  ///
  /// In ar, this message translates to:
  /// **'تمت إزالة عضو'**
  String get auditRemoved;

  /// No description provided for @auditJoinModeChanged.
  ///
  /// In ar, this message translates to:
  /// **'تم تغيير طريقة الانضمام'**
  String get auditJoinModeChanged;

  /// No description provided for @auditFormUpdated.
  ///
  /// In ar, this message translates to:
  /// **'تم تحديث نموذج التحقق'**
  String get auditFormUpdated;

  /// No description provided for @auditModeratorAssigned.
  ///
  /// In ar, this message translates to:
  /// **'تم تعيين منسق'**
  String get auditModeratorAssigned;

  /// No description provided for @auditReopened.
  ///
  /// In ar, this message translates to:
  /// **'تمت إعادة فتح طلب'**
  String get auditReopened;

  /// No description provided for @auditExported.
  ///
  /// In ar, this message translates to:
  /// **'تم تصدير سجل التدقيق'**
  String get auditExported;

  /// No description provided for @uploading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الرفع…'**
  String get uploading;

  /// No description provided for @fileAttached.
  ///
  /// In ar, this message translates to:
  /// **'تم إرفاق ملف'**
  String get fileAttached;

  /// No description provided for @choose.
  ///
  /// In ar, this message translates to:
  /// **'اختيار'**
  String get choose;

  /// No description provided for @replace.
  ///
  /// In ar, this message translates to:
  /// **'استبدال'**
  String get replace;

  /// No description provided for @amendRequest.
  ///
  /// In ar, this message translates to:
  /// **'تعديل الطلب'**
  String get amendRequest;

  /// No description provided for @cancelRequestTitle.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الطلب'**
  String get cancelRequestTitle;

  /// No description provided for @cancelRequestConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيُحذف طلبك وإجاباتك. يمكنك التقديم من جديد لاحقًا.'**
  String get cancelRequestConfirm;

  /// No description provided for @keepRequest.
  ///
  /// In ar, this message translates to:
  /// **'الإبقاء عليه'**
  String get keepRequest;

  /// No description provided for @groupRequiresApproval.
  ///
  /// In ar, this message translates to:
  /// **'هذه المجموعة تتطلّب موافقة المشرف قبل الانضمام.'**
  String get groupRequiresApproval;

  /// No description provided for @statusPendingBody.
  ///
  /// In ar, this message translates to:
  /// **'طلبك قيد المراجعة من قِبل المشرف.'**
  String get statusPendingBody;

  /// No description provided for @statusApprovedBody.
  ///
  /// In ar, this message translates to:
  /// **'تمت الموافقة على طلبك! يمكنك الآن المشاركة في المجموعة.'**
  String get statusApprovedBody;

  /// No description provided for @statusRejectedBody.
  ///
  /// In ar, this message translates to:
  /// **'لم تتم الموافقة على طلبك.'**
  String get statusRejectedBody;

  /// No description provided for @statusMoreInfoBody.
  ///
  /// In ar, this message translates to:
  /// **'يحتاج المشرف إلى معلومات إضافية. يرجى تعديل طلبك.'**
  String get statusMoreInfoBody;

  /// No description provided for @statusExpiredBody.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحية طلبك. يمكنك تقديم طلب جديد.'**
  String get statusExpiredBody;

  /// No description provided for @contactsTitle.
  ///
  /// In ar, this message translates to:
  /// **'جهات الاتصال'**
  String get contactsTitle;

  /// No description provided for @findContactsTitle.
  ///
  /// In ar, this message translates to:
  /// **'اكتشاف جهات اتصالك'**
  String get findContactsTitle;

  /// No description provided for @findContactsHeadline.
  ///
  /// In ar, this message translates to:
  /// **'اعثر على من تعرفهم'**
  String get findContactsHeadline;

  /// No description provided for @findContactsBody.
  ///
  /// In ar, this message translates to:
  /// **'نطابق دفتر عناوينك مع مستخدمي آيرون لينك، من غير ما نعرف أرقامك.'**
  String get findContactsBody;

  /// No description provided for @contactsPointHashedTitle.
  ///
  /// In ar, this message translates to:
  /// **'التجزئة تتم على جهازك'**
  String get contactsPointHashedTitle;

  /// No description provided for @contactsPointHashedBody.
  ///
  /// In ar, this message translates to:
  /// **'كل رقم يتحوّل إلى بصمة مشفّرة قبل أن يغادر الهاتف.'**
  String get contactsPointHashedBody;

  /// No description provided for @contactsPointNoNumbersTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا تُرسَل أرقام أبدًا'**
  String get contactsPointNoNumbersTitle;

  /// No description provided for @contactsPointNoNumbersBody.
  ///
  /// In ar, this message translates to:
  /// **'الخادم يستقبل بصمات فقط، ولا يمكنه استرجاع الرقم منها.'**
  String get contactsPointNoNumbersBody;

  /// No description provided for @contactsPointReversibleTitle.
  ///
  /// In ar, this message translates to:
  /// **'قابل للتراجع في أي وقت'**
  String get contactsPointReversibleTitle;

  /// No description provided for @contactsPointReversibleBody.
  ///
  /// In ar, this message translates to:
  /// **'يمكنك حذف كل ما تم مطابقته بضغطة واحدة.'**
  String get contactsPointReversibleBody;

  /// No description provided for @contactsDeniedHint.
  ///
  /// In ar, this message translates to:
  /// **'بدون الإذن لن نستطيع اقتراح من تعرفهم. يمكنك تفعيله لاحقًا من إعدادات النظام.'**
  String get contactsDeniedHint;

  /// No description provided for @allowContactAccess.
  ///
  /// In ar, this message translates to:
  /// **'السماح بالوصول'**
  String get allowContactAccess;

  /// No description provided for @notNow.
  ///
  /// In ar, this message translates to:
  /// **'ليس الآن'**
  String get notNow;

  /// No description provided for @contactSyncOff.
  ///
  /// In ar, this message translates to:
  /// **'المزامنة غير مفعّلة'**
  String get contactSyncOff;

  /// No description provided for @contactSyncOffHint.
  ///
  /// In ar, this message translates to:
  /// **'فعّلها لاكتشاف من تعرفهم على آيرون لينك.'**
  String get contactSyncOffHint;

  /// No description provided for @enableContactSync.
  ///
  /// In ar, this message translates to:
  /// **'تفعيل المزامنة'**
  String get enableContactSync;

  /// No description provided for @syncNow.
  ///
  /// In ar, this message translates to:
  /// **'مزامنة الآن'**
  String get syncNow;

  /// No description provided for @syncFoundNew.
  ///
  /// In ar, this message translates to:
  /// **'تم العثور على {count} جهة اتصال جديدة'**
  String syncFoundNew(int count);

  /// No description provided for @syncNoNewContacts.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد جهات اتصال جديدة'**
  String get syncNoNewContacts;

  /// No description provided for @noContactsFound.
  ///
  /// In ar, this message translates to:
  /// **'لم نجد أحدًا بعد'**
  String get noContactsFound;

  /// No description provided for @noContactsFoundHint.
  ///
  /// In ar, this message translates to:
  /// **'لا أحد من جهات اتصالك على آيرون لينك حاليًا.'**
  String get noContactsFoundHint;

  /// No description provided for @contactsLoadFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل جهات الاتصال'**
  String get contactsLoadFailedTitle;

  /// No description provided for @onIronLink.
  ///
  /// In ar, this message translates to:
  /// **'على آيرون لينك ({count})'**
  String onIronLink(int count);

  /// No description provided for @badgeNew.
  ///
  /// In ar, this message translates to:
  /// **'جديد'**
  String get badgeNew;

  /// No description provided for @contactPrivacyTitle.
  ///
  /// In ar, this message translates to:
  /// **'خصوصية جهات الاتصال'**
  String get contactPrivacyTitle;

  /// No description provided for @whoCanFindMe.
  ///
  /// In ar, this message translates to:
  /// **'من يمكنه العثور عليّ برقم هاتفي'**
  String get whoCanFindMe;

  /// No description provided for @discoverEveryone.
  ///
  /// In ar, this message translates to:
  /// **'الجميع'**
  String get discoverEveryone;

  /// No description provided for @discoverEveryoneHint.
  ///
  /// In ar, this message translates to:
  /// **'أي شخص لديه رقمك يمكنه اكتشافك.'**
  String get discoverEveryoneHint;

  /// No description provided for @discoverMutual.
  ///
  /// In ar, this message translates to:
  /// **'من أعرفهم فقط'**
  String get discoverMutual;

  /// No description provided for @discoverMutualHint.
  ///
  /// In ar, this message translates to:
  /// **'فقط من يظهر رقمك عندهم وتظهر أرقامهم عندك.'**
  String get discoverMutualHint;

  /// No description provided for @discoverNobody.
  ///
  /// In ar, this message translates to:
  /// **'لا أحد'**
  String get discoverNobody;

  /// No description provided for @discoverNobodyHint.
  ///
  /// In ar, this message translates to:
  /// **'لن يعثر عليك أحد عبر رقم هاتفك.'**
  String get discoverNobodyHint;

  /// No description provided for @storedHashesNotice.
  ///
  /// In ar, this message translates to:
  /// **'نحتفظ بـ {count} بصمة مشفّرة، بدون أي أرقام.'**
  String storedHashesNotice(int count);

  /// No description provided for @deleteContactData.
  ///
  /// In ar, this message translates to:
  /// **'حذف بيانات جهات الاتصال'**
  String get deleteContactData;

  /// No description provided for @deleteContactDataTitle.
  ///
  /// In ar, this message translates to:
  /// **'حذف كل البيانات'**
  String get deleteContactDataTitle;

  /// No description provided for @deleteContactDataConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف كل البصمات والمطابقات نهائيًا، وستختفي من قوائم اكتشاف الآخرين.'**
  String get deleteContactDataConfirm;

  /// No description provided for @deleteEverything.
  ///
  /// In ar, this message translates to:
  /// **'حذف الكل'**
  String get deleteEverything;

  /// No description provided for @contactDataDeleted.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف بيانات جهات الاتصال'**
  String get contactDataDeleted;

  /// No description provided for @blockUser.
  ///
  /// In ar, this message translates to:
  /// **'حظر المستخدم'**
  String get blockUser;

  /// No description provided for @unblockUser.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الحظر'**
  String get unblockUser;

  /// No description provided for @blockUserTitle.
  ///
  /// In ar, this message translates to:
  /// **'حظر {name}؟'**
  String blockUserTitle(String name);

  /// No description provided for @blockUserBody.
  ///
  /// In ar, this message translates to:
  /// **'لن يستطيع مراسلتك ولن تستطيع مراسلته. ولن يتم إبلاغه بأنك حظرته.'**
  String get blockUserBody;

  /// No description provided for @blockedUsers.
  ///
  /// In ar, this message translates to:
  /// **'المستخدمون المحظورون'**
  String get blockedUsers;

  /// No description provided for @blockedUsersEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لم تحظر أحدًا'**
  String get blockedUsersEmpty;

  /// No description provided for @blockedUsersEmptyHint.
  ///
  /// In ar, this message translates to:
  /// **'من تحظرهم سيظهرون هنا، ويمكنك التراجع في أي وقت.'**
  String get blockedUsersEmptyHint;

  /// No description provided for @blockedOn.
  ///
  /// In ar, this message translates to:
  /// **'محظور منذ {date}'**
  String blockedOn(String date);

  /// No description provided for @userBlocked.
  ///
  /// In ar, this message translates to:
  /// **'تم حظر {name}'**
  String userBlocked(String name);

  /// No description provided for @userUnblocked.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء حظر {name}'**
  String userUnblocked(String name);

  /// No description provided for @blockedBannerTitle.
  ///
  /// In ar, this message translates to:
  /// **'أنت حظرت هذا الشخص'**
  String get blockedBannerTitle;

  /// No description provided for @blockedBannerBody.
  ///
  /// In ar, this message translates to:
  /// **'ألغِ الحظر لاستئناف إرسال واستقبال الرسائل.'**
  String get blockedBannerBody;

  /// No description provided for @reportUser.
  ///
  /// In ar, this message translates to:
  /// **'الإبلاغ عن المستخدم'**
  String get reportUser;

  /// No description provided for @reportTitle.
  ///
  /// In ar, this message translates to:
  /// **'إبلاغ'**
  String get reportTitle;

  /// No description provided for @reportReasonQuestion.
  ///
  /// In ar, this message translates to:
  /// **'ما المشكلة؟'**
  String get reportReasonQuestion;

  /// No description provided for @reportDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل إضافية (اختياري)'**
  String get reportDetails;

  /// No description provided for @reportSubmit.
  ///
  /// In ar, this message translates to:
  /// **'إرسال البلاغ'**
  String get reportSubmit;

  /// No description provided for @reportSubmitted.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال البلاغ'**
  String get reportSubmitted;

  /// No description provided for @reportSubmittedBody.
  ///
  /// In ar, this message translates to:
  /// **'سيراجعه أحد المسؤولين. يمكنك أيضًا حظر هذا الشخص حتى لا يتواصل معك في أثناء ذلك.'**
  String get reportSubmittedBody;

  /// No description provided for @reportAlsoBlock.
  ///
  /// In ar, this message translates to:
  /// **'احظره أيضًا'**
  String get reportAlsoBlock;

  /// No description provided for @reportAlreadySent.
  ///
  /// In ar, this message translates to:
  /// **'سبق أن أبلغت عن هذه الرسالة'**
  String get reportAlreadySent;

  /// No description provided for @reportEvidenceNotice.
  ///
  /// In ar, this message translates to:
  /// **'تُرفق نسخة من الرسالة المُبلَّغ عنها، لتبقى متاحة حتى لو تم حذفها.'**
  String get reportEvidenceNotice;

  /// No description provided for @reasonSpam.
  ///
  /// In ar, this message translates to:
  /// **'رسائل مزعجة'**
  String get reasonSpam;

  /// No description provided for @reasonHarassment.
  ///
  /// In ar, this message translates to:
  /// **'تحرش أو إساءة'**
  String get reasonHarassment;

  /// No description provided for @reasonImpersonation.
  ///
  /// In ar, this message translates to:
  /// **'انتحال شخصية'**
  String get reasonImpersonation;

  /// No description provided for @reasonScam.
  ///
  /// In ar, this message translates to:
  /// **'احتيال أو نصب'**
  String get reasonScam;

  /// No description provided for @reasonIllegalContent.
  ///
  /// In ar, this message translates to:
  /// **'محتوى غير قانوني'**
  String get reasonIllegalContent;

  /// No description provided for @reasonLeakedClassified.
  ///
  /// In ar, this message translates to:
  /// **'مواد سرية'**
  String get reasonLeakedClassified;

  /// No description provided for @reasonOther.
  ///
  /// In ar, this message translates to:
  /// **'شيء آخر'**
  String get reasonOther;

  /// No description provided for @analyzeContent.
  ///
  /// In ar, this message translates to:
  /// **'تحليل المحتوى'**
  String get analyzeContent;

  /// No description provided for @myReports.
  ///
  /// In ar, this message translates to:
  /// **'بلاغاتي'**
  String get myReports;

  /// No description provided for @reportStatusOpen.
  ///
  /// In ar, this message translates to:
  /// **'قيد المراجعة'**
  String get reportStatusOpen;

  /// No description provided for @reportStatusReviewing.
  ///
  /// In ar, this message translates to:
  /// **'تحت المراجعة'**
  String get reportStatusReviewing;

  /// No description provided for @reportStatusActioned.
  ///
  /// In ar, this message translates to:
  /// **'تم اتخاذ إجراء'**
  String get reportStatusActioned;

  /// No description provided for @reportStatusDismissed.
  ///
  /// In ar, this message translates to:
  /// **'لم يُتخذ إجراء'**
  String get reportStatusDismissed;

  /// No description provided for @searchMessages.
  ///
  /// In ar, this message translates to:
  /// **'البحث في الرسائل'**
  String get searchMessages;

  /// No description provided for @searchMessagesTitle.
  ///
  /// In ar, this message translates to:
  /// **'البحث في الرسائل'**
  String get searchMessagesTitle;

  /// No description provided for @searchMessagesHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث داخل هذه المحادثة'**
  String get searchMessagesHint;

  /// No description provided for @searchMessagesOnDeviceNotice.
  ///
  /// In ar, this message translates to:
  /// **'البحث يتم على هذا الجهاز فقط. الرسائل مُشفّرة ولا يستطيع الخادم قراءتها، لذلك تشمل النتائج ما نزّله هذا الجهاز.'**
  String get searchMessagesOnDeviceNotice;

  /// No description provided for @searchNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج'**
  String get searchNoResults;

  /// No description provided for @searchNoResultsHint.
  ///
  /// In ar, this message translates to:
  /// **'جرّب كلمة أقصر أو إملاءً مختلفًا.'**
  String get searchNoResultsHint;

  /// No description provided for @searchResultCount.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{لا نتائج} =1{نتيجة واحدة} =2{نتيجتان} few{{count} نتائج} other{{count} نتيجة}}'**
  String searchResultCount(int count);

  /// No description provided for @secureIdentityChanged.
  ///
  /// In ar, this message translates to:
  /// **'رمز الأمان الخاص بهذا الشخص تغيّر. لم يتم إرسال الرسالة.'**
  String get secureIdentityChanged;

  /// No description provided for @secureIdentityChangedBody.
  ///
  /// In ar, this message translates to:
  /// **'يحدث هذا عند إعادة تثبيت التطبيق، وهو أيضًا شكل انتحال الشخصية. تأكّد منه عبر وسيلة أخرى قبل المتابعة.'**
  String get secureIdentityChangedBody;

  /// No description provided for @secureAcceptNewIdentity.
  ///
  /// In ar, this message translates to:
  /// **'تحققت منه — تابع'**
  String get secureAcceptNewIdentity;

  /// No description provided for @securePeerHasNoKeys.
  ///
  /// In ar, this message translates to:
  /// **'هذا الشخص لا يستطيع استقبال رسائل سرية بعد.'**
  String get securePeerHasNoKeys;

  /// No description provided for @securePeerHasNoKeysBody.
  ///
  /// In ar, this message translates to:
  /// **'جهازه لم ينشر مفاتيح التشفير. اطلب منه فتح IronLink مرة واحدة.'**
  String get securePeerHasNoKeysBody;

  /// No description provided for @secureEncryptFailed.
  ///
  /// In ar, this message translates to:
  /// **'لم تُرسل الرسالة، لأنه تعذّر تشفيرها.'**
  String get secureEncryptFailed;

  /// No description provided for @secureDecryptFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر فك تشفير إحدى الرسائل.'**
  String get secureDecryptFailed;

  /// No description provided for @secureMessageUnreadable.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر فك تشفير الرسالة'**
  String get secureMessageUnreadable;

  /// No description provided for @secretChatOn.
  ///
  /// In ar, this message translates to:
  /// **'المحادثة السرية مفعّلة'**
  String get secretChatOn;

  /// No description provided for @secretChatOff.
  ///
  /// In ar, this message translates to:
  /// **'المحادثة السرية غير مفعّلة'**
  String get secretChatOff;

  /// No description provided for @secretChatNotice.
  ///
  /// In ar, this message translates to:
  /// **'رسائل هذه المحادثة مشفّرة من طرف إلى طرف. الخادم يحفظ نصًا مشفّرًا لا يستطيع قراءته.'**
  String get secretChatNotice;

  /// No description provided for @secretChatAttachmentWarning.
  ///
  /// In ar, this message translates to:
  /// **'المرفقات ليست مشفّرة من طرف إلى طرف بعد — التشفير يشمل التعليقات فقط.'**
  String get secretChatAttachmentWarning;

  /// No description provided for @attachmentLoadFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل المرفق'**
  String get attachmentLoadFailed;

  /// No description provided for @attachmentTampered.
  ///
  /// In ar, this message translates to:
  /// **'هذا المرفق تم التلاعب به ولم يُفتح'**
  String get attachmentTampered;

  /// No description provided for @attachmentEncrypted.
  ///
  /// In ar, this message translates to:
  /// **'مرفق مشفّر'**
  String get attachmentEncrypted;

  /// No description provided for @chatNotEncryptedNotice.
  ///
  /// In ar, this message translates to:
  /// **'رسائل هذه المحادثة ليست مشفّرة من طرف إلى طرف. هي محميّة أثناء النقل، لكن الخادم يستطيع قراءتها.'**
  String get chatNotEncryptedNotice;

  /// No description provided for @messageNotEncrypted.
  ///
  /// In ar, this message translates to:
  /// **'غير مشفّرة من طرف إلى طرف'**
  String get messageNotEncrypted;

  /// No description provided for @play.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف مؤقت'**
  String get pause;

  /// No description provided for @recordVoiceNote.
  ///
  /// In ar, this message translates to:
  /// **'اضغط مطوّلاً لتسجيل رسالة صوتية'**
  String get recordVoiceNote;

  /// No description provided for @voiceNoteTooShort.
  ///
  /// In ar, this message translates to:
  /// **'اضغط مطوّلاً للتسجيل'**
  String get voiceNoteTooShort;

  /// No description provided for @groupNoMessages.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد رسائل بعد'**
  String get groupNoMessages;

  /// No description provided for @groupMessageUnreadable.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر فك تشفير الرسالة'**
  String get groupMessageUnreadable;

  /// No description provided for @groupNoLongerMember.
  ///
  /// In ar, this message translates to:
  /// **'لم تعد عضوًا في هذه المجموعة'**
  String get groupNoLongerMember;

  /// No description provided for @groupAnnouncementOnly.
  ///
  /// In ar, this message translates to:
  /// **'النشر في هذه المجموعة للمسؤولين فقط'**
  String get groupAnnouncementOnly;

  /// No description provided for @groupEncryptionNotice.
  ///
  /// In ar, this message translates to:
  /// **'رسائل هذه المجموعة مشفّرة من طرف إلى طرف. الخادم يوجّهها ولا يستطيع قراءتها.'**
  String get groupEncryptionNotice;

  /// No description provided for @groupRotationNotice.
  ///
  /// In ar, this message translates to:
  /// **'عند انضمام أو خروج أي شخص تتغيّر مفاتيح الجميع، فلا يستطيع من يخرج قراءة ما يُقال بعد ذلك.'**
  String get groupRotationNotice;

  /// No description provided for @groupMembersCount.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{لا أعضاء} =1{عضو واحد} =2{عضوان} few{{count} أعضاء} other{{count} عضوًا}}'**
  String groupMembersCount(int count);

  /// No description provided for @groupChat.
  ///
  /// In ar, this message translates to:
  /// **'محادثة المجموعة'**
  String get groupChat;

  /// No description provided for @leaveGroup.
  ///
  /// In ar, this message translates to:
  /// **'مغادرة المجموعة'**
  String get leaveGroup;

  /// No description provided for @leaveGroupConfirm.
  ///
  /// In ar, this message translates to:
  /// **'لن تصلك رسائل هذه المجموعة بعد الآن، ولن تستطيع قراءة ما يُقال بعد مغادرتك.'**
  String get leaveGroupConfirm;

  /// No description provided for @groupLeft.
  ///
  /// In ar, this message translates to:
  /// **'غادرت المجموعة'**
  String get groupLeft;

  /// No description provided for @ownerMustTransfer.
  ///
  /// In ar, this message translates to:
  /// **'سلّم ملكية المجموعة قبل المغادرة'**
  String get ownerMustTransfer;

  /// No description provided for @verificationTimedOut.
  ///
  /// In ar, this message translates to:
  /// **'خدمة التحقق لم تستجب. اتصالك سليم — غالبًا التطبيق لسه غير مُهيّأ لتسجيل الدخول بالهاتف.'**
  String get verificationTimedOut;

  /// No description provided for @aiConsentTitle.
  ///
  /// In ar, this message translates to:
  /// **'مميزات الذكاء الاصطناعي في هذه المحادثة'**
  String get aiConsentTitle;

  /// No description provided for @aiConsentWhatHappens.
  ///
  /// In ar, this message translates to:
  /// **'للتلخيص أو الترجمة أو اقتراح الردود، يفك التطبيق تشفير الرسائل ويرسلها إلى مزوّد ذكاء اصطناعي خارج IronLink. أي أنها تغادر جهازك ويقرأها طرف ثالث.'**
  String get aiConsentWhatHappens;

  /// No description provided for @aiConsentEncryptionNote.
  ///
  /// In ar, this message translates to:
  /// **'كل رسالة أخرى في التطبيق مشفّرة من طرف إلى طرف ولا يستطيع خادمنا قراءتها. هذه المميزات هي الاستثناء الوحيد، ولهذا فهي مغلقة ما لم تطلبها.'**
  String get aiConsentEncryptionNote;

  /// No description provided for @aiConsentToggle.
  ///
  /// In ar, this message translates to:
  /// **'السماح بمميزات الذكاء الاصطناعي هنا'**
  String get aiConsentToggle;

  /// No description provided for @aiConsentToggleHint.
  ///
  /// In ar, this message translates to:
  /// **'ينطبق على محادثتك مع {name} فقط.'**
  String aiConsentToggleHint(String name);

  /// No description provided for @aiConsentWaitingOn.
  ///
  /// In ar, this message translates to:
  /// **'في انتظار موافقة {names}. حتى ذلك الحين لا يُرسل أي شيء.'**
  String aiConsentWaitingOn(String names);

  /// No description provided for @aiConsentWaitingGeneric.
  ///
  /// In ar, this message translates to:
  /// **'في انتظار موافقة بقية المشاركين. حتى ذلك الحين لا يُرسل أي شيء.'**
  String get aiConsentWaitingGeneric;

  /// No description provided for @aiConsentEveryoneAgreed.
  ///
  /// In ar, this message translates to:
  /// **'وافق الجميع. المميزات متاحة في هذه المحادثة.'**
  String get aiConsentEveryoneAgreed;

  /// No description provided for @aiConsentWithdrawNote.
  ///
  /// In ar, this message translates to:
  /// **'يمكنك سحب الموافقة في أي وقت. هذا يوقف إرسال أي شيء بعدها، لكنه لا يستعيد ما أُرسل بالفعل.'**
  String get aiConsentWithdrawNote;

  /// No description provided for @aiConsentRequired.
  ///
  /// In ar, this message translates to:
  /// **'يجب أن يوافق كل من في المحادثة قبل استخدام مميزات الذكاء الاصطناعي.'**
  String get aiConsentRequired;

  /// No description provided for @aiFeatures.
  ///
  /// In ar, this message translates to:
  /// **'مميزات الذكاء الاصطناعي'**
  String get aiFeatures;

  /// No description provided for @aiSummarise.
  ///
  /// In ar, this message translates to:
  /// **'تلخيص المحادثة'**
  String get aiSummarise;

  /// No description provided for @signOut.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get signOut;

  /// No description provided for @signOutConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيتم تسجيل الخروج من هذا الجهاز ومسح كل ما هو مخزّن عليه — سجل رسائلك ومفاتيح التشفير وأي مسودات. ولأن الرسائل مشفّرة من طرف إلى طرف، لن يستطيع الخادم استعادة هذا السجل بعدها.'**
  String get signOutConfirm;

  /// No description provided for @smartAlertTitle.
  ///
  /// In ar, this message translates to:
  /// **'تنبيه ذكي'**
  String get smartAlertTitle;

  /// No description provided for @smartAlertOpenDocument.
  ///
  /// In ar, this message translates to:
  /// **'فتح المستند'**
  String get smartAlertOpenDocument;

  /// No description provided for @smartAlertAcknowledge.
  ///
  /// In ar, this message translates to:
  /// **'تم الاطلاع'**
  String get smartAlertAcknowledge;

  /// No description provided for @smartAlertMoreCount.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{تنبيه ذكي واحد} =2{تنبيهان ذكيان} few{{count} تنبيهات ذكية} other{{count} تنبيهًا ذكيًا}}'**
  String smartAlertMoreCount(int count);

  /// No description provided for @smartAlertSemantics.
  ///
  /// In ar, this message translates to:
  /// **'تنبيه ذكي: عُثر على \"{matched}\" في مستند. السياق: {context}'**
  String smartAlertSemantics(String matched, String context);

  /// No description provided for @alertCenterTitle.
  ///
  /// In ar, this message translates to:
  /// **'التنبيهات الذكية'**
  String get alertCenterTitle;

  /// No description provided for @alertCenterEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تنبيهات'**
  String get alertCenterEmpty;

  /// No description provided for @alertCenterEmptyHint.
  ///
  /// In ar, this message translates to:
  /// **'عندما تصل صورة أو مستند يحتوي على إحدى كلماتك، سيظهر التنبيه هنا.'**
  String get alertCenterEmptyHint;

  /// No description provided for @alertFilterAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get alertFilterAll;

  /// No description provided for @alertFilterUnacknowledged.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم الاطلاع'**
  String get alertFilterUnacknowledged;

  /// No description provided for @alertFilterAcknowledged.
  ///
  /// In ar, this message translates to:
  /// **'تم الاطلاع'**
  String get alertFilterAcknowledged;

  /// No description provided for @alertFilterHighConfidence.
  ///
  /// In ar, this message translates to:
  /// **'عالية الثقة'**
  String get alertFilterHighConfidence;

  /// No description provided for @alertSectionToday.
  ///
  /// In ar, this message translates to:
  /// **'اليوم'**
  String get alertSectionToday;

  /// No description provided for @alertSectionYesterday.
  ///
  /// In ar, this message translates to:
  /// **'أمس'**
  String get alertSectionYesterday;

  /// No description provided for @alertSectionEarlier.
  ///
  /// In ar, this message translates to:
  /// **'أقدم'**
  String get alertSectionEarlier;

  /// No description provided for @alertStatusAcknowledged.
  ///
  /// In ar, this message translates to:
  /// **'تم الاطلاع'**
  String get alertStatusAcknowledged;

  /// No description provided for @alertStatusPresented.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم الاطلاع'**
  String get alertStatusPresented;

  /// No description provided for @alertStatusOpened.
  ///
  /// In ar, this message translates to:
  /// **'فُتح المستند، ولم يتم الاطلاع'**
  String get alertStatusOpened;

  /// No description provided for @alertStatusExpired.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحيته'**
  String get alertStatusExpired;

  /// No description provided for @alertStatusDismissed.
  ///
  /// In ar, this message translates to:
  /// **'أُهمل'**
  String get alertStatusDismissed;

  /// No description provided for @alertRetentionNote.
  ///
  /// In ar, this message translates to:
  /// **'تُحفظ التنبيهات ٤٨ ساعة ثم تُحذف تلقائيًا.'**
  String get alertRetentionNote;

  /// No description provided for @alertPageNumber.
  ///
  /// In ar, this message translates to:
  /// **'صفحة {page}'**
  String alertPageNumber(int page);

  /// No description provided for @alertProcessedLocally.
  ///
  /// In ar, this message translates to:
  /// **'تمت المعالجة على هذا الجهاز'**
  String get alertProcessedLocally;

  /// No description provided for @alertProcessedInCloud.
  ///
  /// In ar, this message translates to:
  /// **'تمت المعالجة في السحابة'**
  String get alertProcessedInCloud;

  /// No description provided for @alertSuppressedByCap.
  ///
  /// In ar, this message translates to:
  /// **'تجاوز الحد اليومي لهذه الكلمة'**
  String get alertSuppressedByCap;

  /// No description provided for @keywordManagementTitle.
  ///
  /// In ar, this message translates to:
  /// **'الكلمات المفتاحية'**
  String get keywordManagementTitle;

  /// No description provided for @keywordManagementSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'كلمات خاصة بهذه المحادثة وحدها. لا يراها المرسل ولا مشرفو المجموعة ولا أي شخص آخر.'**
  String get keywordManagementSubtitle;

  /// No description provided for @keywordAddTitle.
  ///
  /// In ar, this message translates to:
  /// **'إضافة كلمة'**
  String get keywordAddTitle;

  /// No description provided for @keywordEditTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعديل الكلمة'**
  String get keywordEditTitle;

  /// No description provided for @keywordFieldLabel.
  ///
  /// In ar, this message translates to:
  /// **'الكلمة'**
  String get keywordFieldLabel;

  /// No description provided for @keywordFieldHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب كلمة أو عبارة'**
  String get keywordFieldHint;

  /// No description provided for @keywordPriorityLabel.
  ///
  /// In ar, this message translates to:
  /// **'الأولوية'**
  String get keywordPriorityLabel;

  /// No description provided for @keywordPriorityLow.
  ///
  /// In ar, this message translates to:
  /// **'منخفضة'**
  String get keywordPriorityLow;

  /// No description provided for @keywordPriorityMedium.
  ///
  /// In ar, this message translates to:
  /// **'متوسطة'**
  String get keywordPriorityMedium;

  /// No description provided for @keywordPriorityHigh.
  ///
  /// In ar, this message translates to:
  /// **'عالية'**
  String get keywordPriorityHigh;

  /// No description provided for @keywordPriorityCritical.
  ///
  /// In ar, this message translates to:
  /// **'حرجة'**
  String get keywordPriorityCritical;

  /// No description provided for @keywordMatchModeLabel.
  ///
  /// In ar, this message translates to:
  /// **'طريقة المطابقة'**
  String get keywordMatchModeLabel;

  /// No description provided for @keywordMatchExact.
  ///
  /// In ar, this message translates to:
  /// **'كلمة كاملة'**
  String get keywordMatchExact;

  /// No description provided for @keywordMatchPhrase.
  ///
  /// In ar, this message translates to:
  /// **'عبارة'**
  String get keywordMatchPhrase;

  /// No description provided for @keywordMatchFuzzy.
  ///
  /// In ar, this message translates to:
  /// **'تسامح مع أخطاء المسح'**
  String get keywordMatchFuzzy;

  /// No description provided for @keywordMatchRegex.
  ///
  /// In ar, this message translates to:
  /// **'نمط متقدم'**
  String get keywordMatchRegex;

  /// No description provided for @keywordCategoryLabel.
  ///
  /// In ar, this message translates to:
  /// **'التصنيف (اختياري)'**
  String get keywordCategoryLabel;

  /// No description provided for @keywordNotesLabel.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظة خاصة (اختياري)'**
  String get keywordNotesLabel;

  /// No description provided for @keywordCaseSensitiveLabel.
  ///
  /// In ar, this message translates to:
  /// **'مطابقة حالة الأحرف'**
  String get keywordCaseSensitiveLabel;

  /// No description provided for @keywordDailyCapLabel.
  ///
  /// In ar, this message translates to:
  /// **'حد التنبيهات اليومي (اختياري)'**
  String get keywordDailyCapLabel;

  /// No description provided for @keywordEnabledLabel.
  ///
  /// In ar, this message translates to:
  /// **'مُفعّلة'**
  String get keywordEnabledLabel;

  /// No description provided for @keywordDeleteConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف هذه الكلمة وكل التنبيهات التي أنشأتها. لا يمكن التراجع.'**
  String get keywordDeleteConfirm;

  /// No description provided for @keywordEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد كلمات لهذه المحادثة بعد'**
  String get keywordEmpty;

  /// No description provided for @keywordTestTitle.
  ///
  /// In ar, this message translates to:
  /// **'جرّب الكلمة'**
  String get keywordTestTitle;

  /// No description provided for @keywordTestHint.
  ///
  /// In ar, this message translates to:
  /// **'الصق نصًا لترى إن كانت الكلمة ستطابقه'**
  String get keywordTestHint;

  /// No description provided for @keywordTestMatched.
  ///
  /// In ar, this message translates to:
  /// **'تطابق'**
  String get keywordTestMatched;

  /// No description provided for @keywordTestNoMatch.
  ///
  /// In ar, this message translates to:
  /// **'لا تطابق'**
  String get keywordTestNoMatch;

  /// No description provided for @keywordErrorTooShort.
  ///
  /// In ar, this message translates to:
  /// **'الكلمة قصيرة جدًا — حرفان على الأقل.'**
  String get keywordErrorTooShort;

  /// No description provided for @keywordErrorTooLong.
  ///
  /// In ar, this message translates to:
  /// **'الكلمة طويلة جدًا.'**
  String get keywordErrorTooLong;

  /// No description provided for @keywordErrorNotMatchable.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد في هذه الكلمة ما يمكن مطابقته داخل مستند.'**
  String get keywordErrorNotMatchable;

  /// No description provided for @keywordErrorStopWord.
  ///
  /// In ar, this message translates to:
  /// **'هذه كلمة رابطة شائعة، وستظهر في كل مستند تقريبًا.'**
  String get keywordErrorStopWord;

  /// No description provided for @keywordErrorRegexInvalid.
  ///
  /// In ar, this message translates to:
  /// **'النمط غير صالح.'**
  String get keywordErrorRegexInvalid;

  /// No description provided for @keywordErrorRegexUnsafe.
  ///
  /// In ar, this message translates to:
  /// **'قد يستغرق هذا النمط وقتًا غير محدود في التنفيذ.'**
  String get keywordErrorRegexUnsafe;

  /// No description provided for @keywordErrorDuplicate.
  ///
  /// In ar, this message translates to:
  /// **'هذه الكلمة موجودة بالفعل في هذه المحادثة.'**
  String get keywordErrorDuplicate;

  /// No description provided for @documentCheckingNow.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ فحص المستند…'**
  String get documentCheckingNow;

  /// No description provided for @documentCheckedNothingFound.
  ///
  /// In ar, this message translates to:
  /// **'فُحص المستند ولم يُعثر على شيء'**
  String get documentCheckedNothingFound;

  /// No description provided for @documentUnreadable.
  ///
  /// In ar, this message translates to:
  /// **'تعذّرت قراءة هذا المستند بشكل موثوق.'**
  String get documentUnreadable;

  /// No description provided for @documentTooLowResolution.
  ///
  /// In ar, this message translates to:
  /// **'دقة الصورة أقل من أن تُقرأ بشكل موثوق.'**
  String get documentTooLowResolution;

  /// No description provided for @documentUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'هذا النوع من الملفات غير مدعوم للفحص.'**
  String get documentUnsupported;

  /// No description provided for @documentTooLarge.
  ///
  /// In ar, this message translates to:
  /// **'الملف أكبر من الحد المسموح للفحص.'**
  String get documentTooLarge;

  /// No description provided for @documentTruncated.
  ///
  /// In ar, this message translates to:
  /// **'مستند طويل — فُحصت الصفحات الأولى فقط ({pages} صفحة).'**
  String documentTruncated(int pages);

  /// No description provided for @securityCenterLocalExplained.
  ///
  /// In ar, this message translates to:
  /// **'لا يغادر أي مستند هذا الجهاز أثناء الفحص، والكلمات المفتاحية مخزَّنة هنا فقط.'**
  String get securityCenterLocalExplained;

  /// No description provided for @securityCenterNoLocalEngine.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد محرك قراءة على هذا الجهاز، لذا لا يمكن فحص الصور. لن يُرسَل أي شيء إلى السحابة تلقائيًا.'**
  String get securityCenterNoLocalEngine;

  /// No description provided for @senderReportTitle.
  ///
  /// In ar, this message translates to:
  /// **'حالة المستلمين'**
  String get senderReportTitle;

  /// No description provided for @senderReportAlertRaised.
  ///
  /// In ar, this message translates to:
  /// **'صدر تنبيه ذكي'**
  String get senderReportAlertRaised;

  /// No description provided for @senderReportNoAlert.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد تنبيه'**
  String get senderReportNoAlert;

  /// No description provided for @senderReportKeywordHidden.
  ///
  /// In ar, this message translates to:
  /// **'الكلمة المفتاحية خاصة بالمستلم ولا تظهر لك'**
  String get senderReportKeywordHidden;

  /// No description provided for @senderReportUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'لم يسمح المستلم بمشاركة هذه الحالة'**
  String get senderReportUnavailable;

  /// No description provided for @securityCenterTitle.
  ///
  /// In ar, this message translates to:
  /// **'مركز الأمان'**
  String get securityCenterTitle;

  /// No description provided for @securityCenterSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'كل ما يظهر هنا مبني على معلومات يعرفها النظام فعلاً. لا يوجد تقدير ولا تخمين.'**
  String get securityCenterSubtitle;

  /// No description provided for @securityLevelHigh.
  ///
  /// In ar, this message translates to:
  /// **'الحالة جيدة'**
  String get securityLevelHigh;

  /// No description provided for @securityLevelMedium.
  ///
  /// In ar, this message translates to:
  /// **'يستحق المراجعة'**
  String get securityLevelMedium;

  /// No description provided for @securityLevelLow.
  ///
  /// In ar, this message translates to:
  /// **'يحتاج انتباهك الآن'**
  String get securityLevelLow;

  /// No description provided for @securityActiveSessions.
  ///
  /// In ar, this message translates to:
  /// **'الأجهزة المسجَّل دخولها'**
  String get securityActiveSessions;

  /// No description provided for @securityThisDevice.
  ///
  /// In ar, this message translates to:
  /// **'هذا الجهاز'**
  String get securityThisDevice;

  /// No description provided for @securityUnknownDevice.
  ///
  /// In ar, this message translates to:
  /// **'جهاز غير معروف'**
  String get securityUnknownDevice;

  /// No description provided for @securityLastActive.
  ///
  /// In ar, this message translates to:
  /// **'آخر نشاط {when}'**
  String securityLastActive(String when);

  /// No description provided for @securityNeverActive.
  ///
  /// In ar, this message translates to:
  /// **'لم يُستخدم بعد'**
  String get securityNeverActive;

  /// No description provided for @securitySignOutDevice.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل خروج هذا الجهاز'**
  String get securitySignOutDevice;

  /// No description provided for @securitySignOutDeviceConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيتم تسجيل خروج هذا الجهاز فورًا وقطع اتصاله. لن يتأثر أي جهاز آخر.'**
  String get securitySignOutDeviceConfirm;

  /// No description provided for @securitySecureAccount.
  ///
  /// In ar, this message translates to:
  /// **'تأمين حسابي'**
  String get securitySecureAccount;

  /// No description provided for @securitySecureAccountConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيتم تسجيل خروج كل الأجهزة الأخرى. هذا الجهاز يبقى مسجَّلًا.'**
  String get securitySecureAccountConfirm;

  /// No description provided for @securitySecureAccountDone.
  ///
  /// In ar, this message translates to:
  /// **'تم تسجيل خروج كل الأجهزة الأخرى.'**
  String get securitySecureAccountDone;

  /// No description provided for @securitySecureAccountPartial.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تسجيل خروج {count} من الأجهزة. القائمة أدناه تعرض ما هو مسجَّل فعلًا الآن.'**
  String securitySecureAccountPartial(int count);

  /// No description provided for @securityNoOtherDevices.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد أجهزة أخرى مسجَّلة'**
  String get securityNoOtherDevices;

  /// No description provided for @securityFindingOtherDevices.
  ///
  /// In ar, this message translates to:
  /// **'أنت مسجَّل الدخول على أكثر من جهاز'**
  String get securityFindingOtherDevices;

  /// No description provided for @securityFindingOtherDevicesWhy.
  ///
  /// In ar, this message translates to:
  /// **'ليست مشكلة بحد ذاتها. تُذكر لأنها أول ما تحتاج معرفته لو وصل أحد إلى حسابك.'**
  String get securityFindingOtherDevicesWhy;

  /// No description provided for @securityFindingStaleSession.
  ///
  /// In ar, this message translates to:
  /// **'جهاز لم يُستخدم منذ أكثر من أسبوعين'**
  String get securityFindingStaleSession;

  /// No description provided for @securityFindingStaleSessionWhy.
  ///
  /// In ar, this message translates to:
  /// **'قد يكون جهازًا تستخدمه أحيانًا. راجعه، وسجِّل خروجه إن لم تعرفه.'**
  String get securityFindingStaleSessionWhy;

  /// No description provided for @securityFindingEncryptionOn.
  ///
  /// In ar, this message translates to:
  /// **'التشفير من طرف إلى طرف مُفعَّل افتراضيًا'**
  String get securityFindingEncryptionOn;

  /// No description provided for @securityFindingEncryptionOnWhy.
  ///
  /// In ar, this message translates to:
  /// **'الخادم لا يملك المفتاح، ولا يستطيع قراءة رسائلك ولا مرفقاتك.'**
  String get securityFindingEncryptionOnWhy;

  /// No description provided for @securityFindingEncryptionOff.
  ///
  /// In ar, this message translates to:
  /// **'التشفير ليس هو الافتراضي على هذا الجهاز'**
  String get securityFindingEncryptionOff;

  /// No description provided for @securityFindingEncryptionOffWhy.
  ///
  /// In ar, this message translates to:
  /// **'هذا أخطر ما يمكن أن يظهر في هذه الشاشة. أعد تشغيل التطبيق، وإن استمر فالمشكلة تحتاج فحصًا.'**
  String get securityFindingEncryptionOffWhy;

  /// No description provided for @securityFindingKeywordsLocal.
  ///
  /// In ar, this message translates to:
  /// **'كلماتك المفتاحية مخزَّنة على هذا الجهاز فقط'**
  String get securityFindingKeywordsLocal;

  /// No description provided for @securityFindingKeywordsLocalWhy.
  ///
  /// In ar, this message translates to:
  /// **'الخادم لم يستلمها أصلًا، فلا يمكن أن تُفشى منه.'**
  String get securityFindingKeywordsLocalWhy;

  /// No description provided for @securityFindingCloudOcr.
  ///
  /// In ar, this message translates to:
  /// **'فحص المستندات في السحابة مُفعَّل'**
  String get securityFindingCloudOcr;

  /// No description provided for @securityFindingCloudOcrWhy.
  ///
  /// In ar, this message translates to:
  /// **'أنت اخترت هذا. معناه أن المستند قد يُقرأ خارج جهازك عند تعذّر القراءة محليًا.'**
  String get securityFindingCloudOcrWhy;

  /// No description provided for @securityWhyLabel.
  ///
  /// In ar, this message translates to:
  /// **'لماذا أرى هذا؟'**
  String get securityWhyLabel;

  /// No description provided for @securityCheckedNothingWrong.
  ///
  /// In ar, this message translates to:
  /// **'تم الفحص، ولا يوجد ما يستدعي القلق'**
  String get securityCheckedNothingWrong;

  /// No description provided for @securityLoadFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل حالة الأمان'**
  String get securityLoadFailed;

  /// No description provided for @safetyWarningTitle.
  ///
  /// In ar, this message translates to:
  /// **'تنبيه أمان'**
  String get safetyWarningTitle;

  /// No description provided for @safetyDismiss.
  ///
  /// In ar, this message translates to:
  /// **'إخفاء'**
  String get safetyDismiss;

  /// No description provided for @safetyCredentialRequest.
  ///
  /// In ar, this message translates to:
  /// **'الرسالة دي بتطلب كود تحقق'**
  String get safetyCredentialRequest;

  /// No description provided for @safetyCredentialRequestWhy.
  ///
  /// In ar, this message translates to:
  /// **'IronLink بيبعت أكواد التحقق لك انت وحدك. أي حد يطلب منك الكود — حتى لو قال إنه من الدعم — بيحاول يدخل حسابك. متبعتوش لأي حد.'**
  String get safetyCredentialRequestWhy;

  /// No description provided for @safetySuspiciousLink.
  ///
  /// In ar, this message translates to:
  /// **'فيه رابط شكله مضلل'**
  String get safetySuspiciousLink;

  /// No description provided for @safetySuspiciousLinkWhy.
  ///
  /// In ar, this message translates to:
  /// **'العنوان ده مكتوب بطريقة تخليه يبان زي موقع تاني. اتفحص على جهازك، ومحدش غيرك شافه.'**
  String get safetySuspiciousLinkWhy;

  /// No description provided for @safetyPaymentRequest.
  ///
  /// In ar, this message translates to:
  /// **'طلب تحويل فلوس مع علامات أخرى'**
  String get safetyPaymentRequest;

  /// No description provided for @safetyPaymentRequestWhy.
  ///
  /// In ar, this message translates to:
  /// **'طلب الفلوس لوحده عادي. اللي خلانا نقول ده إنه جه مع إشارة تانية — استعجال، أو ادعاء صفة، أو رابط مشبوه.'**
  String get safetyPaymentRequestWhy;

  /// No description provided for @safetyAuthorityClaim.
  ///
  /// In ar, this message translates to:
  /// **'المُرسل بيدّعي صفة رسمية'**
  String get safetyAuthorityClaim;

  /// No description provided for @safetyAuthorityClaimWhy.
  ///
  /// In ar, this message translates to:
  /// **'حد بيقول إنه من الدعم أو البنك أو الإدارة. الجهات دي مابتطلبش أكواد ولا كلمات سر في رسايل.'**
  String get safetyAuthorityClaimWhy;

  /// No description provided for @safetyOffPlatform.
  ///
  /// In ar, this message translates to:
  /// **'طلب ينقل الكلام لتطبيق تاني'**
  String get safetyOffPlatform;

  /// No description provided for @safetyOffPlatformWhy.
  ///
  /// In ar, this message translates to:
  /// **'نقل المحادثة لمكان مش مشفّر خطوة شائعة قبل الاحتيال. ممكن يكون سبب عادي، بس يستاهل تتأكد.'**
  String get safetyOffPlatformWhy;

  /// No description provided for @safetyUrgency.
  ///
  /// In ar, this message translates to:
  /// **'استعجال مع علامات أخرى'**
  String get safetyUrgency;

  /// No description provided for @safetyUrgencyWhy.
  ///
  /// In ar, this message translates to:
  /// **'الضغط بالوقت بيمنع الناس من التفكير. الاستعجال لوحده عادي — ظهر هنا مع إشارة تانية.'**
  String get safetyUrgencyWhy;

  /// No description provided for @attachUnsupportedFormat.
  ///
  /// In ar, this message translates to:
  /// **'الملف ده مش من نوع نقدر ننضّفه من البيانات المخفية، فمابعتناهوش. الصور والتسجيلات الصوتية شغالة عادي.'**
  String get attachUnsupportedFormat;

  /// No description provided for @connectionOffline.
  ///
  /// In ar, this message translates to:
  /// **'مافيش اتصال. رسايلك هتتبعت أول ما ترجع.'**
  String get connectionOffline;

  /// No description provided for @connectionConnecting.
  ///
  /// In ar, this message translates to:
  /// **'بيحاول يتصل…'**
  String get connectionConnecting;

  /// No description provided for @connectionOutdated.
  ///
  /// In ar, this message translates to:
  /// **'النسخة دي بقت قديمة. حدّث التطبيق عشان تكمل.'**
  String get connectionOutdated;

  /// No description provided for @replyToYou.
  ///
  /// In ar, this message translates to:
  /// **'أنت'**
  String get replyToYou;

  /// No description provided for @replyToThem.
  ///
  /// In ar, this message translates to:
  /// **'رد على'**
  String get replyToThem;

  /// No description provided for @replyUnavailableTitle.
  ///
  /// In ar, this message translates to:
  /// **'الرسالة الأصلية'**
  String get replyUnavailableTitle;

  /// No description provided for @replyUnavailableBody.
  ///
  /// In ar, this message translates to:
  /// **'مش موجودة على الجهاز ده'**
  String get replyUnavailableBody;

  /// No description provided for @replyOriginalDeleted.
  ///
  /// In ar, this message translates to:
  /// **'الرسالة دي اتشالت'**
  String get replyOriginalDeleted;

  /// No description provided for @replyKindImage.
  ///
  /// In ar, this message translates to:
  /// **'صورة'**
  String get replyKindImage;

  /// No description provided for @replyKindVoice.
  ///
  /// In ar, this message translates to:
  /// **'رسالة صوتية'**
  String get replyKindVoice;

  /// No description provided for @replyKindAttachment.
  ///
  /// In ar, this message translates to:
  /// **'مرفق'**
  String get replyKindAttachment;

  /// No description provided for @replySwipeHint.
  ///
  /// In ar, this message translates to:
  /// **'اسحب الرسالة عشان ترد عليها'**
  String get replySwipeHint;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return LAr();
    case 'en':
      return LEn();
  }

  throw FlutterError(
      'L.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
