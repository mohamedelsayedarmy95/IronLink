// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get authTagline => 'Private · Secure · Limitless';

  @override
  String get authSubtitle => 'The Trusted Messaging System';

  @override
  String get featureE2EE => 'End-to-end encryption';

  @override
  String get featureVerifiedIdentity => 'Verified identity';

  @override
  String get featurePrivacyByDesign => 'Privacy by design';

  @override
  String get featureDeviceSecurity => 'Secure on every device';

  @override
  String get getStarted => 'Get Started';

  @override
  String get alreadyHaveAccount => 'Already have an account? ';

  @override
  String get signIn => 'Sign in';

  @override
  String get devGuestLogin => 'Guest login (no server)';

  @override
  String get secureSignInTitle => 'Secure Sign-In';

  @override
  String get phoneStepSubtitle => 'Enter your unit-registered phone number';

  @override
  String get otpStepSubtitle =>
      'Enter the verification code sent to you by SMS';

  @override
  String get militaryIdStepSubtitle =>
      'Enter your military ID to finish verification';

  @override
  String get phoneNumberLabel => 'Phone number';

  @override
  String get otpCodeLabel => 'Verification code';

  @override
  String get sendVerificationCode => 'Send verification code';

  @override
  String get resendCode => 'Resend code';

  @override
  String resendCodeCountdown(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get militaryIdHint => 'Military ID';

  @override
  String get showPassword => 'Show';

  @override
  String get hidePassword => 'Hide';

  @override
  String get confirmSignIn => 'Confirm sign-in';

  @override
  String get e2eeNotice =>
      'Your details are end-to-end encrypted — the server can\'t read them.';

  @override
  String get errorFirebaseTokenFailed =>
      'Couldn\'t get a verification token from Firebase';

  @override
  String get errorNetwork =>
      'Couldn\'t reach the server — check your connection';

  @override
  String get errorUnexpected => 'Something went wrong';

  @override
  String get errorInvalidPhone => 'Invalid phone number';

  @override
  String get errorTooManyRequests => 'Too many attempts — try again later';

  @override
  String get errorInvalidCode => 'Incorrect verification code';

  @override
  String get errorSessionExpired => 'Code expired — resend it';

  @override
  String get errorPhoneVerificationFailed =>
      'Something went wrong verifying your phone';

  @override
  String get noChatsYet => 'No conversations yet';

  @override
  String get noChatsYetHint =>
      'Start a secure conversation with one of your contacts.';

  @override
  String get onlineNow => 'Online now';

  @override
  String get startSecretChat => 'Start secret chat';

  @override
  String get secretChatComingSoon =>
      'Secret chat enabled (arriving in a future update)';

  @override
  String get messageDeleted => 'This message was deleted';

  @override
  String get translate => 'Translate';

  @override
  String get reportMessage => 'Report message';

  @override
  String get deleteForEveryone => 'Delete for everyone';

  @override
  String get deleteForEveryoneHint => 'Available for 5 minutes after sending';

  @override
  String typingIndicator(String name) {
    return '$name is typing';
  }

  @override
  String get attach => 'Attach';

  @override
  String get messageHint => 'Type a message…';

  @override
  String get send => 'Send';

  @override
  String get notInAnyGroupYet => 'You\'re not a member of any group yet';

  @override
  String get notInAnyGroupYetHint =>
      'Create a group or join one to coordinate with your team.';

  @override
  String groupMembersTitle(String name, int count) {
    return '$name — $count members';
  }

  @override
  String get announcementChannelReadOnly => 'Announcement channel — read only';

  @override
  String memberCount(int count) {
    return '$count members';
  }

  @override
  String get roleOwner => 'Group owner';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleModerator => 'Moderator';

  @override
  String get roleObserver => 'Observer — read only';

  @override
  String get roleMember => 'Member';

  @override
  String get channelsTitle => 'Channels';

  @override
  String get createChannel => 'Create channel';

  @override
  String get noChannelsYet => 'No channels yet';

  @override
  String get noChannelsYetHint =>
      'Subscribe to a channel to receive official announcements.';

  @override
  String get channelsLoadFailedTitle => 'Couldn\'t load channels';

  @override
  String subscriberCount(int count) {
    return '$count subscribers';
  }

  @override
  String get ocrKeywordsTitle => 'OCR Keywords';

  @override
  String get ocrKeywordsDescription =>
      'You\'ll be alerted automatically if any of these words appear in scanned (OCR) text inside an image or document.';

  @override
  String get newKeywordLabel => 'New keyword';

  @override
  String get newKeywordHint => 'Type a keyword and add it';

  @override
  String get noKeywordsYet => 'No keywords added yet';

  @override
  String get add => 'Add';

  @override
  String get ocrKeywordExists => 'That keyword is already in your list.';

  @override
  String get ocrKeywordsEmptyHint =>
      'Add a word to be alerted whenever it appears in a scanned image or document.';

  @override
  String get retry => 'Retry';

  @override
  String get delete => 'Delete';

  @override
  String get ocrLoadFailedTitle => 'Couldn\'t load keywords';

  @override
  String get ocrAddFailed => 'That keyword wasn\'t added. Try again.';

  @override
  String get ocrRemoveFailed => 'That keyword wasn\'t removed. Try again.';

  @override
  String get failureOffline =>
      'You appear to be offline. Check your connection and try again.';

  @override
  String get failureTimeout =>
      'The server is taking longer than usual. Try again in a moment.';

  @override
  String get failureServer =>
      'We can\'t reach the server right now. Try again shortly.';

  @override
  String get failureUnauthorized =>
      'Your session has expired. Please sign in again.';

  @override
  String get failureRejected =>
      'That request couldn\'t be completed. Check the details and try again.';

  @override
  String get failureInsecure =>
      'The connection\'s security couldn\'t be verified. Nothing was sent.';

  @override
  String get failureUnknown => 'Something went wrong. Please try again.';

  @override
  String get tabChats => 'Chats';

  @override
  String get tabGroups => 'Groups';

  @override
  String get tabBroadcasts => 'Broadcasts';

  @override
  String get tabSettings => 'Settings';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get releaseToCancel => 'Release to cancel';

  @override
  String get dragToCancel => '← Slide to cancel';

  @override
  String get voiceUploadFailed => 'Failed to upload the voice message';

  @override
  String get uploadFailed => 'That attachment didn\'t upload. Try again.';

  @override
  String get acknowledged => 'Got it';
}
