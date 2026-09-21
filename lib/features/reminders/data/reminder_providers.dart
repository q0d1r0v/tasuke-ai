import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';

/// The notification body.
///
/// Held here rather than inside the scheduler because the scheduler is pure
/// enough to unit-test and an ARB lookup needs a BuildContext. It is overridden
/// from the app root once localizations exist; the fallback is deliberately
/// generic rather than a translated string this layer cannot reach.
final Provider<String Function(String title)> reminderBodyProvider =
    Provider<String Function(String title)>(
      (Ref ref) =>
          (String title) => 'Tap to open this task.',
    );

final Provider<ReminderScheduler> reminderSchedulerProvider =
    Provider<ReminderScheduler>((Ref ref) {
      return LocalReminderScheduler(
        notifier: ref.watch(localNotifierProvider),
        tasks: ref.watch(taskRepositoryProvider),
        clock: ref.watch(clockProvider),
        readSettings: () => ref.read(settingsRepositoryProvider).read(),
        bodyBuilder: ref.watch(reminderBodyProvider),
      );
    });

/// Re-syncs the rolling notification window whenever anything that affects it
/// changes: the app coming back to the foreground, the day rolling over, or the
/// device's timezone moving.
///
/// ⚠️ Without the timezone leg, a user who flies from Tashkent to London keeps
/// alarms resolved against the old zone until they happen to edit a task.
final Provider<AppSettings> reminderSettingsProbeProvider =
    Provider<AppSettings>((Ref ref) {
      return ref.watch(appSettingsProvider).value ?? AppSettings.defaults;
    });
