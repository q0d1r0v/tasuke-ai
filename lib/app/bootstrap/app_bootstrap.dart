import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/models/retired_model_sweep.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';

/// What the splash screen waits for.
///
/// Three things, and only three: the database open, the timezone database and
/// the notification plugin handshake, and the store subscription. Every screen
/// below the splash needs one of them, and showing Home before the database
/// lands means showing an empty list to someone who has fifty tasks.
///
/// ⚠️ It deliberately does NOT wait for the reminder sweep or for the speech
/// model to be copied out of the bundle. Both are launched here and detached:
/// nothing below the splash reads either result, and on a fresh install or a
/// restored backup the sweep is up to 60 alarms × 3 platform round trips,
/// serialised, behind a splash that has no spinner — indistinguishable from a
/// hang.
final FutureProvider<BootstrapResult>
appBootstrapProvider = FutureProvider<BootstrapResult>((Ref ref) async {
  // These three share no dependency: the database leg is drift plus
  // path_provider, the notifier leg is the tz database plus the plugin
  // handshake, the store leg is SharedPreferences plus a billing channel. Run
  // them together rather than one after another.
  //
  // `Future.wait` attaches an error handler to each, so none can escape as an
  // uncaught async error, and a database failure still lands on the splash's
  // fatal-error screen.
  await Future.wait<void>(<Future<void>>[
    // Opened here so a corrupt file surfaces on a screen that can offer a
    // reset, rather than inside a random list builder three taps later.
    ref.read(databaseHealthProvider.future),
    ref.read(localNotifierProvider).initialise(),
    _subscribeToStore(ref.read(purchaseGatewayProvider)),
  ]);

  // Copy the bundled speech model out of the asset bundle, off the critical
  // path — into files/models on Android and Library/Caches on iOS, both kept
  // out of cloud backup. iOS may purge its copy under disk pressure, which is
  // why this runs on every launch rather than once. It takes about a second
  // and nothing on the splash needs it; a user who beats it to the mic button
  // is covered because `VoiceCapturePipeline.startRecording` calls `prepare()`
  // again and the install is idempotent and single-flighted.
  unawaited(ref.read(speechRecognizerProvider).prepare());

  // Delete the 219 MB language model an older build may have downloaded —
  // detached, and it never throws. The resolver is read before detaching for
  // the same reason as the scheduler below.
  unawaited(removeRetiredExtractorModel(ref.read(supportDirPathProvider)));

  // Reconcile the OS's pending alarms with the database — detached. This is
  // what restores reminders after a reboot, after an app update, and after the
  // user changed timezone while the process was dead, and none of it is worth
  // a second of splash.
  //
  // ⚠️ The scheduler is read SYNCHRONOUSLY, before detaching. The splash's
  // retry button and the reset flow both `ref.invalidate(appBootstrapProvider)`,
  // and a detached closure that calls `ref.read` on a disposed Ref throws.
  unawaited(_syncRemindersDetached(ref.read(reminderSchedulerProvider)));

  // Consume the payload of the notification that launched the app, if any.
  // ⚠️ Consumed, not merely read: an unread launch payload replayed on the next
  // cold start opens a task the user already dealt with.
  final String? payload = await ref
      .read(localNotifierProvider)
      .consumeLaunchPayload();

  return BootstrapResult(launchTaskId: decodeReminderPayload(payload));
});

/// Subscribes to the store before the first route resolves.
///
/// ⚠️ StoreKit replays every purchase that was never completed to whoever is
/// listening at launch, and an update delivered with nothing subscribed is
/// gone. Play replays nothing, which is why `initialise()` also starts a
/// silent restore once the listener is attached. That is how a paying subscriber lands on the free tier, in front of
/// the very quota gate that sent them to the paywall — and how Google Play
/// comes to refund the purchase three days later, because nothing ever
/// acknowledged it.
///
/// Bounded and non-fatal: a billing channel that never answers must not hold
/// the splash, and `isProProvider` falls back to the persisted entitlement. The
/// gateway keeps the in-flight future, so a late reply still attaches the
/// listener and no retry is spawned.
Future<void> _subscribeToStore(PurchaseGateway gateway) async {
  try {
    await gateway.initialise().timeout(const Duration(seconds: 5));
  } on Object catch (error, stack) {
    Log.e('purchase gateway init on boot failed', error, stack);
  }
}

/// Runs the boot sweep without holding the splash.
///
/// ⚠️ The try/catch lives HERE, not in the scheduler. `LocalReminderScheduler`
/// guards only the per-alarm `schedule()` call; reading settings, the
/// permission check and the pending-id query are unguarded and `sync()`
/// re-exposes their errors through the future it returns. A bare
/// `unawaited(sync())` would turn today's logged failure into an uncaught async
/// error during launch.
Future<void> _syncRemindersDetached(ReminderScheduler scheduler) async {
  try {
    await scheduler.sync();
  } on Object catch (error, stack) {
    Log.e('reminder sync on boot failed', error, stack);
  }
}

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
