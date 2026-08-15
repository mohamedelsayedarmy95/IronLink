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
  String get attachGallery => 'Gallery';

  @override
  String get attachCamera => 'Camera';

  @override
  String get attachDocument => 'PDF document';

  @override
  String get attachPdfComingSoon => 'Picking PDF files isn\'t available yet.';

  @override
  String get captionHint => 'Add a caption…';

  @override
  String ocrAlertFound(String keyword) {
    return 'The keyword \"$keyword\" was found in an uploaded file.';
  }

  @override
  String get acknowledged => 'Got it';

  @override
  String get completeVerificationForm => 'Complete Verification Form';

  @override
  String joinRequestFor(String group) {
    return 'Join request: $group';
  }

  @override
  String get completeFormBelow => 'Please complete the form below.';

  @override
  String get submitRequest => 'Submit request';

  @override
  String get resubmit => 'Resubmit';

  @override
  String get requestToJoin => 'Request to Join';

  @override
  String get cancelRequest => 'Cancel request';

  @override
  String get requestAgain => 'Request again';

  @override
  String requiredFieldsProgress(int filled, int total) {
    return '$filled of $total required fields completed';
  }

  @override
  String get draftRestored => 'Your previous answers were restored';

  @override
  String get formAnswersEncrypted =>
      'Your answers are encrypted in transit and at rest.';

  @override
  String get formLoadFailedTitle => 'Couldn\'t load the form';

  @override
  String get noFormRequired => 'No form required';

  @override
  String get noFormRequiredHint =>
      'This group doesn\'t ask for any extra information. Send your request directly.';

  @override
  String get selectAnOption => 'Select an option';

  @override
  String get selectADate => 'Select a date';

  @override
  String get noFileSelected => 'No file selected';

  @override
  String get fieldTypeUnsupported =>
      'This field isn\'t supported in this version. Update the app to complete it.';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusMoreInfo => 'Needs info';

  @override
  String get statusExpired => 'Expired';

  @override
  String get joinRequestsTitle => 'Join Requests';

  @override
  String get tabPending => 'Pending';

  @override
  String get tabExpired => 'Expired';

  @override
  String get tabHistory => 'History';

  @override
  String get select => 'Select';

  @override
  String get cancel => 'Cancel';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get approveAll => 'Accept All';

  @override
  String get rejectAll => 'Reject All';

  @override
  String approveSelected(int count) {
    return 'Approve ($count)';
  }

  @override
  String rejectSelected(int count) {
    return 'Reject ($count)';
  }

  @override
  String get approveAllTitle => 'Accept all requests';

  @override
  String get rejectAllTitle => 'Reject all requests';

  @override
  String approveAllConfirm(int count) {
    return 'Are you sure you want to accept all $count pending requests?';
  }

  @override
  String rejectAllConfirm(int count) {
    return 'Are you sure you want to reject all $count pending requests? This cannot be undone.';
  }

  @override
  String bulkResult(int count) {
    return 'Successfully processed $count requests';
  }

  @override
  String get rejectRequestTitle => 'Reject request';

  @override
  String get rejectionReasonOptional => 'Reason for rejection (optional)';

  @override
  String get rejectionReasonLabel => 'Reason';

  @override
  String get noAnswersSubmitted => 'No answers submitted';

  @override
  String get requestsLoadFailedTitle => 'Couldn\'t load requests';

  @override
  String get noPendingRequests => 'No pending join requests';

  @override
  String get noPendingRequestsHint =>
      'Your group is secure. New requests will appear here.';

  @override
  String get nothingHere => 'Nothing here';

  @override
  String get nothingHereHint => 'No requests with this status yet.';

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get entrySettingsTitle => 'Entry Settings';

  @override
  String get joinModeSection => 'Join mode';

  @override
  String get modeOpen => 'Open';

  @override
  String get modeOpenHint => 'Anyone joins instantly, no approval needed.';

  @override
  String get modeInviteOnly => 'Invite only';

  @override
  String get modeInviteOnlyHint => 'Only people with an invite link can join.';

  @override
  String get modeRequestApproval => 'Request + approval';

  @override
  String get modeRequestApprovalHint =>
      'Applicants complete a verification form and await approval.';

  @override
  String get verificationFormSection => 'Verification form';

  @override
  String get noFormAttached => 'No form attached';

  @override
  String get noFormAttachedHint =>
      'The group is gated but asks nothing. Create a form.';

  @override
  String fieldCount(int count) {
    return '$count fields';
  }

  @override
  String get requestHandlingSection => 'Request handling';

  @override
  String get requestExpiryTitle => 'Request expiry';

  @override
  String get requestExpiryHint =>
      'Requests with no decision within this window expire automatically.';

  @override
  String get expiryNever => 'Never';

  @override
  String expiryDays(int count) {
    return '$count days';
  }

  @override
  String get allowRejoinTitle => 'Allow re-applying';

  @override
  String get allowRejoinHint =>
      'A rejected applicant may submit a new request.';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get formBuilderTitle => 'Form Builder';

  @override
  String get formBuilderEmptyTitle => 'No fields added yet';

  @override
  String get formBuilderEmptyHint =>
      'Add the fields an applicant must complete before joining.';

  @override
  String get addField => 'Add field';

  @override
  String get saveAndActivate => 'Save & activate';

  @override
  String get previewForm => 'Preview';

  @override
  String get editForm => 'Edit';

  @override
  String get previewNotice => 'This is exactly what the applicant will see.';

  @override
  String get formNameLabel => 'Form name';

  @override
  String get formNameHint => 'e.g. Unit verification';

  @override
  String get formNeedsName => 'Give the form a name';

  @override
  String get formNeedsFields => 'Add at least one field';

  @override
  String fieldNumber(int number) {
    return 'Field $number';
  }

  @override
  String get fieldNeedsLabel => 'This field needs a label';

  @override
  String get fieldNeedsOptions => 'Add at least one option';

  @override
  String get untitledField => 'Untitled field';

  @override
  String get chooseFieldType => 'Choose a field type';

  @override
  String get fieldLabelLabel => 'Question';

  @override
  String get fieldLabelHint => 'e.g. Full name in Arabic';

  @override
  String get fieldPlaceholderLabel => 'Placeholder (optional)';

  @override
  String get fieldHelperLabel => 'Helper text (optional)';

  @override
  String get fieldRequiredLabel => 'Required field';

  @override
  String get fieldOptionsLabel => 'Options';

  @override
  String get addOptionHint => 'Add an option';

  @override
  String get optionExists => 'That option already exists';

  @override
  String get done => 'Done';

  @override
  String get fieldTypeTextShort => 'Short text';

  @override
  String get fieldTypeTextLong => 'Long text';

  @override
  String get fieldTypeNumber => 'Number';

  @override
  String get fieldTypeSelectSingle => 'Single select';

  @override
  String get fieldTypeSelectMulti => 'Multi select';

  @override
  String get fieldTypeDate => 'Date';

  @override
  String get fieldTypePhone => 'Phone number';

  @override
  String get fieldTypeFile => 'File';

  @override
  String get fieldTypeImage => 'Image';

  @override
  String get fieldTypeCheckbox => 'Checkbox';

  @override
  String get fieldTypeUrl => 'URL';

  @override
  String get fieldTypeEmail => 'Email';

  @override
  String get auditLogTitle => 'Audit Log';

  @override
  String get auditLogEmpty => 'No activities recorded yet';

  @override
  String get auditLogEmptyHint =>
      'Every sensitive action on this group will appear here.';

  @override
  String get auditLogLoadFailedTitle => 'Couldn\'t load the audit log';

  @override
  String get loadMore => 'Load more';

  @override
  String get filterAll => 'All';

  @override
  String get filterApprovals => 'Approvals';

  @override
  String get filterRejections => 'Rejections';

  @override
  String get filterBans => 'Bans';

  @override
  String get filterSettings => 'Settings';

  @override
  String get auditApproved => 'Approved join request';

  @override
  String get auditRejected => 'Rejected join request';

  @override
  String get auditMoreInfo => 'Requested more information';

  @override
  String auditBulkApproved(int count) {
    return 'Bulk approved $count requests';
  }

  @override
  String auditBulkRejected(int count) {
    return 'Bulk rejected $count requests';
  }

  @override
  String get auditBanned => 'Banned a member';

  @override
  String get auditUnbanned => 'Lifted a ban';

  @override
  String get auditRemoved => 'Removed a member';

  @override
  String get auditJoinModeChanged => 'Changed the join mode';

  @override
  String get auditFormUpdated => 'Updated the verification form';

  @override
  String get auditModeratorAssigned => 'Assigned a moderator';

  @override
  String get auditReopened => 'Reopened a request';

  @override
  String get auditExported => 'Exported the audit log';

  @override
  String get uploading => 'Uploading…';

  @override
  String get fileAttached => 'File attached';

  @override
  String get choose => 'Choose';

  @override
  String get replace => 'Replace';

  @override
  String get amendRequest => 'Amend request';

  @override
  String get cancelRequestTitle => 'Cancel request';

  @override
  String get cancelRequestConfirm =>
      'Your request and answers will be deleted. You can apply again later.';

  @override
  String get keepRequest => 'Keep it';

  @override
  String get groupRequiresApproval =>
      'This group requires admin approval before joining.';

  @override
  String get statusPendingBody =>
      'Your request is being reviewed by the admin.';

  @override
  String get statusApprovedBody =>
      'You have been approved! You can now participate in the group.';

  @override
  String get statusRejectedBody => 'Your request was not approved.';

  @override
  String get statusMoreInfoBody =>
      'The admin needs more information. Please amend your request.';

  @override
  String get statusExpiredBody =>
      'Your request has expired. You can submit a new request.';

  @override
  String get contactsTitle => 'Contacts';

  @override
  String get findContactsTitle => 'Find your contacts';

  @override
  String get findContactsHeadline => 'Find people you know';

  @override
  String get findContactsBody =>
      'We match your address book against IronLink members without ever learning your numbers.';

  @override
  String get contactsPointHashedTitle => 'Hashed on your device';

  @override
  String get contactsPointHashedBody =>
      'Each number becomes a cryptographic fingerprint before it leaves your phone.';

  @override
  String get contactsPointNoNumbersTitle => 'Numbers are never sent';

  @override
  String get contactsPointNoNumbersBody =>
      'The server receives fingerprints only, and cannot recover a number from one.';

  @override
  String get contactsPointReversibleTitle => 'Reversible at any time';

  @override
  String get contactsPointReversibleBody =>
      'You can delete everything we matched in a single tap.';

  @override
  String get contactsDeniedHint =>
      'Without access we can\'t suggest people you know. You can enable it later in system settings.';

  @override
  String get allowContactAccess => 'Allow access';

  @override
  String get notNow => 'Not now';

  @override
  String get contactSyncOff => 'Sync is off';

  @override
  String get contactSyncOffHint =>
      'Turn it on to discover people you know on IronLink.';

  @override
  String get enableContactSync => 'Turn on sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String syncFoundNew(int count) {
    return 'Found $count new contacts';
  }

  @override
  String get syncNoNewContacts => 'No new contacts';

  @override
  String get noContactsFound => 'Nobody found yet';

  @override
  String get noContactsFoundHint =>
      'None of your contacts are on IronLink right now.';

  @override
  String get contactsLoadFailedTitle => 'Couldn\'t load contacts';

  @override
  String onIronLink(int count) {
    return 'On IronLink ($count)';
  }

  @override
  String get badgeNew => 'New';

  @override
  String get contactPrivacyTitle => 'Contact privacy';

  @override
  String get whoCanFindMe => 'Who can find me by phone number';

  @override
  String get discoverEveryone => 'Everyone';

  @override
  String get discoverEveryoneHint =>
      'Anyone with your number can discover you.';

  @override
  String get discoverMutual => 'People I know';

  @override
  String get discoverMutualHint =>
      'Only people who have your number and whose numbers you have.';

  @override
  String get discoverNobody => 'Nobody';

  @override
  String get discoverNobodyHint => 'Nobody can find you by phone number.';

  @override
  String storedHashesNotice(int count) {
    return 'We hold $count fingerprints, and no phone numbers.';
  }

  @override
  String get deleteContactData => 'Delete contact data';

  @override
  String get deleteContactDataTitle => 'Delete everything';

  @override
  String get deleteContactDataConfirm =>
      'All fingerprints and matches are permanently deleted, and you disappear from other people\'s discovery lists.';

  @override
  String get deleteEverything => 'Delete all';

  @override
  String get contactDataDeleted => 'Contact data deleted';

  @override
  String get blockUser => 'Block user';

  @override
  String get unblockUser => 'Unblock';

  @override
  String blockUserTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get blockUserBody =>
      'They will not be able to message you, and you will not be able to message them. They are not told that you blocked them.';

  @override
  String get blockedUsers => 'Blocked users';

  @override
  String get blockedUsersEmpty => 'You have not blocked anyone';

  @override
  String get blockedUsersEmptyHint =>
      'People you block will appear here, and you can undo it at any time.';

  @override
  String blockedOn(String date) {
    return 'Blocked $date';
  }

  @override
  String userBlocked(String name) {
    return '$name is blocked';
  }

  @override
  String userUnblocked(String name) {
    return '$name is unblocked';
  }

  @override
  String get blockedBannerTitle => 'You blocked this person';

  @override
  String get blockedBannerBody =>
      'Unblock them to send and receive messages again.';

  @override
  String get reportUser => 'Report user';

  @override
  String get reportTitle => 'Report';

  @override
  String get reportReasonQuestion => 'What is wrong?';

  @override
  String get reportDetails => 'Anything else we should know (optional)';

  @override
  String get reportSubmit => 'Send report';

  @override
  String get reportSubmitted => 'Report sent';

  @override
  String get reportSubmittedBody =>
      'A reviewer will look at it. You can also block this person so they cannot contact you meanwhile.';

  @override
  String get reportAlsoBlock => 'Block them as well';

  @override
  String get reportAlreadySent => 'You have already reported this message';

  @override
  String get reportEvidenceNotice =>
      'A copy of the reported message is attached, so it stays available even if it is deleted.';

  @override
  String get reasonSpam => 'Spam';

  @override
  String get reasonHarassment => 'Harassment or abuse';

  @override
  String get reasonImpersonation => 'Pretending to be someone else';

  @override
  String get reasonScam => 'Scam or fraud';

  @override
  String get reasonIllegalContent => 'Illegal content';

  @override
  String get reasonLeakedClassified => 'Classified material';

  @override
  String get reasonOther => 'Something else';

  @override
  String get analyzeContent => 'Analyse content';

  @override
  String get myReports => 'Reports I sent';

  @override
  String get reportStatusOpen => 'Under review';

  @override
  String get reportStatusReviewing => 'Being reviewed';

  @override
  String get reportStatusActioned => 'Action taken';

  @override
  String get reportStatusDismissed => 'No action taken';

  @override
  String get searchMessages => 'Search messages';

  @override
  String get searchMessagesTitle => 'Search messages';

  @override
  String get searchMessagesHint => 'Search in this conversation';

  @override
  String get searchMessagesOnDeviceNotice =>
      'Search runs on this device only. Messages are encrypted, so the server cannot read them — results cover what this device has downloaded.';

  @override
  String get searchNoResults => 'Nothing found';

  @override
  String get searchNoResultsHint =>
      'Try a shorter word, or a different spelling.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String get secureIdentityChanged =>
      'This person\'s security code changed. The message was not sent.';

  @override
  String get secureIdentityChangedBody =>
      'This happens when they reinstall the app — and it is also what an impersonation looks like. Confirm with them through another channel before continuing.';

  @override
  String get secureAcceptNewIdentity => 'I verified it — continue';

  @override
  String get securePeerHasNoKeys =>
      'This person cannot receive secret messages yet.';

  @override
  String get securePeerHasNoKeysBody =>
      'Their device has not published encryption keys. Ask them to open IronLink once.';

  @override
  String get secureEncryptFailed =>
      'The message was not sent, because it could not be encrypted.';

  @override
  String get secureDecryptFailed => 'A message could not be decrypted.';

  @override
  String get secureMessageUnreadable => 'Message could not be decrypted';

  @override
  String get secretChatOn => 'Secret chat is on';

  @override
  String get secretChatOff => 'Secret chat is off';

  @override
  String get secretChatNotice =>
      'Messages in this chat are end-to-end encrypted. The server stores only ciphertext it cannot read.';

  @override
  String get secretChatAttachmentWarning =>
      'Attachments are not yet encrypted end-to-end — only their captions are.';

  @override
  String get attachmentLoadFailed => 'Attachment could not be loaded';

  @override
  String get attachmentTampered =>
      'This attachment was altered and was not opened';

  @override
  String get attachmentEncrypted => 'Encrypted attachment';

  @override
  String get chatNotEncryptedNotice =>
      'Messages in this chat are not end-to-end encrypted. They are protected in transit, but the server can read them.';

  @override
  String get messageNotEncrypted => 'Not end-to-end encrypted';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get recordVoiceNote => 'Hold to record a voice note';

  @override
  String get voiceNoteTooShort => 'Hold to record';
}
