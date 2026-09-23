import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

/// Erases everything this app holds on the device.
///
/// Wired to Settings → "Delete all data". Both stores expect an in-app deletion
/// path even for an app with no account, and with no backend this is the only
/// one there is. The fatal-error screen uses [fatalDatabaseResetProvider]
/// instead, because this one writes through the database.
///
/// Order matters: cancel the OS alarms **first**, because a task row deleted
/// while its alarm is still scheduled leaves a notification that opens a task
/// that no longer exists.
typedef AppReset = Future<void> Function();

final Provider<AppReset> databaseResetProvider = Provider<AppReset>((Ref ref) {
  return () async {
    try {
      await ref.read(localNotifierProvider).cancelAll();
    } on Object catch (error, stack) {
      Log.e('cancelling notifications during reset failed', error, stack);
    }

    await ref.read(taskRepositoryProvider).deleteAll();
    // ⚠️ `keepDays: 0` still keeps TODAY's row: prune deletes days strictly
    // before the cutoff. Deliberate — it is a count, not the user's content,
    // and wiping it would make "Delete all data" a free extra capture a day.
    await ref
        .read(usageRepositoryProvider)
        .prune(ref.read(todayProvider), keepDays: 0);
    await ref.read(settingsRepositoryProvider).write(AppSettings.defaults);

    // ⚠️ A sweep already running read its tasks before the delete and keeps
    // scheduling them after `cancelAll`, re-arming alarms for deleted tasks.
    // This one queues behind it, finds no tasks and cancels what it re-armed.
    try {
      await ref.read(reminderSchedulerProvider).sync();
    } on Object catch (error, stack) {
      Log.e('reminder sync after reset failed', error, stack);
    }

    // Onboarding and the permissions primer are deliberately NOT reset.
    // Deleting your tasks is not a request to be walked through the tutorial
    // again, and re-prompting for the microphone here would be the second
    // prompt iOS never shows.
  };
});

/// The fatal-error screen's reset: the database would not open, so nothing
/// here goes through it.
///
/// ⚠️ Deleting rows could never work there. drift caches a failed open and
/// rethrows it on every later query on that instance, and a file that fails
/// its open is not fixed by DELETE anyway. So: close the broken instance,
/// delete the file, and let the next read build a fresh one, which `onCreate`
/// and the seed in `beforeOpen` fill with defaults.
///
/// The alarms are cancelled only once the file is gone, so a reset that
/// failed leaves the user's reminders where they were. The caller retries the
/// boot afterwards; its sweep reconciles the OS with the empty database.
final Provider<AppReset> fatalDatabaseResetProvider = Provider<AppReset>((
  Ref ref,
) {
  return () async {
    try {
      await ref.read(appDatabaseProvider).close();
    } on Object catch (error) {
      // Expected: closing a database whose open failed rethrows that failure.
      Log.w('closing the broken database failed: ${error.runtimeType}');
    }
    await ref.read(databaseFileDeleterProvider)();
    ref.invalidate(appDatabaseProvider);

    try {
      await ref.read(localNotifierProvider).cancelAll();
    } on Object catch (error, stack) {
      Log.e('cancelling notifications during reset failed', error, stack);
    }
  };
});
