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

  /// No description provided for @acknowledged.
  ///
  /// In ar, this message translates to:
  /// **'علمت'**
  String get acknowledged;
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
