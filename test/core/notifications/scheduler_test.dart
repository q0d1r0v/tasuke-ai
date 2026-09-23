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

  /// Ids the plugin's cache no longer lists, the way a fired alarm drops out.
  final Set<int> forgotten = <int>{};

  /// The next `zonedSchedule` throws, as an OEM build past its quota does.
  bool failNextSchedule = false;

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
    if (failNextSchedule) {
      failNextSchedule = false;
      throw StateError('maximum number of alarms exceeded');
    }
    scheduled.add(
      ScheduledCall(id: id, at: at, exact: exact, payload: payload),
    );
  }

  @override
  Future<void> cancel(int id) async => calls.add('cancel:$id');

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<List<int>> pendingIds() async => scheduled
      .map((ScheduledCall call) => call.id)
      .where((int id) => !forgotten.contains(id))
      .toList();

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

ScheduledReminder reminder({
  int id = 1,
  required LocalDateTime at,
  String title = 'Send the build',
}) => ScheduledReminder(
  id: id,
  title: title,
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

  group('a re-arm this process already made identically', () {
    // Every sweep re-arms the whole window. On Android each re-arm is a cancel
    // and a schedule that both rewrite the plugin's whole JSON cache on the UI
    // thread, so an unchanged alarm is left alone. ⚠️ The memo is in memory
    // only and is never seeded from `pendingIds()`: that list is the plugin's
    // SharedPreferences cache, not what AlarmManager holds.
    List<String> osCalls(RecordingHost host) =>
        host.calls.where((String call) => call != 'initialise').toList();

    test('is skipped', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');

      final ScheduleResult first = await setup.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 9, 0)),
      );
      final ScheduleResult second = await setup.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 9, 0)),
      );

      expect(osCalls(setup.host), <String>['cancel:7', 'schedule:7']);
      expect(first.precision, SchedulePrecision.exact);
      expect(second.precision, SchedulePrecision.exact);
      await setup.notifier.dispose();
    });

    test('still happens when the time, title or precision changed', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');

      await setup.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 9, 0)),
      );
      await setup.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 10, 0)),
      );
      await setup.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 10, 0), title: 'Call James'),
      );
      setup.host.exactAllowed = false;
      final ScheduleResult inexact = await setup.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 10, 0), title: 'Call James'),
      );

      expect(
        setup.host.calls.where((String c) => c == 'schedule:7'),
        hasLength(4),
      );
      expect(inexact.precision, SchedulePrecision.inexact);
      expect(setup.host.scheduled.last.exact, isFalse);
      await setup.notifier.dispose();
    });

    test('still happens after a cancel or a cancelAll', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');
      final ScheduledReminder same = reminder(
        id: 7,
        at: civil(2026, 9, 21, 9, 0),
      );

      await setup.notifier.schedule(same);
      await setup.notifier.cancel(7);
      await setup.notifier.schedule(same);
      await setup.notifier.cancelAll();
      await setup.notifier.schedule(same);

      expect(osCalls(setup.host), <String>[
        'cancel:7',
        'schedule:7',
        'cancel:7',
        'cancel:7',
        'schedule:7',
        'cancelAll',
        'cancel:7',
        'schedule:7',
      ]);
      await setup.notifier.dispose();
    });

    test('still happens once the plugin stops listing the id', () async {
      // It fired, or the plugin's cache was lost: absence is trusted, presence
      // never is.
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');
      final ScheduledReminder same = reminder(
        id: 7,
        at: civil(2026, 9, 21, 9, 0),
      );
      await setup.notifier.schedule(same);

      setup.host.forgotten.add(7);
      expect(await setup.notifier.pendingIds(), isEmpty);
      await setup.notifier.schedule(same);

      expect(
        setup.host.calls.where((String c) => c == 'schedule:7'),
        hasLength(2),
      );
      await setup.notifier.dispose();
    });

    test('still happens after a schedule that failed', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) setup =
          await notifierIn('Asia/Tashkent');
      final ScheduledReminder same = reminder(
        id: 7,
        at: civil(2026, 9, 21, 9, 0),
      );
      await setup.notifier.schedule(same);

      // A move that the OS refuses leaves the old claim dropped as well.
      setup.host.failNextSchedule = true;
      await expectLater(
        setup.notifier.schedule(reminder(id: 7, at: civil(2026, 9, 21, 10, 0))),
        throwsA(isA<Object>()),
      );
      await setup.notifier.schedule(same);

      expect(
        setup.host.calls.where((String c) => c == 'schedule:7'),
        hasLength(3),
      );
      await setup.notifier.dispose();
    });

    test('is forgotten by a new notifier, as by a new process', () async {
      final ({FlutterLocalNotifier notifier, RecordingHost host}) first =
          await notifierIn('Asia/Tashkent');
      await first.notifier.schedule(
        reminder(id: 7, at: civil(2026, 9, 21, 9, 0)),
      );
      await first.notifier.dispose();

      final FlutterLocalNotifier second = FlutterLocalNotifier(
        host: first.host,
        tz: TzService(lookup: () async => 'Asia/Tashkent'),
      );
      await second.initialise();
      await second.schedule(reminder(id: 7, at: civil(2026, 9, 21, 9, 0)));

      expect(
        first.host.calls.where((String c) => c == 'schedule:7'),
        hasLength(2),
      );
      await second.dispose();
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
