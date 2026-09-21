import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';

/// What the splash screen waits for.
///
/// Opening the database, initialising the timezone database and the
/// notification plugin are all asynchronous, and every screen below the splash
/// needs at least one of them. Holding here is a real wait, not a timed
/// animation: on a cold start with a large task list the database open is the
/// slow part, and showing Home before it lands means showing an empty list to
/// someone who has fifty tasks.
final FutureProvider<BootstrapResult>
appBootstrapProvider = FutureProvider<BootstrapResult>((Ref ref) async {
  // Open the database here so a corrupt file surfaces on a screen that can
  // offer a reset, rather than inside a random list builder three taps later.
  await ref.read(databaseHealthProvider.future);

  await ref.read(localNotifierProvider).initialise();

  // Reconcile the OS's pending alarms with the database. This is what restores
  // reminders after a reboot, after an app update, and after the user changed
  // timezone while the process was dead.
  try {
    await ref.read(reminderSchedulerProvider).sync();
  } on Object catch (error, stack) {
    // A failed sync must not block the launch — the tasks are still there.
    Log.e('reminder sync on boot failed', error, stack);
  }

  // Consume the payload of the notification that launched the app, if any.
  // ⚠️ Consumed, not merely read: an unread launch payload replayed on the next
  // cold start opens a task the user already dealt with.
  final String? payload = await ref
      .read(localNotifierProvider)
      .consumeLaunchPayload();

  return BootstrapResult(launchTaskId: decodeReminderPayload(payload));
});

/// Opens the database and proves it answers a query.
///
/// Separate from [appBootstrapProvider] so a widget test can override just this
/// one leg. ⚠️ `testWidgets` runs inside `FakeAsync`, where no real timer fires;
/// drift closes its query streams through a zero-duration timer and its
/// `close()` waits on the real event loop, so a widget test that constructs a
/// database either reports "a Timer is still pending" or deadlocks the isolate
/// outright. The database's own tests run on the Dart VM, where none of that
/// applies.
final FutureProvider<void> databaseHealthProvider = FutureProvider<void>((
  Ref ref,
) async {
  final AppDatabase database = ref.watch(appDatabaseProvider);
  // A query, not merely a construction: drift opens lazily, so constructing the
  // object proves nothing about the file behind it.
  await database.customSelect('SELECT 1').get();
  Log.d('database ready');
});

final class BootstrapResult {
  const BootstrapResult({this.launchTaskId});

  /// Set when the app was started by tapping a reminder.
  final String? launchTaskId;
}
