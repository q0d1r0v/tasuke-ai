// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tasuke AI';

  @override
  String get appSubtitle => 'Voice to Tasks';

  @override
  String get appSlogan => 'Speak. Plan. Done.';

  @override
  String get actionNext => 'Next';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionSave => 'Save';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDone => 'Done';

  @override
  String get actionClose => 'Close';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionOpenSettings => 'Open Settings';

  @override
  String get actionAllow => 'Allow';

  @override
  String get actionGotIt => 'Got it';

  @override
  String get actionDismiss => 'Dismiss';

  @override
  String get actionViewOnline => 'View online';

  @override
  String get actionClear => 'Clear';

  @override
  String get onboardingTitle1 => 'Turn Your Voice into Action';

  @override
  String get onboardingBody1 =>
      'Just speak naturally. Tasuke AI understands, organizes and creates tasks for you.';

  @override
  String get onboardingTitle2 => 'One Sentence, Many Tasks';

  @override
  String get onboardingBody2 =>
      'Say everything on your mind at once. We find each task and work out when it is due.';

  @override
  String get onboardingTitle3 => 'Private by Design';

  @override
  String get onboardingBody3 =>
      'Speech recognition and AI both run on this device. Your voice and your tasks never leave it.';

  @override
  String get permissionsTitle => 'Let\'s Get Started';

  @override
  String get permissionsSubtitle =>
      'Tasuke AI needs a few permissions to work at its best.';

  @override
  String get permissionsMicrophoneTitle => 'Microphone';

  @override
  String get permissionsMicrophoneSubtitle => 'To record your voice';

  @override
  String get permissionsNotificationsTitle => 'Notifications';

  @override
  String get permissionsNotificationsSubtitle =>
      'To remind you about your tasks';

  @override
  String get permissionsPrivacyNote =>
      'We respect your privacy. Everything works on your device.';

  @override
  String get permissionsGranted => 'Allowed';

  @override
  String get permissionsDenied => 'Not allowed';

  @override
  String get modelSetupTitle => 'Preparing your AI';

  @override
  String modelSetupSubtitle(String size) {
    return 'Tasuke AI is downloading its language model. This happens once, and only needs $size.';
  }

  @override
  String get modelSetupWifiHint =>
      'Best over Wi-Fi. You can keep using the app while it downloads.';

  @override
  String modelSetupProgress(int percent) {
    return '$percent% downloaded';
  }

  @override
  String get modelSetupDownload => 'Download now';

  @override
  String get modelSetupLater => 'Not now';

  @override
  String get modelSetupReady => 'Your AI is ready';

  @override
  String get modelSetupFailed => 'The download didn\'t finish';

  @override
  String get modelSetupChecksumFailed =>
      'The downloaded file was incomplete and has been removed.';

  @override
  String get modelSetupNoSpace =>
      'There isn\'t enough free space for the model.';

  @override
  String modelSetupPreparing(int percent) {
    return 'Preparing AI — $percent%';
  }

  @override
  String get homeGreetingMorning => 'Good morning,';

  @override
  String get homeGreetingAfternoon => 'Good afternoon,';

  @override
  String get homeGreetingEvening => 'Good evening,';

  @override
  String get homeTagline => 'Let\'s make it happen today';

  @override
  String get homeTabToday => 'Today';

  @override
  String get homeTabUpcoming => 'Upcoming';

  @override
  String get homeTabCompleted => 'Completed';

  @override
  String get homeSpeak => 'Speak';

  @override
  String get emptyTodayTitle => 'Nothing for today';

  @override
  String get emptyTodayBody =>
      'Tap the microphone and say what\'s on your mind.';

  @override
  String get emptyUpcomingTitle => 'Nothing coming up';

  @override
  String get emptyUpcomingBody => 'Tasks with a future date will appear here.';

  @override
  String get emptyCompletedTitle => 'Nothing completed yet';

  @override
  String get emptyCompletedBody =>
      'Finished tasks collect here so you can see what you got done.';

  @override
  String get emptySearchPromptTitle => 'Search your tasks';

  @override
  String get emptySearchPromptBody => 'Type a word from a task title.';

  @override
  String emptySearchNoResultsTitle(String query) {
    return 'No tasks match \"$query\"';
  }

  @override
  String get emptySearchNoResultsBody => 'Try a different word.';

  @override
  String get emptyStatsTitle => 'No stats yet';

  @override
  String get emptyStatsBody =>
      'Complete a task and your progress shows up here.';

  @override
  String get recordingTitle => 'Recording...';

  @override
  String get recordingHint =>
      'Speak naturally.\nYou can say multiple tasks at once.';

  @override
  String get recordingTooShort => 'Hold on — say a bit more.';

  @override
  String get recordingMaxReached =>
      'We stopped at one minute. Anything after that wasn\'t recorded.';

  @override
  String get processingTitle => 'Turning your thoughts into tasks...';

  @override
  String get processingStepTranscribe => 'Transcribing your voice';

  @override
  String get processingStepUnderstand => 'Understanding with AI';

  @override
  String get processingStepFind => 'Finding tasks and dates';

  @override
  String get processingStepFinish => 'Almost done...';

  @override
  String get confirmTitle => 'Confirm Tasks';

  @override
  String confirmFoundTasks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'We found $count tasks. You can edit them before saving.',
      one: 'We found 1 task. You can edit it before saving.',
      zero: 'We didn\'t find a task in that. Edit it below, or try again.',
    );
    return '$_temp0';
  }

  @override
  String get confirmAddAnother => 'Add another task';

  @override
  String get confirmSave => 'Save Tasks';

  @override
  String get confirmDiscardTitle => 'Discard these tasks?';

  @override
  String get confirmDiscardBody => 'They haven\'t been saved yet.';

  @override
  String get confirmDiscardConfirm => 'Discard';

  @override
  String get confirmTitleRequired => 'Give every task a title first.';

  @override
  String get confirmLowConfidence => 'Check this date';

  @override
  String confirmSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks saved',
      one: '1 task saved',
    );
    return '$_temp0';
  }

  @override
  String get taskDetailTitle => 'Task Details';

  @override
  String get taskFieldTitle => 'Title';

  @override
  String get taskFieldTitleHint => 'What needs doing?';

  @override
  String get taskFieldNotes => 'Notes';

  @override
  String get taskFieldDate => 'Date';

  @override
  String get taskFieldTime => 'Time';

  @override
  String get taskFieldReminder => 'Reminder';

  @override
  String get taskNoDate => 'No date';

  @override
  String get taskNoTime => 'No time';

  @override
  String get taskAllDay => 'All day';

  @override
  String get taskDelete => 'Delete Task';

  @override
  String get taskDeleteConfirmTitle => 'Delete this task?';

  @override
  String get taskDeleteConfirmBody => 'This can\'t be undone.';

  @override
  String get taskDeleted => 'Task deleted';

  @override
  String get taskCompleted => 'Task completed';

  @override
  String get taskOverdue => 'Overdue';

  @override
  String get taskMarkComplete => 'Mark complete';

  @override
  String get taskMarkIncomplete => 'Mark not done';

  @override
  String get dateToday => 'Today';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get dateNextWeek => 'Next Week';

  @override
  String get dateLater => 'Later';

  @override
  String get dateSomeday => 'Someday';

  @override
  String taskMetaRelative(String day, String time) {
    return '$day, $time';
  }

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search tasks';

  @override
  String get statsTitle => 'Stats';

  @override
  String get statsPending => 'Pending';

  @override
  String get statsCompleted => 'Completed';

  @override
  String get statsThisWeek => 'This week';

  @override
  String statsStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days day streak',
      one: '1 day streak',
      zero: 'No streak yet',
    );
    return '$_temp0';
  }

  @override
  String get statsLastSevenDays => 'Last 7 days';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsSubscription => 'Subscription';

  @override
  String get settingsSubscriptionFree => 'Free Plan';

  @override
  String get settingsSubscriptionPro => 'Tasuke Pro';

  @override
  String get settingsUsage => 'Usage';

  @override
  String settingsUsageValue(int used, int limit) {
    return '$used / $limit today';
  }

  @override
  String get settingsUsageUnlimited => 'Unlimited';

  @override
  String get settingsAiModel => 'AI model';

  @override
  String get settingsAiModelReady => 'Ready';

  @override
  String get settingsAiModelMissing => 'Not downloaded';

  @override
  String get settingsAiModelDownloading => 'Downloading…';

  @override
  String get settingsAllDayReminder => 'All-day reminder time';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsTerms => 'Terms of Service';

  @override
  String get settingsHelp => 'Help & Support';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsRestorePurchases => 'Restore Purchases';

  @override
  String get settingsDeleteData => 'Delete all data';

  @override
  String get settingsDeleteDataConfirmTitle => 'Delete everything?';

  @override
  String get settingsDeleteDataConfirmBody =>
      'Every task, setting and reminder on this device will be erased. This can\'t be undone.';

  @override
  String get settingsDeleteDataDone => 'All data deleted';

  @override
  String aboutVersion(String version) {
    return 'v$version';
  }

  @override
  String get aboutBuiltFor => 'Built for a more productive you.';

  @override
  String get aboutOnDeviceTitle => 'Everything runs on your device';

  @override
  String get aboutOnDeviceBody =>
      'Speech recognition and task extraction both happen on this phone. The only thing Tasuke AI ever downloads is its own language model.';

  @override
  String get aboutLicenses => 'Open source licenses';

  @override
  String get paywallTitle => 'Tasuke Pro';

  @override
  String get paywallSubtitle => 'Unlock your full potential';

  @override
  String get paywallBenefitUnlimited => 'Unlimited voice processing';

  @override
  String get paywallBenefitMultiple => 'Multiple tasks from one voice input';

  @override
  String get paywallBenefitAdvanced => 'Advanced AI processing';

  @override
  String get paywallBenefitPriority => 'Priority updates';

  @override
  String get paywallBenefitSupport => 'Support the development';

  @override
  String get paywallMonthly => 'Monthly';

  @override
  String get paywallYearly => 'Yearly';

  @override
  String get paywallPerMonth => 'per month';

  @override
  String get paywallPerYear => 'per year';

  @override
  String get paywallPeriodMonth => '1 month';

  @override
  String get paywallPeriodYear => '1 year';

  @override
  String paywallYearlyEquivalent(String price) {
    return '$price per month, billed yearly';
  }

  @override
  String paywallSave(int percent) {
    return 'Save $percent%';
  }

  @override
  String get paywallSubscribe => 'Subscribe';

  @override
  String get paywallRestore => 'Restore Purchases';

  @override
  String get paywallManage => 'Manage subscription';

  @override
  String get paywallAutoRenewNotice =>
      'Subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your store account at confirmation of purchase.';

  @override
  String paywallFreeTierNote(int limit) {
    return 'Free: $limit voice captures a day, unlimited manual tasks and reminders.';
  }

  @override
  String get paywallLegal => 'Terms of Use and Privacy Policy';

  @override
  String get paywallStoreUnavailableTitle => 'The store isn\'t available';

  @override
  String get paywallStoreUnavailableBody =>
      'Check your connection and store account, then try again.';

  @override
  String get paywallPending => 'Waiting for approval';

  @override
  String get paywallPendingBody =>
      'Your purchase needs approval before Pro unlocks.';

  @override
  String get paywallPurchased => 'Welcome to Tasuke Pro';

  @override
  String get paywallRestoredNone => 'No previous purchase found';

  @override
  String get paywallRestored => 'Your subscription is active again';

  @override
  String paywallQuotaHeader(int used, int limit) {
    return 'You\'ve used $used of $limit voice captures today.';
  }

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String get errorGenericBody => 'Please try again.';

  @override
  String get errorMicDeniedTitle => 'Tasuke needs your microphone';

  @override
  String get errorMicDeniedBody =>
      'It\'s used only while you\'re recording a task, and the audio never leaves this device.';

  @override
  String get errorMicPermanentBody =>
      'Microphone access is off for Tasuke AI. You can turn it back on in Settings.';

  @override
  String get errorMicBusyTitle => 'Your microphone is in use';

  @override
  String get errorMicBusyBody =>
      'Another app or a call is using it. Try again in a moment.';

  @override
  String get errorNoSpeechTitle => 'We didn\'t catch that';

  @override
  String get errorNoSpeechBody =>
      'Try again a little closer to the microphone.';

  @override
  String get errorModelMissingTitle => 'The voice model isn\'t ready';

  @override
  String get errorModelMissingBody =>
      'Tasuke AI couldn\'t load its speech model. You can still type a task.';

  @override
  String get errorExtractorNotReadyTitle => 'The AI is still downloading';

  @override
  String get errorExtractorNotReadyBody =>
      'Voice capture unlocks once the model finishes. You can add tasks by hand in the meantime.';

  @override
  String get errorTypeInstead => 'Type a task instead';

  @override
  String get errorDatabaseTitle => 'Tasuke can\'t open its database';

  @override
  String get errorDatabaseBody =>
      'This usually means the app\'s storage was damaged.';

  @override
  String get errorResetData => 'Reset app data';

  @override
  String get errorDiskFull =>
      'There isn\'t enough space to save. Free some up and try again.';

  @override
  String get bannerNotificationsOff =>
      'Reminders are off. Turn on notifications to be reminded.';

  @override
  String get bannerExactAlarmOff =>
      'Reminders may arrive a few minutes late on this device.';

  @override
  String get bannerBatteryOptimisation =>
      'This device may delay reminders to save battery.';

  @override
  String get notificationChannelName => 'Task reminders';

  @override
  String get notificationChannelDescription =>
      'Reminders for the tasks you create.';

  @override
  String get notificationReminderBody => 'Tap to open this task.';

  @override
  String get quotaExhaustedTitle => 'You\'ve used today\'s voice captures';

  @override
  String quotaExhaustedBody(int limit) {
    return 'Free includes $limit a day. Tasuke Pro is unlimited.';
  }

  @override
  String get quotaSeeProPlans => 'See Pro plans';

  @override
  String get helpTitle => 'Help & Support';

  @override
  String get helpHowToTitle => 'How to capture a task';

  @override
  String get helpHowToBody =>
      'Tap the microphone and speak naturally. You can say several things at once — for example, \"Tomorrow at 3 PM send the build to James and Friday check App Store\". Tasuke AI splits that into two tasks with the right dates and shows them for you to confirm.';

  @override
  String get helpOfflineTitle => 'Does it work offline?';

  @override
  String get helpOfflineBody =>
      'Yes. Once the language model has downloaded, everything works with no connection at all.';

  @override
  String get helpRemindersTitle => 'My reminders are late';

  @override
  String get helpRemindersBody =>
      'Some devices delay alarms to save battery. Allowing exact alarms, and excluding Tasuke AI from battery optimisation, fixes it.';

  @override
  String get helpContact => 'Contact support';

  @override
  String get legalPrivacyTitle => 'Privacy Policy';

  @override
  String get legalTermsTitle => 'Terms of Service';

  @override
  String get languageTitle => 'Language';

  @override
  String get usageTitle => 'Usage';
}
