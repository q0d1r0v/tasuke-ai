import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

void main() {
  const WhenParser parser = WhenParser();
  // A Monday, mid-morning. Every expectation below is relative to it.
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');

  group('relative days', () {
    test('today, tomorrow and yesterday', () {
      expect(parser.parse('today', now: now).date?.toIso(), '2026-09-21');
      expect(parser.parse('tomorrow', now: now).date?.toIso(), '2026-09-22');
      expect(parser.parse('yesterday', now: now).date?.toIso(), '2026-09-20');
    });

    test('the day after tomorrow beats the tomorrow inside it', () {
      final ParsedWhen parsed = parser.parse(
        'the day after tomorrow',
        now: now,
      );
      expect(parsed.date?.toIso(), '2026-09-23');
      expect(parsed.matchStart, 0);
      expect(parsed.matchEnd, 'the day after tomorrow'.length);
    });

    test('tonight is today at the night hour', () {
      final ParsedWhen parsed = parser.parse('tonight', now: now);
      expect(parsed.date?.toIso(), '2026-09-21');
      expect(parsed.time?.minuteOfDay, ExtractionDefaults.nightMinute);
    });

    test('tonight, said in the small hours, is the night under way', () {
      // ⚠️ "tonight at 2" said at 00:40 was 02:00 the NEXT night, 25 hours
      // away: the pills reminder fired a day late.
      String at(String nowIso, String phrase) {
        final ParsedWhen parsed = parser.parse(
          phrase,
          now: LocalDateTime.parseIso(nowIso),
        );
        return '${parsed.date?.toIso()} ${parsed.time?.toIso()}';
      }

      expect(at('2026-09-24T00:40', 'tonight at 2'), '2026-09-24 02:00');
      expect(at('2026-09-24T00:10', 'tonight at 1'), '2026-09-24 01:00');
      expect(
        at('2026-09-24T00:40', 'tonight at 12'),
        '2026-09-25 00:00',
        reason: 'this midnight is already behind',
      );
      expect(
        at('2026-09-24T03:00', 'tonight at 1'),
        '2026-09-25 01:00',
        reason: '1 is already behind',
      );
      expect(at('2026-09-23T15:00', 'tonight at 1'), '2026-09-24 01:00');
      expect(at('2026-09-23T23:30', 'tonight at 1'), '2026-09-24 01:00');
      expect(
        at('2026-09-25T00:40', 'this Friday night at 2'),
        '2026-09-26 02:00',
        reason: "a named day's night is still the one ahead",
      );
    });

    test('"ten to one" tonight is ten to one, not ten to two', () {
      // ⚠️ The small hours were built from the hour said after "to": "ten to
      // one" was 01:50, and "a quarter to twelve" 00:45 the next day, when
      // 23:45 tonight was meant.
      String at(String nowIso, String phrase) {
        final ParsedWhen parsed = parser.parse(
          phrase,
          now: LocalDateTime.parseIso(nowIso),
        );
        return '${parsed.date?.toIso()} ${parsed.time?.toIso()}';
      }

      const String afternoon = '2026-09-23T15:00';
      expect(
        at(afternoon, 'tonight at a quarter to twelve'),
        '2026-09-23 23:45',
      );
      expect(at(afternoon, 'tonight at ten to one'), '2026-09-24 00:50');
      expect(at(afternoon, 'tonight at ten past twelve'), '2026-09-24 00:10');
      expect(at(afternoon, 'tonight at a quarter to two'), '2026-09-24 01:45');
      expect(at(afternoon, 'tonight at five to four'), '2026-09-24 03:55');
      expect(
        at('2026-09-24T00:20', 'tonight at a quarter to one'),
        '2026-09-24 00:45',
      );
    });

    test('the small hours come from the time said, not the hour word', () {
      LocalTimeOfDay? small(String said, String time) => WhenParser.smallHours(
        said,
        LocalTimeOfDay.tryParse(time)!,
        night: true,
      );

      expect(small('at 2', '14:00')?.toIso(), '02:00');
      expect(small('at 12', '12:00')?.toIso(), '00:00');
      expect(small('at 4:59', '16:59')?.toIso(), '04:59');
      expect(small('at ten to one', '12:50')?.toIso(), '00:50');
      expect(small('at five to four', '15:55')?.toIso(), '03:55');
      expect(small('at 5', '17:00'), isNull);
      expect(small('at a quarter to twelve', '11:45'), isNull);
      // Already the small hours: the Tonight heading passes them unshifted.
      expect(small('at 3 in the morning', '03:00')?.toIso(), '03:00');
      expect(small('at ten to one in the morning', '00:50')?.toIso(), '00:50');
      expect(
        small('in the afternoon', '14:00'),
        isNull,
        reason: 'a part of the day names no clock hour',
      );
      expect(small('at 14:00', '14:00'), isNull, reason: 'a 24-hour clock');
    });

    test('tonight at midnight is the end of today, not noon', () {
      String at(String phrase) {
        final ParsedWhen parsed = parser.parse(phrase, now: now);
        return '${parsed.date?.toIso()} ${parsed.time?.toIso()}';
      }

      expect(at('tonight at midnight'), '2026-09-22 00:00');
      expect(at('tonight by midnight'), '2026-09-22 00:00');
      expect(at('this evening at midnight'), '2026-09-22 00:00');
      expect(at('tonight at a quarter past midnight'), '2026-09-22 00:15');
      expect(at('tonight at ten to midnight'), '2026-09-21 23:50');
      expect(
        at('tonight at 12 noon'),
        '2026-09-21 12:00',
        reason: 'noon said outright is not the small hours',
      );
    });

    test('a part of the day comes back as its default minute', () {
      expect(
        parser.parse('tomorrow morning', now: now).time?.minuteOfDay,
        ExtractionDefaults.morningMinute,
      );
      expect(
        parser.parse('tomorrow afternoon', now: now).time?.minuteOfDay,
        ExtractionDefaults.afternoonMinute,
      );
      expect(
        parser.parse('tomorrow evening', now: now).time?.minuteOfDay,
        ExtractionDefaults.eveningMinute,
      );
      expect(
        parser.parse('tomorrow night', now: now).time?.minuteOfDay,
        ExtractionDefaults.nightMinute,
      );
    });

    test(
      'a duration in minutes or hours moves the clock, not just the day',
      () {
        final ParsedWhen parsed = parser.parse('in 30 minutes', now: now);
        expect(parsed.date?.toIso(), '2026-09-21');
        expect(parsed.time?.toIso(), '10:30');
        expect(parser.parse('in 2 hours', now: now).time?.toIso(), '12:00');
      },
    );

    test('half hours, however they are said', () {
      // ⚠️ "in an hour and a half" used to match "in an hour": thirty minutes
      // early, with "and a half" left in the title.
      final LocalDateTime three = LocalDateTime.parseIso('2026-09-23T15:00');
      for (final (String phrase, String time) in <(String, String)>[
        ('in half an hour', '15:30'),
        ('in a half hour', '15:30'),
        ('in half hour', '15:30'),
        ('in an hour and a half', '16:30'),
        ('in two hours and a half', '17:30'),
        ('in two and a half hours', '17:30'),
        ('in 1.5 hours', '16:30'),
        ('in a half-hour', '15:30'),
        ('in half-an-hour', '15:30'),
        ('in an hour-and-a-half', '16:30'),
        ('in two-and-a-half hours', '17:30'),
        // Two decimals were read as the clock time "2.25": a day late.
        ('in 2.25 hours', '17:15'),
        ('in 1.50 hours', '16:30'),
      ]) {
        final ParsedWhen parsed = parser.parse(phrase, now: three);
        expect(parsed.date?.toIso(), '2026-09-23', reason: phrase);
        expect(parsed.time?.toIso(), time, reason: phrase);
        expect(
          (parsed.matchStart, parsed.matchEnd),
          (0, phrase.length),
          reason: phrase,
        );
      }
    });

    test('"in an hour\'s time" takes the whole idiom', () {
      // ⚠️ The match stopped at "hour", and the title came out as "Call Anna
      // 's time".
      final LocalDateTime three = LocalDateTime.parseIso('2026-09-23T15:00');
      for (final (String phrase, String date, String? time)
          in <(String, String, String?)>[
            ("in half an hour's time", '2026-09-23', '15:30'),
            ("in an hour's time", '2026-09-23', '16:00'),
            ('in an hour’s time', '2026-09-23', '16:00'),
            ("in an hour and a half's time", '2026-09-23', '16:30'),
            ("in two hours' time", '2026-09-23', '17:00'),
            ('in two hours time', '2026-09-23', '17:00'),
            ('in 1.5 hours time', '2026-09-23', '16:30'),
            ("in a week's time", '2026-09-30', null),
          ]) {
        final ParsedWhen parsed = parser.parse(phrase, now: three);
        expect(parsed.date?.toIso(), date, reason: phrase);
        expect(parsed.time?.toIso(), time, reason: phrase);
        expect(
          (parsed.matchStart, parsed.matchEnd),
          (0, phrase.length),
          reason: phrase,
        );
      }
    });

    test('a duration that crosses midnight moves the day too', () {
      final ParsedWhen parsed = parser.parse(
        'in 45 minutes',
        now: LocalDateTime.parseIso('2026-12-31T23:30'),
      );
      expect(parsed.date?.toIso(), '2027-01-01');
      expect(parsed.time?.toIso(), '00:15');
    });

    test('durations in days, weeks and months', () {
      expect(parser.parse('in 3 days', now: now).date?.toIso(), '2026-09-24');
      expect(parser.parse('in a week', now: now).date?.toIso(), '2026-09-28');
      expect(parser.parse('in 2 weeks', now: now).date?.toIso(), '2026-10-05');
      expect(parser.parse('in a month', now: now).date?.toIso(), '2026-10-21');
    });

    test('the date is found wherever it sits in the sentence', () {
      for (final String phrase in <String>[
        'tomorrow call Mark',
        'call Mark tomorrow',
        'call Mark tomorrow about the invoice',
      ]) {
        expect(
          parser.parse(phrase, now: now).date?.toIso(),
          '2026-09-22',
          reason: phrase,
        );
      }
    });

    test('a relative day is a confident answer', () {
      expect(parser.parse('tomorrow', now: now).confidence, Confidence.high);
    });

    test('next week and next month are answers the user must confirm', () {
      // Monday of next week, and the first of next month — both of them a
      // guess at which day was meant, so the Confirm card flags them.
      final ParsedWhen week = parser.parse('next week', now: now);
      expect(week.date?.toIso(), '2026-09-28');
      expect(week.confidence, Confidence.low);
      final ParsedWhen month = parser.parse('next month', now: now);
      expect(month.date?.toIso(), '2026-10-01');
      expect(month.confidence, Confidence.low);
    });

    test('an empty or whitespace phrase is empty, not a crash', () {
      expect(parser.parse('', now: now).isEmpty, isTrue);
      expect(parser.parse('   \n\t ', now: now).isEmpty, isTrue);
    });
  });
}
