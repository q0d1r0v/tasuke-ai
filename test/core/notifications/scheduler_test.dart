import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/notifications/flutter_local_notifier.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/notifications/tz_service.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:timezone/timezone.dart' as tz;

/// One `zonedSchedule` call, as the OS would have received it.
final class ScheduledCall {
  const ScheduledCall({
    required this.id,
    required this.at,
    required this.exact,
    required this.payload,
  });

  final int id;
  final tz.TZDateTime at;
  final bool exact;
  final String payload;
}

/// A [NotificationHost] that records instead of calling a MethodChannel.
final class RecordingHost implements NotificationHost {
  final List<String> calls = <String>[];
  final List<ScheduledCall> scheduled = <ScheduledCall>[];

  bool exactAllowed = true;
  String? launch;
  void Function(String payload)? _onTap;

  void tap(String payload) => _onTap?.call(payload);

  @override
  Future<void> initialise({
    required void Function(String payload) onTap,
  }) async {
    _onTap = onTap;
    calls.add('initialise');
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required String payload,
    required bool exact,
    required NotificationStrings strings,
  }) async {
    calls.add('schedule:$id');
    scheduled.add(
      ScheduledCall(id: id, at: at, exact: exact, payload: payload),
    );
  }

  @override
  Future<void> cancel(int id) async => calls.add('cancel:$id');

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<List<int>> pendingIds() async =>
      scheduled.map((ScheduledCall call) => call.id).toList();

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<bool> canScheduleExact() async => exactAllowed;

  @override
  Future<bool> requestExactAlarmPermission() async => true;

  @override
  Future<String?> launchPayload() async => launch;
}

Future<({FlutterLocalNotifier notifier, RecordingHost host})> notifierIn(
  String zone, {
  bool exactAllowed = true,
}) async {
  final TzService timezones = TzService(lookup: () async => zone);
  final RecordingHost host = RecordingHost()..exactAllowed = exactAllowed;
  final FlutterLocalNotifier notifier = FlutterLocalNotifier(
    host: host,
    tz: timezones,
  );
  await notifier.initialise();
  return (notifier: notifier, host: host);
}

LocalDateTime civil(int y, int m, int d, int hour, int minute) =>
    LocalDateTime(LocalDate(y, m, d), LocalTimeOfDay.hm(hour, minute));

ScheduledReminder reminder({int id = 1, required LocalDateTime at}) =>
    ScheduledReminder(
      id: id,
      title: 'Send the build',
      body: 'Tap to open this task.',
      atLocal: at,
      payload: '{"taskId":"t-1"}',
    );

void main() {
  group('a civil reminder becomes an instant at scheduling time', () {
    test('same day, in the device zone', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('America/New_York');

      await setup.notifier.schedule(reminder(at: civil(2026, 9, 21, 15, 30)));

      final tz.Location newYork = tz.getLocation('America/New_York');
      expect(
        setup.host.scheduled.single.at,
        tz.TZDateTime(newYork, 2026, 9, 21, 15, 30),
      );
      await setup.notifier.dispose();
    });

    test(
      'crossing midnight is a different calendar day, not an offset',
      () async {
        final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
            await notifierIn('America/New_York');

        await setup.notifier.schedule(reminder(at: civil(2026, 9, 22, 0, 15)));

        final tz.TZDateTime at = setup.host.scheduled.single.at;
        expect(at.year, 2026);
        expect(at.month, 9);
        expect(at.day, 22);
        expect(at.hour, 0);
        expect(at.minute, 15);
        await setup.notifier.dispose();
      },
    );

    test('02:30 on a spring-forward night shifts to 03:30 and stays EDT', () async {
      // 8 March 2026: America/New_York jumps 02:00 → 03:00. 02:30 does not
      // exist that night, and TZDateTime normalising it forward is the correct
      // answer — the alternative is a reminder that never fires.
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('America/New_York');

      await setup.notifier.schedule(reminder(at: civil(2026, 3, 8, 2, 30)));

      final tz.TZDateTime at = setup.host.scheduled.single.at;
      expect(at.hour, 3, reason: 'the skipped hour rolls forward');
      expect(at.minute, 30);
      expect(
        at.timeZoneOffset,
        const Duration(hours: -4),
        reason: 'after the transition the zone is EDT, not EST',
      );
      await setup.notifier.dispose();
    });

    test('an hour before the transition is still EST', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('America/New_York');

      await setup.notifier.schedule(reminder(at: civil(2026, 3, 8, 1, 30)));

      final tz.TZDateTime at = setup.host.scheduled.single.at;
      expect(at.hour, 1);
      expect(at.timeZoneOffset, const Duration(hours: -5));
      await setup.notifier.dispose();
    });

    test('a 45-minute offset zone resolves exactly', () async {
      // Asia/Kathmandu is UTC+05:45. Any code that assumes whole-hour offsets
      // is off by 45 minutes here and nowhere else, which is why this case is
      // pinned rather than trusted.
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Kathmandu');

      await setup.notifier.schedule(reminder(at: civil(2026, 9, 21, 9, 0)));

      final tz.TZDateTime at = setup.host.scheduled.single.at;
      expect(at.hour, 9);
      expect(at.minute, 0);
      expect(at.timeZoneOffset, const Duration(hours: 5, minutes: 45));
      expect(at.toUtc().hour, 3);
      expect(at.toUtc().minute, 15);
      await setup.notifier.dispose();
    });
  });

  group('notification ids', () {
    test('are a stable function of the task id', () {
      expect(
        NotificationIds.forTask('b3f1c0de-0000-4000-8000-000000000001'),
        NotificationIds.forTask('b3f1c0de-0000-4000-8000-000000000001'),
      );
      // Pinned, not just self-consistent: the point of the function is that a
      // reminder scheduled by one release is cancellable by the next, so the
      // value has to survive a change of SDK as well as a change of process.
      expect(NotificationIds.forTask('task-1'), 187962844);
      expect(NotificationIds.forTask('task-2'), 2101052695);
    });

    test('fit in a Java int and are never negative', () {
      for (final String id in <String>['', 'a', 'ЁЁЁ', 'x' * 200]) {
        final int value = NotificationIds.forTask(id);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(2147483648));
      }
    });

    test('differ for ids that differ only in the last character', () {
      expect(
        NotificationIds.forTask('task-a'),
        isNot(NotificationIds.forTask('task-b')),
      );
    });
  });

  group('editing a task', () {
    test('cancels the old alarm before setting the new one', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');

      await setup.notifier.schedule(
        reminder(id: 42, at: civil(2026, 9, 21, 9, 0)),
      );
      await setup.notifier.schedule(
        reminder(id: 42, at: civil(2026, 9, 21, 18, 0)),
      );

      expect(setup.host.calls, <String>[
        'initialise',
        'cancel:42',
        'schedule:42',
        'cancel:42',
        'schedule:42',
      ]);
      expect(setup.host.scheduled.last.at.hour, 18);
      await setup.notifier.dispose();
    });
  });

  group('precision', () {
    test('exact when the OS allows it', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');

      final ScheduleResult result = await setup.notifier.schedule(
        reminder(at: civil(2026, 9, 21, 9, 0)),
      );

      expect(result.precision, SchedulePrecision.exact);
      expect(setup.host.scheduled.single.exact, isTrue);
      await setup.notifier.dispose();
    });

    test('inexact, and reported as such, when it does not', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent', exactAllowed: false);

      final ScheduleResult result = await setup.notifier.schedule(
        reminder(at: civil(2026, 9, 21, 9, 0)),
      );

      expect(result.precision, SchedulePrecision.inexact);
      expect(setup.host.scheduled.single.exact, isFalse);
      await setup.notifier.dispose();
    });
  });

  group('launch payload', () {
    test('is consumed on read', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');
      setup.host.launch = '{"taskId":"t-9"}';

      expect(await setup.notifier.consumeLaunchPayload(), '{"taskId":"t-9"}');
      expect(
        await setup.notifier.consumeLaunchPayload(),
        isNull,
        reason: 'a replayed launch payload reopens a task already dealt with',
      );
      await setup.notifier.dispose();
    });
  });

  group('taps', () {
    test('reach the broadcast stream', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');

      final Future<String> first = setup.notifier.taps.first;
      setup.host.tap('{"taskId":"t-3"}');

      expect(await first, '{"taskId":"t-3"}');
      await setup.notifier.dispose();
    });
  });
}
