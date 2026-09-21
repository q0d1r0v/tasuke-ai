import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

/// Erases everything this app holds on the device.
///
/// Wired to Settings → "Delete all data" and to the fatal-error screen's reset.
/// Both stores expect an in-app deletion path even for an app with no account,
/// and with no backend this is the only one there is.
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
    await ref
        .read(usageRepositoryProvider)
        .prune(ref.read(todayProvider), keepDays: 0);
    await ref.read(settingsRepositoryProvider).write(AppSettings.defaults);
    // Onboarding and the permissions primer are deliberately NOT reset.
    // Deleting your tasks is not a request to be walked through the tutorial
    // again, and re-prompting for the microphone here would be the second
    // prompt iOS never shows.
  };
});
