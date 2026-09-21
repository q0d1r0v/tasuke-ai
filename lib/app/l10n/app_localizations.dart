import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasuke AI'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Voice to Tasks'**
  String get appSubtitle;

  /// No description provided for @appSlogan.
  ///
  /// In en, this message translates to:
  /// **'Speak. Plan. Done.'**
  String get appSlogan;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get actionOpenSettings;

  /// No description provided for @actionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get actionAllow;

  /// No description provided for @actionGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get actionGotIt;

  /// No description provided for @actionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get actionDismiss;

  /// No description provided for @actionViewOnline.
  ///
  /// In en, this message translates to:
  /// **'View online'**
  String get actionViewOnline;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Turn Your Voice into Action'**
  String get onboardingTitle1;

  /// No description provided for @onboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Just speak naturally. Tasuke AI understands, organizes and creates tasks for you.'**
  String get onboardingBody1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'One Sentence, Many Tasks'**
  String get onboardingTitle2;

  /// No description provided for @onboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Say everything on your mind at once. We find each task and work out when it is due.'**
  String get onboardingBody2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Private by Design'**
  String get onboardingTitle3;

  /// No description provided for @onboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition and AI both run on this device. Your voice and your tasks never leave it.'**
  String get onboardingBody3;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s Get Started'**
  String get permissionsTitle;

  /// No description provided for @permissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tasuke AI needs a few permissions to work at its best.'**
  String get permissionsSubtitle;

  /// No description provided for @permissionsMicrophoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permissionsMicrophoneTitle;

  /// No description provided for @permissionsMicrophoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'To record your voice'**
  String get permissionsMicrophoneSubtitle;

  /// No description provided for @permissionsNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permissionsNotificationsTitle;

  /// No description provided for @permissionsNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'To remind you about your tasks'**
  String get permissionsNotificationsSubtitle;

  /// No description provided for @permissionsPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'We respect your privacy. Everything works on your device.'**
  String get permissionsPrivacyNote;

  /// No description provided for @permissionsGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get permissionsGranted;

  /// No description provided for @permissionsDenied.
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get permissionsDenied;

  /// No description provided for @modelSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing your AI'**
  String get modelSetupTitle;

  /// No description provided for @modelSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tasuke AI is downloading its language model. This happens once, and only needs {size}.'**
  String modelSetupSubtitle(String size);

  /// No description provided for @modelSetupWifiHint.
  ///
  /// In en, this message translates to:
  /// **'Best over Wi-Fi. You can keep using the app while it downloads.'**
  String get modelSetupWifiHint;

  /// No description provided for @modelSetupProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% downloaded'**
  String modelSetupProgress(int percent);

  /// No description provided for @modelSetupDownload.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get modelSetupDownload;

  /// No description provided for @modelSetupLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get modelSetupLater;

  /// No description provided for @modelSetupReady.
  ///
  /// In en, this message translates to:
  /// **'Your AI is ready'**
  String get modelSetupReady;

  /// No description provided for @modelSetupFailed.
  ///
  /// In en, this message translates to:
  /// **'The download didn\'t finish'**
  String get modelSetupFailed;

  /// No description provided for @modelSetupChecksumFailed.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file was incomplete and has been removed.'**
  String get modelSetupChecksumFailed;

  /// No description provided for @modelSetupNoSpace.
  ///
  /// In en, this message translates to:
  /// **'There isn\'t enough free space for the model.'**
  String get modelSetupNoSpace;

  /// No description provided for @modelSetupPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing AI — {percent}%'**
  String modelSetupPreparing(int percent);

  /// No description provided for @homeGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning,'**
  String get homeGreetingMorning;

  /// No description provided for @homeGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon,'**
  String get homeGreetingAfternoon;

  /// No description provided for @homeGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening,'**
  String get homeGreetingEvening;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Let\'s make it happen today'**
  String get homeTagline;

  /// No description provided for @homeTabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get homeTabToday;

  /// No description provided for @homeTabUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get homeTabUpcoming;

  /// No description provided for @homeTabCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get homeTabCompleted;

  /// No description provided for @homeSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get homeSpeak;

  /// No description provided for @emptyTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing for today'**
  String get emptyTodayTitle;

  /// No description provided for @emptyTodayBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the microphone and say what\'s on your mind.'**
  String get emptyTodayBody;

  /// No description provided for @emptyUpcomingTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing coming up'**
  String get emptyUpcomingTitle;

  /// No description provided for @emptyUpcomingBody.
  ///
  /// In en, this message translates to:
  /// **'Tasks with a future date will appear here.'**
  String get emptyUpcomingBody;

  /// No description provided for @emptyCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing completed yet'**
  String get emptyCompletedTitle;

  /// No description provided for @emptyCompletedBody.
  ///
  /// In en, this message translates to:
  /// **'Finished tasks collect here so you can see what you got done.'**
  String get emptyCompletedBody;

  /// No description provided for @emptySearchPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Search your tasks'**
  String get emptySearchPromptTitle;

  /// No description provided for @emptySearchPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Type a word from a task title.'**
  String get emptySearchPromptBody;

  /// No description provided for @emptySearchNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No tasks match \"{query}\"'**
  String emptySearchNoResultsTitle(String query);

  /// No description provided for @emptySearchNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try a different word.'**
  String get emptySearchNoResultsBody;

  /// No description provided for @emptyStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'No stats yet'**
  String get emptyStatsTitle;

  /// No description provided for @emptyStatsBody.
  ///
  /// In en, this message translates to:
  /// **'Complete a task and your progress shows up here.'**
  String get emptyStatsBody;

  /// No description provided for @recordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get recordingTitle;

  /// No description provided for @recordingHint.
  ///
  /// In en, this message translates to:
  /// **'Speak naturally.\nYou can say multiple tasks at once.'**
  String get recordingHint;

  /// No description provided for @recordingTooShort.
  ///
  /// In en, this message translates to:
  /// **'Hold on — say a bit more.'**
  String get recordingTooShort;

  /// No description provided for @recordingMaxReached.
  ///
  /// In en, this message translates to:
  /// **'We stopped at one minute. Anything after that wasn\'t recorded.'**
  String get recordingMaxReached;

  /// No description provided for @processingTitle.
  ///
  /// In en, this message translates to:
  /// **'Turning your thoughts into tasks...'**
  String get processingTitle;

  /// No description provided for @processingStepTranscribe.
  ///
  /// In en, this message translates to:
  /// **'Transcribing your voice'**
  String get processingStepTranscribe;

  /// No description provided for @processingStepUnderstand.
  ///
  /// In en, this message translates to:
  /// **'Understanding with AI'**
  String get processingStepUnderstand;

  /// No description provided for @processingStepFind.
  ///
  /// In en, this message translates to:
  /// **'Finding tasks and dates'**
  String get processingStepFind;

  /// No description provided for @processingStepFinish.
  ///
  /// In en, this message translates to:
  /// **'Almost done...'**
  String get processingStepFinish;

  /// No description provided for @confirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Tasks'**
  String get confirmTitle;

  /// No description provided for @confirmFoundTasks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{We didn\'t find a task in that. Edit it below, or try again.} =1{We found 1 task. You can edit it before saving.} other{We found {count} tasks. You can edit them before saving.}}'**
  String confirmFoundTasks(int count);

  /// No description provided for @confirmAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Add another task'**
  String get confirmAddAnother;

  /// No description provided for @confirmSave.
  ///
  /// In en, this message translates to:
  /// **'Save Tasks'**
  String get confirmSave;

  /// No description provided for @confirmDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard these tasks?'**
  String get confirmDiscardTitle;

  /// No description provided for @confirmDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'They haven\'t been saved yet.'**
  String get confirmDiscardBody;

  /// No description provided for @confirmDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get confirmDiscardConfirm;

  /// No description provided for @confirmTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Give every task a title first.'**
  String get confirmTitleRequired;

  /// No description provided for @confirmLowConfidence.
  ///
  /// In en, this message translates to:
  /// **'Check this date'**
  String get confirmLowConfidence;

  /// No description provided for @confirmSaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task saved} other{{count} tasks saved}}'**
  String confirmSaved(int count);

  /// No description provided for @taskDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Task Details'**
  String get taskDetailTitle;

  /// No description provided for @taskFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get taskFieldTitle;

  /// No description provided for @taskFieldTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What needs doing?'**
  String get taskFieldTitleHint;

  /// No description provided for @taskFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get taskFieldNotes;

  /// No description provided for @taskFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get taskFieldDate;

  /// No description provided for @taskFieldTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get taskFieldTime;

  /// No description provided for @taskFieldReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get taskFieldReminder;

  /// No description provided for @taskNoDate.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get taskNoDate;

  /// No description provided for @taskNoTime.
  ///
  /// In en, this message translates to:
  /// **'No time'**
  String get taskNoTime;

  /// No description provided for @taskAllDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get taskAllDay;

  /// No description provided for @taskDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Task'**
  String get taskDelete;

  /// No description provided for @taskDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this task?'**
  String get taskDeleteConfirmTitle;

  /// No description provided for @taskDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get taskDeleteConfirmBody;

  /// No description provided for @taskDeleted.
  ///
  /// In en, this message translates to:
  /// **'Task deleted'**
  String get taskDeleted;

  /// No description provided for @taskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Task completed'**
  String get taskCompleted;

  /// No description provided for @taskOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get taskOverdue;

  /// No description provided for @taskMarkComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get taskMarkComplete;

  /// No description provided for @taskMarkIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Mark not done'**
  String get taskMarkIncomplete;

  /// No description provided for @dateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dateTomorrow;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// No description provided for @dateNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next Week'**
  String get dateNextWeek;

  /// No description provided for @dateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get dateLater;

  /// No description provided for @dateSomeday.
  ///
  /// In en, this message translates to:
  /// **'Someday'**
  String get dateSomeday;

  /// No description provided for @taskMetaRelative.
  ///
  /// In en, this message translates to:
  /// **'{day}, {time}'**
  String taskMetaRelative(String day, String time);

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search tasks'**
  String get searchHint;

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get statsTitle;

  /// No description provided for @statsPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statsPending;

  /// No description provided for @statsCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statsCompleted;

  /// No description provided for @statsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get statsThisWeek;

  /// No description provided for @statsStreak.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{No streak yet} =1{1 day streak} other{{days} day streak}}'**
  String statsStreak(int days);

  /// No description provided for @statsLastSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get statsLastSevenDays;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get settingsSubscription;

  /// No description provided for @settingsSubscriptionFree.
  ///
  /// In en, this message translates to:
  /// **'Free Plan'**
  String get settingsSubscriptionFree;

  /// No description provided for @settingsSubscriptionPro.
  ///
  /// In en, this message translates to:
  /// **'Tasuke Pro'**
  String get settingsSubscriptionPro;

  /// No description provided for @settingsUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get settingsUsage;

  /// No description provided for @settingsUsageValue.
  ///
  /// In en, this message translates to:
  /// **'{used} / {limit} today'**
  String settingsUsageValue(int used, int limit);

  /// No description provided for @settingsUsageUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get settingsUsageUnlimited;

  /// No description provided for @settingsAiModel.
  ///
  /// In en, this message translates to:
  /// **'AI model'**
  String get settingsAiModel;

  /// No description provided for @settingsAiModelReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get settingsAiModelReady;

  /// No description provided for @settingsAiModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get settingsAiModelMissing;

  /// No description provided for @settingsAiModelDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get settingsAiModelDownloading;

  /// No description provided for @settingsAllDayReminder.
  ///
  /// In en, this message translates to:
  /// **'All-day reminder time'**
  String get settingsAllDayReminder;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTerms;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get settingsHelp;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsRestorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get settingsRestorePurchases;

  /// No description provided for @settingsDeleteData.
  ///
  /// In en, this message translates to:
  /// **'Delete all data'**
  String get settingsDeleteData;

  /// No description provided for @settingsDeleteDataConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete everything?'**
  String get settingsDeleteDataConfirmTitle;

  /// No description provided for @settingsDeleteDataConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every task, setting and reminder on this device will be erased. This can\'t be undone.'**
  String get settingsDeleteDataConfirmBody;

  /// No description provided for @settingsDeleteDataDone.
  ///
  /// In en, this message translates to:
  /// **'All data deleted'**
  String get settingsDeleteDataDone;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutBuiltFor.
  ///
  /// In en, this message translates to:
  /// **'Built for a more productive you.'**
  String get aboutBuiltFor;

  /// No description provided for @aboutOnDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Everything runs on your device'**
  String get aboutOnDeviceTitle;

  /// No description provided for @aboutOnDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition and task extraction both happen on this phone. The only thing Tasuke AI ever downloads is its own language model.'**
  String get aboutOnDeviceBody;

  /// No description provided for @aboutLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get aboutLicenses;

  /// No description provided for @paywallTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasuke Pro'**
  String get paywallTitle;

  /// No description provided for @paywallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock your full potential'**
  String get paywallSubtitle;

  /// No description provided for @paywallBenefitUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited voice processing'**
  String get paywallBenefitUnlimited;

  /// No description provided for @paywallBenefitMultiple.
  ///
  /// In en, this message translates to:
  /// **'Multiple tasks from one voice input'**
  String get paywallBenefitMultiple;

  /// No description provided for @paywallBenefitAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced AI processing'**
  String get paywallBenefitAdvanced;

  /// No description provided for @paywallBenefitPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority updates'**
  String get paywallBenefitPriority;

  /// No description provided for @paywallBenefitSupport.
  ///
  /// In en, this message translates to:
  /// **'Support the development'**
  String get paywallBenefitSupport;

  /// No description provided for @paywallMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get paywallMonthly;

  /// No description provided for @paywallYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get paywallYearly;

  /// No description provided for @paywallPerMonth.
  ///
  /// In en, this message translates to:
  /// **'per month'**
  String get paywallPerMonth;

  /// No description provided for @paywallPerYear.
  ///
  /// In en, this message translates to:
  /// **'per year'**
  String get paywallPerYear;

  /// No description provided for @paywallPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get paywallPeriodMonth;

  /// No description provided for @paywallPeriodYear.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get paywallPeriodYear;

  /// No description provided for @paywallYearlyEquivalent.
  ///
  /// In en, this message translates to:
  /// **'{price} per month, billed yearly'**
  String paywallYearlyEquivalent(String price);

  /// No description provided for @paywallSave.
  ///
  /// In en, this message translates to:
  /// **'Save {percent}%'**
  String paywallSave(int percent);

  /// No description provided for @paywallSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get paywallSubscribe;

  /// No description provided for @paywallRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get paywallRestore;

  /// No description provided for @paywallManage.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get paywallManage;

  /// No description provided for @paywallAutoRenewNotice.
  ///
  /// In en, this message translates to:
  /// **'Subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your store account at confirmation of purchase.'**
  String get paywallAutoRenewNotice;

  /// No description provided for @paywallFreeTierNote.
  ///
  /// In en, this message translates to:
  /// **'Free: {limit} voice captures a day, unlimited manual tasks and reminders.'**
  String paywallFreeTierNote(int limit);

  /// No description provided for @paywallLegal.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use and Privacy Policy'**
  String get paywallLegal;

  /// No description provided for @paywallStoreUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'The store isn\'t available'**
  String get paywallStoreUnavailableTitle;

  /// No description provided for @paywallStoreUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and store account, then try again.'**
  String get paywallStoreUnavailableBody;

  /// No description provided for @paywallPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get paywallPending;

  /// No description provided for @paywallPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Your purchase needs approval before Pro unlocks.'**
  String get paywallPendingBody;

  /// No description provided for @paywallPurchased.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Tasuke Pro'**
  String get paywallPurchased;

  /// No description provided for @paywallRestoredNone.
  ///
  /// In en, this message translates to:
  /// **'No previous purchase found'**
  String get paywallRestoredNone;

  /// No description provided for @paywallRestored.
  ///
  /// In en, this message translates to:
  /// **'Your subscription is active again'**
  String get paywallRestored;

  /// No description provided for @paywallQuotaHeader.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used {used} of {limit} voice captures today.'**
  String paywallQuotaHeader(int used, int limit);

  /// No description provided for @errorGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGenericTitle;

  /// No description provided for @errorGenericBody.
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get errorGenericBody;

  /// No description provided for @errorMicDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasuke needs your microphone'**
  String get errorMicDeniedTitle;

  /// No description provided for @errorMicDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'It\'s used only while you\'re recording a task, and the audio never leaves this device.'**
  String get errorMicDeniedBody;

  /// No description provided for @errorMicPermanentBody.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is off for Tasuke AI. You can turn it back on in Settings.'**
  String get errorMicPermanentBody;

  /// No description provided for @errorMicBusyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your microphone is in use'**
  String get errorMicBusyTitle;

  /// No description provided for @errorMicBusyBody.
  ///
  /// In en, this message translates to:
  /// **'Another app or a call is using it. Try again in a moment.'**
  String get errorMicBusyBody;

  /// No description provided for @errorNoSpeechTitle.
  ///
  /// In en, this message translates to:
  /// **'We didn\'t catch that'**
  String get errorNoSpeechTitle;

  /// No description provided for @errorNoSpeechBody.
  ///
  /// In en, this message translates to:
  /// **'Try again a little closer to the microphone.'**
  String get errorNoSpeechBody;

  /// No description provided for @errorModelMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'The voice model isn\'t ready'**
  String get errorModelMissingTitle;

  /// No description provided for @errorModelMissingBody.
  ///
  /// In en, this message translates to:
  /// **'Tasuke AI couldn\'t load its speech model. You can still type a task.'**
  String get errorModelMissingBody;

  /// No description provided for @errorExtractorNotReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'The AI is still downloading'**
  String get errorExtractorNotReadyTitle;

  /// No description provided for @errorExtractorNotReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Voice capture unlocks once the model finishes. You can add tasks by hand in the meantime.'**
  String get errorExtractorNotReadyBody;

  /// No description provided for @errorTypeInstead.
  ///
  /// In en, this message translates to:
  /// **'Type a task instead'**
  String get errorTypeInstead;

  /// No description provided for @errorDatabaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasuke can\'t open its database'**
  String get errorDatabaseTitle;

  /// No description provided for @errorDatabaseBody.
  ///
  /// In en, this message translates to:
  /// **'This usually means the app\'s storage was damaged.'**
  String get errorDatabaseBody;

  /// No description provided for @errorResetData.
  ///
  /// In en, this message translates to:
  /// **'Reset app data'**
  String get errorResetData;

  /// No description provided for @errorDiskFull.
  ///
  /// In en, this message translates to:
  /// **'There isn\'t enough space to save. Free some up and try again.'**
  String get errorDiskFull;

  /// No description provided for @bannerNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Reminders are off. Turn on notifications to be reminded.'**
  String get bannerNotificationsOff;

  /// No description provided for @bannerExactAlarmOff.
  ///
  /// In en, this message translates to:
  /// **'Reminders may arrive a few minutes late on this device.'**
  String get bannerExactAlarmOff;

  /// No description provided for @bannerBatteryOptimisation.
  ///
  /// In en, this message translates to:
  /// **'This device may delay reminders to save battery.'**
  String get bannerBatteryOptimisation;

  /// No description provided for @notificationChannelName.
  ///
  /// In en, this message translates to:
  /// **'Task reminders'**
  String get notificationChannelName;

  /// No description provided for @notificationChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Reminders for the tasks you create.'**
  String get notificationChannelDescription;

  /// No description provided for @notificationReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Tap to open this task.'**
  String get notificationReminderBody;

  /// No description provided for @quotaExhaustedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used today\'s voice captures'**
  String get quotaExhaustedTitle;

  /// No description provided for @quotaExhaustedBody.
  ///
  /// In en, this message translates to:
  /// **'Free includes {limit} a day. Tasuke Pro is unlimited.'**
  String quotaExhaustedBody(int limit);

  /// No description provided for @quotaSeeProPlans.
  ///
  /// In en, this message translates to:
  /// **'See Pro plans'**
  String get quotaSeeProPlans;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpTitle;

  /// No description provided for @helpHowToTitle.
  ///
  /// In en, this message translates to:
  /// **'How to capture a task'**
  String get helpHowToTitle;

  /// No description provided for @helpHowToBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the microphone and speak naturally. You can say several things at once — for example, \"Tomorrow at 3 PM send the build to James and Friday check App Store\". Tasuke AI splits that into two tasks with the right dates and shows them for you to confirm.'**
  String get helpHowToBody;

  /// No description provided for @helpOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Does it work offline?'**
  String get helpOfflineTitle;

  /// No description provided for @helpOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Yes. Once the language model has downloaded, everything works with no connection at all.'**
  String get helpOfflineBody;

  /// No description provided for @helpRemindersTitle.
  ///
  /// In en, this message translates to:
  /// **'My reminders are late'**
  String get helpRemindersTitle;

  /// No description provided for @helpRemindersBody.
  ///
  /// In en, this message translates to:
  /// **'Some devices delay alarms to save battery. Allowing exact alarms, and excluding Tasuke AI from battery optimisation, fixes it.'**
  String get helpRemindersBody;

  /// No description provided for @helpContact.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get helpContact;

  /// No description provided for @legalPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get legalPrivacyTitle;

  /// No description provided for @legalTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get legalTermsTitle;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @usageTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usageTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
