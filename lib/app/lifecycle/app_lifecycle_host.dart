import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/lifecycle/app_lifecycle.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/notifications/tz_service.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';

/// Everything that has to happen because time passed or the device changed.
///
/// ⚠️ This whole layer was built and never mounted. `appResumedProvider`,
/// `timezoneChangesProvider` and `TzService.refresh()` each had zero consumers,
/// and `todayProvider`'s own doc comment asked — in writing — for an owner that
/// did not exist:
///
///   "Whoever owns the app lifecycle must `ref.invalidate(todayProvider)` on
///    resume and on a day-boundary timer; without that, 'Today' keeps meaning
///    yesterday and every overdue task quietly stays out of the list."
///
/// Phones keep a Flutter process alive for days, so that is not a corner case.
/// The morning after, Home still filtered against yesterday; and a user who
/// flew Tashkent → London kept every alarm resolved against the old zone until
/// they happened to edit a task.
///
/// It sits above `MaterialApp.router` so a route change can never unmount it.
class AppLifecycleHost extends ConsumerStatefulWidget {
  const AppLifecycleHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends ConsumerState<AppLifecycleHost> {
  /// ⚠️ A one-shot, re-armed from the clock each time — never
  /// `Timer.periodic(Duration(days: 1))`. A 24-hour period drifts an hour at
  /// every DST transition and never re-syncs, so within a year the "midnight"
  /// tick is happening mid-afternoon.
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _armMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  void _armMidnight() {
    _midnight?.cancel();
    _midnight = Timer(
      untilNextLocalMidnight(ref.read(clockProvider).nowLocal()),
      () {
        if (!mounted) return;
        Log.d('local midnight — rolling the day over');
        ref.invalidate(todayProvider);
        _armMidnight();
      },
    );
  }

  /// The sweep that keeps the OS's pending alarms honest.
  ///
  /// Detached and guarded: `LocalReminderScheduler.sync()` re-exposes errors
  /// from reading settings and from the permission check, and an uncaught
  /// async error raised from a lifecycle callback arrives with no stack worth
  /// reading.
  void _resync(String because) {
    unawaited(() async {
      try {
        await ref.read(reminderSchedulerProvider).sync();
      } on Object catch (error, stack) {
        Log.e('reminder re-sync after $because failed', error, stack);
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ Registered in `build` because that is the only place `WidgetRef.listen`
    // is legal. Both handlers are one-liners; the work they start is detached.
    ref.listen<AsyncValue<int>>(appResumedProvider, (
      AsyncValue<int>? _,
      AsyncValue<int> _,
    ) {
      // The day may have rolled over while the process slept — the OS suspends
      // Dart timers in the background, so `_midnight` cannot be relied on to
      // have fired. Re-arming is what covers that.
      ref.invalidate(todayProvider);
      _armMidnight();
      // A permission the user changed in the Settings app is the other thing
      // that goes stale while the app is away.
      ref.invalidate(permissionStatusProvider);
      // ⚠️ The zone is re-read here, and nowhere else after startup. Android
      // does not restart a live process on a timezone change, so without this
      // a user who landed in Tokyo kept resolving new reminders against
      // Tashkent. A change also fires the zone listener below, whose extra
      // sweep is merged with or queued behind this one, and harmless.
      final TzService tz = ref.read(tzServiceProvider);
      unawaited(() async {
        try {
          await tz.refresh();
        } on Object catch (error, stack) {
          Log.e('timezone refresh on resume failed', error, stack);
        }
        _resync('resume');
      }());
    });

    // A flight, or a manual zone change. Every pending reminder is resolved
    // against a zone, so one change invalidates all of them at once.
    ref.listen<AsyncValue<String>>(timezoneChangesProvider, (
      AsyncValue<String>? _,
      AsyncValue<String> next,
    ) {
      final String? zone = next.value;
      if (zone == null) return;
      Log.d('timezone changed to $zone — re-resolving reminders');
      ref.invalidate(todayProvider);
      _resync('a timezone change');
    });

    return widget.child;
  }
}
