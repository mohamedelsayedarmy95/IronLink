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

  @override
  String get groupNoMessages => 'No messages yet';

  @override
  String get groupMessageUnreadable => 'Message could not be decrypted';

  @override
  String get groupNoLongerMember => 'You are no longer a member of this group';

  @override
  String get groupAnnouncementOnly => 'Only admins can post in this group';

  @override
  String get groupEncryptionNotice =>
      'Messages in this group are end-to-end encrypted. The server routes them and cannot read them.';

  @override
  String get groupRotationNotice =>
      'When someone joins or leaves, everyone\'s keys change — so a person who leaves cannot read what is said afterwards.';

  @override
  String groupMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
      zero: 'No members',
    );
    return '$_temp0';
  }

  @override
  String get groupChat => 'Group chat';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get leaveGroupConfirm =>
      'You will stop receiving messages from this group, and will not be able to read what is said after you leave.';

  @override
  String get groupLeft => 'You left the group';

  @override
  String get ownerMustTransfer => 'Hand over ownership before leaving';

  @override
  String get verificationTimedOut =>
      'The verification service did not respond. Your connection is fine — this usually means the app is not set up for phone sign-in yet.';

  @override
  String get aiConsentTitle => 'AI features in this conversation';

  @override
  String get aiConsentWhatHappens =>
      'To summarise, translate or suggest replies, this app decrypts the messages and sends them to an AI provider outside IronLink. They leave your device and are read by a third party.';

  @override
  String get aiConsentEncryptionNote =>
      'Every other message in this app is end-to-end encrypted and unreadable by our server. These features are the one exception, which is why they are off unless you ask for them.';

  @override
  String get aiConsentToggle => 'Allow AI features here';

  @override
  String aiConsentToggleHint(String name) {
    return 'Applies only to your conversation with $name.';
  }

  @override
  String aiConsentWaitingOn(String names) {
    return 'Waiting for $names to agree. Until then nothing is sent.';
  }

  @override
  String get aiConsentWaitingGeneric =>
      'Waiting for the other participants to agree. Until then nothing is sent.';

  @override
  String get aiConsentEveryoneAgreed =>
      'Everyone has agreed. AI features are available here.';

  @override
  String get aiConsentWithdrawNote =>
      'You can withdraw at any time. That stops anything further being sent, but cannot recall what was already sent.';

  @override
  String get aiConsentRequired =>
      'Everyone in this conversation has to agree before AI features can be used.';

  @override
  String get aiFeatures => 'AI features';

  @override
  String get aiSummarise => 'Summarise conversation';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirm =>
      'This device will be signed out and everything stored on it erased — your message history, your encryption keys and any drafts. Because messages are end-to-end encrypted, the server cannot restore that history afterwards.';

  @override
  String get smartAlertTitle => 'Smart Alert';

  @override
  String get smartAlertOpenDocument => 'Open document';

  @override
  String get smartAlertAcknowledge => 'Acknowledge';

  @override
  String smartAlertMoreCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Smart Alerts',
      one: '1 Smart Alert',
    );
    return '$_temp0';
  }

  @override
  String smartAlertSemantics(String matched, String context) {
    return 'Smart Alert: \"$matched\" found in a document. Context: $context';
  }

  @override
  String get alertCenterTitle => 'Smart Alerts';

  @override
  String get alertCenterEmpty => 'No alerts';

  @override
  String get alertCenterEmptyHint =>
      'When an image or document arrives containing one of your keywords, the alert appears here.';

  @override
  String get alertFilterAll => 'All';

  @override
  String get alertFilterUnacknowledged => 'Unacknowledged';

  @override
  String get alertFilterAcknowledged => 'Acknowledged';

  @override
  String get alertFilterHighConfidence => 'High confidence';

  @override
  String get alertSectionToday => 'Today';

  @override
  String get alertSectionYesterday => 'Yesterday';

  @override
  String get alertSectionEarlier => 'Earlier';

  @override
  String get alertStatusAcknowledged => 'Acknowledged';

  @override
  String get alertStatusPresented => 'Not acknowledged';

  @override
  String get alertStatusOpened => 'Opened, not acknowledged';

  @override
  String get alertStatusExpired => 'Expired';

  @override
  String get alertStatusDismissed => 'Dismissed';

  @override
  String get alertRetentionNote =>
      'Alerts are kept for 48 hours and then deleted automatically.';

  @override
  String alertPageNumber(int page) {
    return 'Page $page';
  }

  @override
  String get alertProcessedLocally => 'Processed on this device';

  @override
  String get alertProcessedInCloud => 'Processed in the cloud';

  @override
  String get alertSuppressedByCap => 'Over this keyword daily limit';

  @override
  String get keywordManagementTitle => 'Keywords';

  @override
  String get keywordManagementSubtitle =>
      'Private to this conversation. The sender, group admins and everyone else cannot see them.';

  @override
  String get keywordAddTitle => 'Add keyword';

  @override
  String get keywordEditTitle => 'Edit keyword';

  @override
  String get keywordFieldLabel => 'Keyword';

  @override
  String get keywordFieldHint => 'Type a word or phrase';

  @override
  String get keywordPriorityLabel => 'Priority';

  @override
  String get keywordPriorityLow => 'Low';

  @override
  String get keywordPriorityMedium => 'Medium';

  @override
  String get keywordPriorityHigh => 'High';

  @override
  String get keywordPriorityCritical => 'Critical';

  @override
  String get keywordMatchModeLabel => 'Matching';

  @override
  String get keywordMatchExact => 'Whole word';

  @override
  String get keywordMatchPhrase => 'Phrase';

  @override
  String get keywordMatchFuzzy => 'Tolerate scan errors';

  @override
  String get keywordMatchRegex => 'Advanced pattern';

  @override
  String get keywordCategoryLabel => 'Category (optional)';

  @override
  String get keywordNotesLabel => 'Private note (optional)';

  @override
  String get keywordCaseSensitiveLabel => 'Match capitalisation';

  @override
  String get keywordDailyCapLabel => 'Daily alert limit (optional)';

  @override
  String get keywordEnabledLabel => 'Enabled';

  @override
  String get keywordDeleteConfirm =>
      'This keyword and every alert it raised will be deleted. This cannot be undone.';

  @override
  String get keywordEmpty => 'No keywords for this conversation yet';

  @override
  String get keywordTestTitle => 'Test this keyword';

  @override
  String get keywordTestHint =>
      'Paste some text to see whether the keyword would match it';

  @override
  String get keywordTestMatched => 'Matches';

  @override
  String get keywordTestNoMatch => 'No match';

  @override
  String get keywordErrorTooShort => 'Too short - at least two characters.';

  @override
  String get keywordErrorTooLong => 'That keyword is too long.';

  @override
  String get keywordErrorNotMatchable =>
      'Nothing in that keyword can be matched inside a document.';

  @override
  String get keywordErrorStopWord =>
      'That is a common connecting word, and would appear in almost every document.';

  @override
  String get keywordErrorRegexInvalid => 'That pattern is not valid.';

  @override
  String get keywordErrorRegexUnsafe =>
      'That pattern can take unbounded time to evaluate.';

  @override
  String get keywordErrorDuplicate =>
      'That keyword is already in this conversation.';

  @override
  String get documentCheckingNow => 'Checking document…';

  @override
  String get documentCheckedNothingFound => 'Checked, nothing found';

  @override
  String get documentUnreadable => 'This document could not be read reliably.';

  @override
  String get documentTooLowResolution =>
      'This image is too low-resolution to analyze reliably.';

  @override
  String get documentUnsupported => 'This kind of file cannot be checked.';

  @override
  String get documentTooLarge => 'This file is larger than the checking limit.';

  @override
  String documentTruncated(int pages) {
    return 'Long document - only the first $pages pages were checked.';
  }

  @override
  String get securityCenterLocalExplained =>
      'No document leaves this device to be checked, and your keywords are stored only here.';

  @override
  String get securityCenterNoLocalEngine =>
      'There is no reading engine on this device, so images cannot be checked. Nothing will be sent to the cloud automatically.';

  @override
  String get senderReportTitle => 'Recipient status';

  @override
  String get senderReportAlertRaised => 'A Smart Alert was raised';

  @override
  String get senderReportNoAlert => 'No alert';

  @override
  String get senderReportKeywordHidden =>
      'The keyword is private to the recipient and is not shown to you';

  @override
  String get senderReportUnavailable =>
      'The recipient has not shared this status';

  @override
  String get securityCenterTitle => 'Security Center';

  @override
  String get securityCenterSubtitle =>
      'Everything here is based on something the system actually knows. Nothing is estimated.';

  @override
  String get securityLevelHigh => 'Looks good';

  @override
  String get securityLevelMedium => 'Worth reviewing';

  @override
  String get securityLevelLow => 'Needs your attention';

  @override
  String get securityActiveSessions => 'Signed-in devices';

  @override
  String get securityThisDevice => 'This device';

  @override
  String get securityUnknownDevice => 'Unrecognised device';

  @override
  String securityLastActive(String when) {
    return 'Last active $when';
  }

  @override
  String get securityNeverActive => 'Not used yet';

  @override
  String get securitySignOutDevice => 'Sign out this device';

  @override
  String get securitySignOutDeviceConfirm =>
      'This device will be signed out immediately and disconnected. No other device is affected.';

  @override
  String get securitySecureAccount => 'Secure my account';

  @override
  String get securitySecureAccountConfirm =>
      'Every other device will be signed out. This one stays signed in.';

  @override
  String get securitySecureAccountDone => 'All other devices were signed out.';

  @override
  String securitySecureAccountPartial(int count) {
    return '$count devices could not be signed out. The list below shows what is actually signed in now.';
  }

  @override
  String get securityNoOtherDevices => 'No other devices are signed in';

  @override
  String get securityFindingOtherDevices =>
      'You are signed in on more than one device';

  @override
  String get securityFindingOtherDevicesWhy =>
      'Not a problem in itself. It is stated because it is the first thing you would need to know if someone reached your account.';

  @override
  String get securityFindingStaleSession =>
      'A device has not been used in over two weeks';

  @override
  String get securityFindingStaleSessionWhy =>
      'It may be a device you use occasionally. Have a look, and sign it out if you do not recognise it.';

  @override
  String get securityFindingEncryptionOn =>
      'End-to-end encryption is on by default';

  @override
  String get securityFindingEncryptionOnWhy =>
      'The server holds no key and cannot read your messages or attachments.';

  @override
  String get securityFindingEncryptionOff =>
      'Encryption is not the default on this device';

  @override
  String get securityFindingEncryptionOffWhy =>
      'This is the most serious thing this screen can say. Restart the app; if it persists, it needs investigating.';

  @override
  String get securityFindingKeywordsLocal =>
      'Your keywords are stored only on this device';

  @override
  String get securityFindingKeywordsLocalWhy =>
      'The server never received them, so it cannot leak them.';

  @override
  String get securityFindingCloudOcr => 'Cloud document checking is enabled';

  @override
  String get securityFindingCloudOcrWhy =>
      'You chose this. It means a document may be read outside your device when local reading fails.';

  @override
  String get securityWhyLabel => 'Why am I seeing this?';

  @override
  String get securityCheckedNothingWrong => 'Checked, nothing to report';

  @override
  String get securityLoadFailed => 'Could not load security status';

  @override
  String get safetyWarningTitle => 'Safety notice';

  @override
  String get safetyDismiss => 'Hide';

  @override
  String get safetyCredentialRequest =>
      'This message asks for a verification code';

  @override
  String get safetyCredentialRequestWhy =>
      'IronLink sends verification codes to you alone. Anyone asking you for one — even claiming to be support — is trying to get into your account. Do not send it to anybody.';

  @override
  String get safetySuspiciousLink => 'A link here looks deceptive';

  @override
  String get safetySuspiciousLinkWhy =>
      'This address is written to look like a different site. It was checked on your device, and nobody else saw it.';

  @override
  String get safetyPaymentRequest => 'A payment request, alongside other signs';

  @override
  String get safetyPaymentRequestWhy =>
      'A request for money on its own is ordinary. This is flagged because it arrived with another signal — urgency, a claimed identity, or a deceptive link.';

  @override
  String get safetyAuthorityClaim => 'The sender claims an official identity';

  @override
  String get safetyAuthorityClaimWhy =>
      'Someone is claiming to be support, a bank, or an administrator. Those parties do not ask for codes or passwords in messages.';

  @override
  String get safetyOffPlatform =>
      'A request to move the conversation elsewhere';

  @override
  String get safetyOffPlatformWhy =>
      'Moving a conversation somewhere unencrypted is a common step before fraud. There may be an ordinary reason, but it is worth confirming.';

  @override
  String get safetyUrgency => 'Time pressure, alongside other signs';

  @override
  String get safetyUrgencyWhy =>
      'Urgency stops people thinking. On its own it is ordinary — here it appeared with another signal.';

  @override
  String get attachUnsupportedFormat =>
      'This file is not a type we can strip hidden data from, so it was not sent. Photos and voice notes work normally.';

  @override
  String get connectionOffline =>
      'No connection. Your messages will send when you are back.';

  @override
  String get connectionConnecting => 'Reconnecting…';

  @override
  String get connectionOutdated =>
      'This version is too old. Update the app to continue.';
}
