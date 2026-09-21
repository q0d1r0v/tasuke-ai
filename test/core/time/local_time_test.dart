import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

/// The three value objects the whole app's time handling rests on.
///
/// They exist because a `DateTime` carries a zone and these things must not:
/// `2026-09-22` is the same date in Tashkent and in Tokyo, and "3 PM" is the
/// same appointment wherever the user wakes up.
void main() {
  group('LocalDate', () {
    test('parses and re-emits ISO, which is also its sort order', () {
      final LocalDate date = LocalDate.parseIso('2026-09-21');
      expect(date, const LocalDate(2026, 9, 21));
      expect(date.toIso(), '2026-09-21');

      // ⚠️ The reason the database stores TEXT rather than an epoch day:
      // ISO-8601 sorts lexicographically in true chronological order, so
      // `ORDER BY due_date` is both correct and index-served.
      final List<String> isos = <String>[
        const LocalDate(2026, 12, 1).toIso(),
        const LocalDate(2026, 2, 9).toIso(),
        const LocalDate(2027, 1, 1).toIso(),
      ]..sort();
      expect(isos, <String>['2026-02-09', '2026-12-01', '2027-01-01']);
    });

    test('rejects anything that is not a real calendar date', () {
      expect(() => LocalDate.parseIso('2026-13-01'), throwsFormatException);
      expect(() => LocalDate.parseIso('2026-02-30'), throwsFormatException);
      expect(() => LocalDate.parseIso('2026-00-10'), throwsFormatException);
      expect(() => LocalDate.parseIso('2026-09-1'), throwsFormatException);
      expect(() => LocalDate.parseIso('21/09/2026'), throwsFormatException);
      expect(() => LocalDate.parseIso('not a date'), throwsFormatException);
    });

    test('tryParseIso returns null instead of throwing', () {
      // Model output and user input both land here, and a throw there is a
      // crash the user caused by speaking.
      expect(LocalDate.tryParseIso(null), isNull);
      expect(LocalDate.tryParseIso('2026-02-30'), isNull);
      expect(LocalDate.tryParseIso('2026-09-21'), const LocalDate(2026, 9, 21));
    });

    test('leap years, and February with them', () {
      expect(LocalDate.isLeapYear(2028), isTrue);
      expect(LocalDate.isLeapYear(2027), isFalse);
      // The century rule, which is where hand-rolled implementations go wrong.
      expect(LocalDate.isLeapYear(1900), isFalse);
      expect(LocalDate.isLeapYear(2000), isTrue);

      expect(LocalDate.daysInMonth(2028, 2), 29);
      expect(LocalDate.daysInMonth(2027, 2), 28);
      expect(LocalDate.daysInMonth(2026, 1), 31);
      expect(LocalDate.daysInMonth(2026, 4), 30);
    });

    test('addDays crosses months and years', () {
      expect(
        const LocalDate(2026, 9, 21).addDays(10),
        const LocalDate(2026, 10, 1),
      );
      expect(
        const LocalDate(2026, 12, 31).addDays(1),
        const LocalDate(2027, 1, 1),
      );
      expect(
        const LocalDate(2027, 1, 1).addDays(-1),
        const LocalDate(2026, 12, 31),
      );
      expect(
        const LocalDate(2028, 2, 28).addDays(1),
        const LocalDate(2028, 2, 29),
      );
    });

    test('addMonths CLAMPS rather than rolling over', () {
      // ⚠️ "in a month" from 31 January is 28 or 29 February, never 2 or 3
      // March. Rolling over is the behaviour a naive implementation gets, and
      // it produces a task dated three days after the one the user meant.
      expect(
        const LocalDate(2027, 1, 31).addMonths(1),
        const LocalDate(2027, 2, 28),
      );
      expect(
        const LocalDate(2028, 1, 31).addMonths(1),
        const LocalDate(2028, 2, 29),
      );
      expect(
        const LocalDate(2026, 3, 31).addMonths(1),
        const LocalDate(2026, 4, 30),
      );
      expect(
        const LocalDate(2026, 12, 15).addMonths(1),
        const LocalDate(2027, 1, 15),
      );
      expect(
        const LocalDate(2026, 1, 15).addMonths(-1),
        const LocalDate(2025, 12, 15),
      );
    });

    test('weekday and lastDayOfMonth', () {
      // 2026-09-21 is a Monday.
      expect(const LocalDate(2026, 9, 21).weekday, DateTime.monday);
      expect(const LocalDate(2026, 9, 27).weekday, DateTime.sunday);
      expect(
        const LocalDate(2028, 2, 3).lastDayOfMonth,
        const LocalDate(2028, 2, 29),
      );
    });

    test('differenceInDays, ordering and comparison', () {
      const LocalDate a = LocalDate(2026, 9, 21);
      const LocalDate b = LocalDate(2026, 9, 28);

      expect(b.differenceInDays(a), 7);
      expect(a.differenceInDays(b), -7);
      expect(a.isBefore(b), isTrue);
      expect(b.isAfter(a), isTrue);
      expect(a.isBefore(a), isFalse);
      expect(a.compareTo(b), lessThan(0));
      expect(const LocalDate(2026, 10, 1).compareTo(a), greaterThan(0));
      expect(const LocalDate(2027, 1, 1).compareTo(a), greaterThan(0));
    });

    test('equality, hashCode and toString', () {
      expect(const LocalDate(2026, 9, 21), const LocalDate(2026, 9, 21));
      expect(
        const LocalDate(2026, 9, 21).hashCode,
        const LocalDate(2026, 9, 21).hashCode,
      );
      expect(
        const LocalDate(2026, 9, 21) == const LocalDate(2026, 9, 22),
        isFalse,
      );
      // ignore: unrelated_type_equality_checks
      expect(const LocalDate(2026, 9, 21) == '2026-09-21', isFalse);
      expect(const LocalDate(2026, 9, 21).toString(), '2026-09-21');
    });

    test('today reads the LOCAL fields, never a UTC instant', () {
      // A UTC-based implementation is off by a day for half the world for part
      // of every day, and it is invisible in any test run in UTC+0.
      final DateTime lateEvening = DateTime(2026, 9, 21, 23, 30);
      expect(LocalDate.today(lateEvening), const LocalDate(2026, 9, 21));
    });

    test('toDateTimeLocal is midnight, for formatting only', () {
      final DateTime dt = const LocalDate(2026, 9, 21).toDateTimeLocal();
      expect(dt.year, 2026);
      expect(dt.hour, 0);
    });
  });

  group('LocalTimeOfDay', () {
    test('hour and minute decompose from minuteOfDay', () {
      expect(const LocalTimeOfDay(0).toIso(), '00:00');
      expect(const LocalTimeOfDay(15 * 60).hour, 15);
      expect(const LocalTimeOfDay(15 * 60 + 30).minute, 30);
      expect(const LocalTimeOfDay.hm(9, 5).toIso(), '09:05');
      expect(const LocalTimeOfDay(1439).toIso(), '23:59');
    });

    test('tryFromMinutes rejects out-of-range values', () {
      expect(LocalTimeOfDay.tryFromMinutes(null), isNull);
      expect(LocalTimeOfDay.tryFromMinutes(-1), isNull);
      expect(LocalTimeOfDay.tryFromMinutes(1440), isNull);
      expect(LocalTimeOfDay.tryFromMinutes(0)?.minuteOfDay, 0);
    });

    test('tryParse accepts only HH:MM', () {
      expect(LocalTimeOfDay.tryParse('15:00')?.minuteOfDay, 900);
      expect(LocalTimeOfDay.tryParse(null), isNull);
      expect(LocalTimeOfDay.tryParse('9:30'), isNull);
      expect(LocalTimeOfDay.tryParse('25:00'), isNull);
      expect(LocalTimeOfDay.tryParse('15:60'), isNull);
      expect(LocalTimeOfDay.tryParse('15-00'), isNull);
    });

    test('ordering, equality and toString', () {
      expect(
        const LocalTimeOfDay.hm(9, 0).compareTo(const LocalTimeOfDay.hm(15, 0)),
        lessThan(0),
      );
      expect(const LocalTimeOfDay(540), const LocalTimeOfDay.hm(9, 0));
      expect(
        const LocalTimeOfDay(540).hashCode,
        const LocalTimeOfDay.hm(9, 0).hashCode,
      );
      // ignore: unrelated_type_equality_checks
      expect(const LocalTimeOfDay(540) == 540, isFalse);
      expect(const LocalTimeOfDay.hm(9, 0).toString(), '09:00');
    });
  });

  group('LocalDateTime', () {
    test('round-trips its ISO form', () {
      final LocalDateTime value = LocalDateTime.parseIso('2026-09-21T15:00');
      expect(value.date, const LocalDate(2026, 9, 21));
      expect(value.time, const LocalTimeOfDay.hm(15, 0));
      expect(value.toIso(), '2026-09-21T15:00');
      expect(value.toString(), '2026-09-21T15:00');
    });

    test('rejects and tolerates bad input in the right places', () {
      expect(
        () => LocalDateTime.parseIso('2026-09-21 15:00'),
        throwsFormatException,
      );
      expect(
        () => LocalDateTime.parseIso('2026-09-21T25:00'),
        throwsFormatException,
      );
      expect(() => LocalDateTime.parseIso('short'), throwsFormatException);
      expect(LocalDateTime.tryParseIso(null), isNull);
      expect(LocalDateTime.tryParseIso('nope'), isNull);
      expect(LocalDateTime.tryParseIso('2026-09-21T15:00'), isNotNull);
    });

    test('fromLocal drops the seconds, which no reminder needs', () {
      final LocalDateTime value = LocalDateTime.fromLocal(
        DateTime(2026, 9, 21, 15, 0, 59, 999),
      );
      expect(value.toIso(), '2026-09-21T15:00');
    });

    test('addMinutes crosses midnight in both directions', () {
      final LocalDateTime base = LocalDateTime.parseIso('2026-09-21T23:30');
      expect(base.addMinutes(45).toIso(), '2026-09-22T00:15');
      expect(
        LocalDateTime.parseIso('2026-09-21T00:15').subtractMinutes(30).toIso(),
        '2026-09-20T23:45',
      );
      // A reminder lead of a whole day is a legal, if unusual, setting.
      expect(base.subtractMinutes(24 * 60).toIso(), '2026-09-20T23:30');
    });

    test('ordering compares the date first, then the time', () {
      final LocalDateTime early = LocalDateTime.parseIso('2026-09-21T09:00');
      final LocalDateTime late = LocalDateTime.parseIso('2026-09-21T15:00');
      final LocalDateTime tomorrow = LocalDateTime.parseIso('2026-09-22T08:00');

      expect(early.isBefore(late), isTrue);
      expect(late.isAfter(early), isTrue);
      expect(late.isBefore(tomorrow), isTrue);
      expect(early.compareTo(early), 0);
    });

    test('equality and hashCode', () {
      final LocalDateTime a = LocalDateTime.parseIso('2026-09-21T15:00');
      final LocalDateTime b = LocalDateTime.parseIso('2026-09-21T15:00');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // ignore: unrelated_type_equality_checks
      expect(a == '2026-09-21T15:00', isFalse);
    });
  });
}
