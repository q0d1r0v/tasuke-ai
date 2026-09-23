import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/bootstrap/app_reset.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';

/// Settings → "Delete all data".
///
/// Plain `test`, not `testWidgets`: nothing here draws, and the race below
/// needs the real event loop to interleave a sweep with the reset.
void main() {
  const LocalDate today = LocalDate(2026, 3, 11);

  late FakeLocalNotifier inner;
  late _GatedNotifier notifier;
  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeUsageRepository usage;
  late ProviderContainer container;

  setUp(() {
    inner = FakeLocalNotifier();
    notifier = _GatedNotifier(inner);
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    usage = FakeUsageRepository();
    container = ProviderContainer(
      overrides: <Override>[
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 3, 11, 10))),
        localNotifierProvider.overrideWithValue(notifier),
        taskRepositoryProvider.overrideWithValue(tasks),
        settingsRepositoryProvider.overrideWithValue(settings),
        usageRepositoryProvider.overrideWithValue(usage),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    inner.dispose();
    tasks.dispose();
    settings.dispose();
    usage.dispose();
  });

  Task withReminder(String id, int hour, int notificationId) {
    final DateTime at = DateTime.utc(2026, 3, 11, 5);
    final TaskDue due = TaskDue(date: today, time: LocalTimeOfDay.hm(hour, 0));
    return Task(
      id: id,
      title: 'Task $id',
      createdAt: at,
      updatedAt: at,
      due: due,
      reminder: TaskReminder(
        enabled: true,
        at: LocalDateTime(today, LocalTimeOfDay.hm(hour, 0)),
        notificationId: notificationId,
      ),
    );
  }

  test('a sweep already running cannot re-arm the deleted tasks', () async {
    // ⚠️ The resume sweep read its tasks before the reset and was still
    // scheduling them after `cancelAll`, so a deleted task's title could still
    // ring that evening.
    tasks.seed(<Task>[withReminder('a', 15, 1), withReminder('b', 16, 2)]);
    notifier.gate = Completer<void>();

    final Future<SyncOutcome> sweep = container
        .read(reminderSchedulerProvider)
        .sync();
    await pumpEventQueue();
    expect(notifier.waiting, isTrue, reason: 'the sweep is mid-schedule');

    final Future<void> reset = container.read(databaseResetProvider)();
    await pumpEventQueue();

    notifier.gate!.complete();
    await sweep;
    await reset;

    expect(tasks.all, isEmpty);
    expect(await inner.pendingIds(), isEmpty);
  });

  test('a sweep that fails does not fail the reset', () async {
    tasks.seed(<Task>[withReminder('a', 15, 1)]);
    notifier.failPending = true;

    await container.read(databaseResetProvider)();

    expect(tasks.all, isEmpty);
    expect(inner.cancelledAll, isTrue);
  });
}

/// A notifier whose `schedule` can be held open, to catch a sweep mid-flight.
final class _GatedNotifier implements LocalNotifier {
  _GatedNotifier(this._inner);

  final FakeLocalNotifier _inner;

  Completer<void>? gate;
  bool waiting = false;
  bool failPending = false;

  @override
  Future<ScheduleResult> schedule(ScheduledReminder reminder) async {
    final Completer<void>? held = gate;
    if (held != null) {
      waiting = true;
      await held.future;
    }
    return _inner.schedule(reminder);
  }

  @override
  Future<List<int>> pendingIds() async {
    if (failPending) throw StateError('plugin cache unreadable');
    return _inner.pendingIds();
  }

  @override
  Future<void> initialise() => _inner.initialise();

  @override
  Future<bool> hasPermission() => _inner.hasPermission();

  @override
  Future<bool> requestPermission() => _inner.requestPermission();

  @override
  Future<bool> canScheduleExact() => _inner.canScheduleExact();

  @override
  Future<bool> requestExactAlarmPermission() =>
      _inner.requestExactAlarmPermission();

  @override
  Future<void> cancel(int id) => _inner.cancel(id);

  @override
  Future<void> cancelAll() => _inner.cancelAll();

  @override
  Future<String?> consumeLaunchPayload() => _inner.consumeLaunchPayload();

  @override
  Stream<String> get taps => _inner.taps;
}
