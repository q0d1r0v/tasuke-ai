import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

import '../../helpers/fakes.dart';

/// [FakeLocalNotifier] with a call log, and one id that refuses to schedule.
///
/// The shared fake records *what* it was asked to hold but not the order it was
/// asked in, and the whole point of the sweep is that cancels land before
/// schedules — an alarm re-created before its old copy is removed is a
/// duplicate notification on the user's lock screen.
final class RecordingNotifier implements LocalNotifier {
  RecordingNotifier(this.inner, {this.failingId});

  final FakeLocalNotifier inner;

  /// Scheduling this id throws, the way an OEM build past its alarm quota does.
  final int? failingId;

  final List<String> calls = <String>[];

  @override
  Future<void> initialise() => inner.initialise();

  @override
  Future<bool> hasPermission() => inner.hasPermission();

  @override
  Future<bool> requestPermission() => inner.requestPermission();

  @override
  Future<bool> canScheduleExact() => inner.canScheduleExact();

  @override
  Future<bool> requestExactAlarmPermission() =>
      inner.requestExactAlarmPermission();

  @override
  Future<ScheduleResult> schedule(ScheduledReminder reminder) async {
    calls.add('schedule:${reminder.id}');
    if (reminder.id == failingId) {
      throw StateError('maximum number of alarms exceeded');
    }
    return inner.schedule(reminder);
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel:$id');
    await inner.cancel(id);
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    await inner.cancelAll();
  }

  @override
  Future<List<int>> pendingIds() => inner.pendingIds();

  @override
  Future<String?> consumeLaunchPayload() => inner.consumeLaunchPayload();

  @override
  Stream<String> get taps => inner.taps;
}

LocalDateTime civil(int day, int hour, [int minute = 0]) =>
    LocalDateTime(LocalDate(2026, 3, day), LocalTimeOfDay.hm(hour, minute));

Task reminderTask({
  required String id,
  required int notificationId,
  required LocalDateTime at,
  String title = 'Send the build to James',
}) {
  final DateTime stamp = DateTime.utc(2026, 3, 11, 5);
  return Task(
    id: id,
    title: title,
    createdAt: stamp,
    updatedAt: stamp,
    due: TaskDue(date: at.date, time: at.time),
    reminder: TaskReminder(
      enabled: true,
      at: at,
      notificationId: notificationId,
    ),
  );
}

void main() {
  /// Wednesday 11 March 2026, 10:00 local.
  final Clock clock = FixedClock(DateTime(2026, 3, 11, 10));

  late FakeTaskRepository tasks;
  late FakeLocalNotifier fakeNotifier;
  late RecordingNotifier notifier;
  late AppSettings settings;

  setUp(() {
    tasks = FakeTaskRepository();
    fakeNotifier = FakeLocalNotifier();
    notifier = RecordingNotifier(fakeNotifier);
    settings = AppSettings.defaults;
  });

  tearDown(() {
    fakeNotifier.dispose();
    tasks.dispose();
  });

  LocalReminderScheduler schedulerOver(LocalNotifier target) =>
      LocalReminderScheduler(
        notifier: target,
        tasks: tasks,
        clock: clock,
        readSettings: () async => settings,
        bodyBuilder: (String title) => 'Tap to open this task.',
      );

  LocalReminderScheduler scheduler() => schedulerOver(notifier);

  /// Puts an id in the OS's hands, as a previous sweep would have.
  Future<void> seedHeld(int id) => fakeNotifier.schedule(
    ScheduledReminder(
      id: id,
      title: 'Left over',
      body: 'Tap to open this task.',
      atLocal: civil(12, 9),
      payload: encodeReminderPayload('gone'),
    ),
  );

  group('applying the plan', () {
    test('hands the OS a reminder for every schedulable task', () async {
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
        reminderTask(id: 't-2', notificationId: 22, at: civil(12, 9)),
      ]);

      final SyncOutcome outcome = await scheduler().sync();

      expect(outcome.scheduled, 2);
      expect(fakeNotifier.scheduled.map((ScheduledReminder r) => r.id), <int>[
        11,
        22,
      ]);
      expect(outcome.skippedReason, isNull);
    });

    test('cancels everything it is going to cancel BEFORE it schedules', () async {
      // ⚠️ An alarm re-created before its stale copy is removed is a duplicate
      // on the user's lock screen, and the OS gives no way to tell them apart.
      await seedHeld(99);
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);

      await scheduler().sync();

      expect(notifier.calls, <String>['cancel:99', 'schedule:11']);
    });

    test('carries the task id in the payload so a tap can open it', () async {
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);

      await scheduler().sync();

      expect(
        decodeReminderPayload(fakeNotifier.scheduled.single.payload),
        't-1',
      );
      expect(fakeNotifier.scheduled.single.atLocal, civil(11, 15));
    });

    test('re-arms a held alarm in place, never beside it', () async {
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      await scheduler().sync();
      notifier.calls.clear();

      final SyncOutcome again = await scheduler().sync();

      // Same id, so the OS replaces the alarm: still exactly one.
      expect(again.scheduled, 1);
      expect(notifier.calls, <String>['schedule:11']);
      expect(fakeNotifier.scheduled, hasLength(1));
    });

    test('a reminder moved to a new time moves its alarm', () async {
      // ⚠️ The bug this pins shipped. The sweep skipped every id the plugin
      // already listed, and that list has ids but no times — so a reminder
      // moved from 15:00 to 18:00 kept ringing at 15:00 and never at 18:00.
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      await scheduler().sync();

      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 18)),
      ]);
      await scheduler().sync();

      expect(fakeNotifier.scheduled.single.atLocal, civil(11, 18));
    });

    test('a renamed task re-arms with its new title', () async {
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      await scheduler().sync();

      tasks.seed(<Task>[
        reminderTask(
          id: 't-1',
          notificationId: 11,
          at: civil(11, 15),
          title: 'Call James',
        ),
      ]);
      await scheduler().sync();

      expect(fakeNotifier.scheduled.single.title, 'Call James');
    });

    test('an exact-alarm grant upgrades what is already scheduled', () async {
      fakeNotifier.exact = false;
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      expect((await scheduler().sync()).exact, isFalse);

      fakeNotifier.exact = true;
      final SyncOutcome after = await scheduler().sync();

      expect(after.exact, isTrue);
      expect(after.scheduled, 1);
    });

    test(
      'sweeps an orphan left by a task deleted while the process was dead',
      () async {
        await seedHeld(99);

        final SyncOutcome outcome = await scheduler().sync();

        expect(outcome.cancelled, 1);
        expect(fakeNotifier.cancelled, <int>[99]);
        expect(fakeNotifier.scheduled, isEmpty);
      },
    );
  });

  group('two sweeps at once', () {
    test('serialise, and neither one hangs', () async {
      // ⚠️ The first implementation spun on `while (_inFlight != null) await
      // _inFlight;`. Awaiting an already-completed future only yields a
      // microtask, and Dart drains the whole microtask queue before it looks at
      // timers or events — so the second caller starved the event loop and the
      // isolate stopped responding. It presents as a native hang that no test
      // timeout can interrupt, which is why this case is pinned.
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
        reminderTask(id: 't-2', notificationId: 22, at: civil(12, 9)),
      ]);
      final LocalReminderScheduler subject = scheduler();

      final List<SyncOutcome> outcomes = await Future.wait<SyncOutcome>(
        <Future<SyncOutcome>>[subject.sync(), subject.sync()],
      );

      expect(outcomes, hasLength(2));
      // Both calls land before a sweep starts, so they share one.
      expect(outcomes.first.scheduled, 2);
      expect(outcomes.last.scheduled, 2);
      expect(
        fakeNotifier.scheduled.map((ScheduledReminder r) => r.id).toSet(),
        <int>{11, 22},
        reason: 'neither sweep may re-create what the other just scheduled',
      );
    });

    test('calls made before a sweep starts share it', () async {
      // A tick, a title debounce and a resume each ask for a sweep; each used
      // to re-arm the whole window on its own.
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      final LocalReminderScheduler subject = scheduler();

      final List<SyncOutcome> outcomes = await Future.wait<SyncOutcome>(
        <Future<SyncOutcome>>[subject.sync(), subject.sync(), subject.sync()],
      );

      expect(notifier.calls, <String>['schedule:11']);
      expect(outcomes.map((SyncOutcome o) => o.scheduled), <int>[1, 1, 1]);
    });

    test('a call made while a sweep runs gets its own, after it', () async {
      // ⚠️ The shared sweep is released when it STARTS. This caller may have
      // written after the running sweep read the tasks, so sharing it would
      // drop that write until the next unrelated sweep.
      final _GatedNotifier gated = _GatedNotifier(fakeNotifier);
      final Completer<void> release = Completer<void>();
      gated.gate = release;
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      final LocalReminderScheduler subject = schedulerOver(gated);

      final Future<SyncOutcome> running = subject.sync();
      await Future<void>.delayed(Duration.zero);
      expect(gated.gate, isNull, reason: 'parked after reading the tasks');

      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
        reminderTask(id: 't-2', notificationId: 22, at: civil(12, 9)),
      ]);
      final Future<SyncOutcome> later = subject.sync();
      expect(later, isNot(same(running)));

      release.complete();
      expect((await running).scheduled, 1);
      expect((await later).scheduled, 2, reason: 'it saw the mid-sweep write');
      expect(gated.calls, <String>[
        'schedule:11',
        'schedule:11',
        'schedule:22',
      ]);
    });

    test('a failed sweep does not poison the ones queued behind it', () async {
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      final LocalReminderScheduler subject = schedulerOver(
        _ThrowingPendingIdsOnce(notifier),
      );

      await expectLater(subject.sync(), throwsA(isA<StateError>()));

      final SyncOutcome second = await subject.sync();
      expect(second.scheduled, 1);
    });
  });

  group('when the OS will not cooperate', () {
    test(
      'no notification permission cancels everything and says why',
      () async {
        await seedHeld(99);
        fakeNotifier.permitted = false;
        tasks.seed(<Task>[
          reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
        ]);

        final SyncOutcome outcome = await scheduler().sync();

        expect(outcome.skippedReason, 'notifications-not-permitted');
        expect(outcome.scheduled, 0);
        expect(outcome.cancelled, 1);
        expect(
          fakeNotifier.scheduled,
          isEmpty,
          reason: 'a later grant must start from a clean slate',
        );
      },
    );

    test('an inexact schedule surfaces in the outcome rather than failing', () async {
      // Android 12+ refusing SCHEDULE_EXACT_ALARM means the reminder may land
      // up to ~15 minutes late. The UI says so once; it does not treat it as an
      // error, because the alarm was in fact set.
      fakeNotifier.exact = false;
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);

      final SyncOutcome outcome = await scheduler().sync();

      expect(outcome.exact, isFalse);
      expect(outcome.scheduled, 1);
    });

    test('one alarm the OS refuses does not abort the rest of the sweep', () async {
      // The task is already saved and the user's other reminders still matter.
      final RecordingNotifier flaky = RecordingNotifier(
        fakeNotifier,
        failingId: 11,
      );
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
        reminderTask(id: 't-2', notificationId: 22, at: civil(12, 9)),
      ]);

      final SyncOutcome outcome = await schedulerOver(flaky).sync();

      expect(outcome.scheduled, 1);
      expect(flaky.calls, <String>['schedule:11', 'schedule:22']);
      expect(fakeNotifier.scheduled.map((ScheduledReminder r) => r.id), <int>[
        22,
      ]);
    });

    test('the notifications switch being off clears the OS entirely', () async {
      await seedHeld(99);
      settings = AppSettings.defaults.copyWith(notificationsEnabled: false);
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);

      final SyncOutcome outcome = await scheduler().sync();

      expect(outcome.scheduled, 0);
      expect(fakeNotifier.cancelled, <int>[99]);
    });
  });

  group('cancelAll', () {
    test('clears the OS in one call rather than id by id', () async {
      tasks.seed(<Task>[
        reminderTask(id: 't-1', notificationId: 11, at: civil(11, 15)),
      ]);
      await scheduler().sync();
      notifier.calls.clear();

      await scheduler().cancelAll();

      expect(notifier.calls, <String>['cancelAll']);
      expect(fakeNotifier.scheduled, isEmpty);
    });
  });

  group('the reminder payload', () {
    test('round-trips a task id', () {
      expect(decodeReminderPayload(encodeReminderPayload('t-7')), 't-7');
    });

    test('is null for anything that is not our shape', () {
      // ⚠️ Null, never a throw: a malformed payload must open Home, not crash
      // the launch. The OS hands this back after a reboot, an app update and a
      // notification the user tapped six weeks ago.
      for (final String? payload in <String?>[
        null,
        '',
        'not json at all',
        '[1,2,3]',
        '{"taskId":""}',
        '{"taskId":42}',
        '{"other":"t-7"}',
        '{"taskId":',
      ]) {
        expect(
          decodeReminderPayload(payload),
          isNull,
          reason: 'payload ${payload ?? '<null>'} should decode to null',
        );
      }
    });
  });
}

/// Parks the first `schedule` call on [gate], so a sweep can be caught after
/// it has read the tasks and before it has finished.
final class _GatedNotifier extends RecordingNotifier {
  _GatedNotifier(super.inner);

  Completer<void>? gate;

  @override
  Future<ScheduleResult> schedule(ScheduledReminder reminder) async {
    final Completer<void>? held = gate;
    gate = null;
    if (held != null) await held.future;
    return super.schedule(reminder);
  }
}

/// Fails the first `pendingIds` call, so the sweep behind it can be observed
/// starting from a clean queue.
final class _ThrowingPendingIdsOnce implements LocalNotifier {
  _ThrowingPendingIdsOnce(this._inner);

  final LocalNotifier _inner;
  bool _thrown = false;

  @override
  Future<List<int>> pendingIds() async {
    if (!_thrown) {
      _thrown = true;
      throw StateError('the notification service died');
    }
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
  Future<ScheduleResult> schedule(ScheduledReminder reminder) =>
      _inner.schedule(reminder);

  @override
  Future<void> cancel(int id) => _inner.cancel(id);

  @override
  Future<void> cancelAll() => _inner.cancelAll();

  @override
  Future<String?> consumeLaunchPayload() => _inner.consumeLaunchPayload();

  @override
  Stream<String> get taps => _inner.taps;
}
