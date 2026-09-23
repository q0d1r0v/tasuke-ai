import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

void main() {
  const WhenParser parser = WhenParser();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');

  group('absolute dates', () {
    test('the rule this file exists to pin', () {
      expect(ExtractionDefaults.bareDateRollsToNextYear, isTrue);
    });

    test('month and day, in either order and at any length', () {
      for (final String phrase in <String>[
        'sep 21',
        'sep. 21',
        'sept 21',
        'september 21',
        'september 21st',
        '21 sep',
        '21st september',
        'the 21st of september',
      ]) {
        expect(
          parser.parse(phrase, now: now).date?.toIso(),
          '2026-09-21',
          reason: phrase,
        );
      }
    });

    test('an explicit year is taken at its word', () {
      expect(parser.parse('sep 21 2027', now: now).date?.toIso(), '2027-09-21');
      expect(
        parser.parse('september 21, 2027', now: now).date?.toIso(),
        '2027-09-21',
      );
      expect(
        parser.parse('21 september 2027', now: now).date?.toIso(),
        '2027-09-21',
      );
    });

    test('a date with no year that has gone past rolls to next year', () {
      expect(parser.parse('sep 20', now: now).date?.toIso(), '2027-09-20');
      expect(parser.parse('mar 5', now: now).date?.toIso(), '2027-03-05');
      expect(
        parser.parse('dec 25', now: now).date?.toIso(),
        '2026-12-25',
        reason: 'December has not happened yet',
      );
    });

    test('29 February skips the years that do not have one', () {
      expect(parser.parse('feb 29', now: now).date?.toIso(), '2028-02-29');
    });

    test('ISO dates', () {
      expect(parser.parse('2026-09-21', now: now).date?.toIso(), '2026-09-21');
      expect(
        parser.parse('due 2027-01-05', now: now).date?.toIso(),
        '2027-01-05',
      );
    });

    test('slashed dates are read in US order', () {
      expect(parser.parse('9/21', now: now).date?.toIso(), '2026-09-21');
      expect(parser.parse('12/25', now: now).date?.toIso(), '2026-12-25');
      expect(parser.parse('9/21/2027', now: now).date?.toIso(), '2027-09-21');
      expect(
        parser.parse('9/21/27', now: now).date?.toIso(),
        '2027-09-21',
        reason: 'two-digit years are this century',
      );
      expect(
        parser.parse('21/9', now: now).isEmpty,
        isTrue,
        reason: 'day/month order is refused rather than guessed at',
      );
    });

    test('a day of the month alone is the next one of those', () {
      expect(parser.parse('on the 5th', now: now).date?.toIso(), '2026-10-05');
      expect(
        parser.parse('the 21st', now: now).date?.toIso(),
        '2026-09-21',
        reason: 'today still counts',
      );
      expect(parser.parse('the 22nd', now: now).date?.toIso(), '2026-09-22');
      expect(
        parser.parse('the 31st', now: now).date?.toIso(),
        '2026-10-31',
        reason: 'September has no 31st, so it skips a month',
      );
    });

    test(
      'a date that does not exist parses to nothing, never to a wrong date',
      () {
        for (final String phrase in <String>[
          'feb 30',
          'february 31',
          '2026-02-30',
          '2026-13-01',
          '2026-00-10',
          '13/40',
          'the 45th',
        ]) {
          expect(
            parser.parse(phrase, now: now).isEmpty,
            isTrue,
            reason: phrase,
          );
        }
      },
    );

    test('a named month beats the vaguer reading that starts before it', () {
      // ⚠️ "on the 5th" and "Thursday" start earlier than the date they are
      // part of, and used to win: the next 5th, or this Thursday.
      for (final (String phrase, String date) in <(String, String)>[
        ('on the 5th of December', '2026-12-05'),
        ('by the fifth of December', '2026-12-05'),
        ('for the 12th of January 2027', '2027-01-12'),
        ('on Thursday, October 15th', '2026-10-15'),
        ('Thursday the 15th of October', '2026-10-15'),
        ('next Friday, the 2nd of October', '2026-10-02'),
      ]) {
        final ParsedWhen parsed = parser.parse(phrase, now: now);
        expect(parsed.date?.toIso(), date, reason: phrase);
        expect(parsed.confidence, Confidence.high, reason: phrase);
        expect(
          (parsed.matchStart, parsed.matchEnd),
          (0, phrase.length),
          reason: '$phrase: none of it may stay in the title',
        );
      }
    });

    test('a weekday that disagrees with its date keeps the date, and asks', () {
      // 16 October 2026 is a Friday.
      final ParsedWhen parsed = parser.parse(
        'on Thursday, October 16th',
        now: now,
      );
      expect(parsed.date?.toIso(), '2026-10-16');
      expect(parsed.confidence, Confidence.low);
    });

    test('a weekday and a date said apart stay apart', () {
      expect(
        parser.parse('Friday and December 5', now: now).date?.toIso(),
        '2026-09-25',
      );
    });

    group('a weekday with a day of the month', () {
      // ⚠️ "Monday the 5th", "Monday, October fifth" and "Thursday, October
      // the 1st" all used to be the coming weekday — leftmost wins — one to
      // three weeks early, at high confidence. 23 September 2026 is a
      // Wednesday; 5 October a Monday, 1 October and 5 November Thursdays.
      final LocalDateTime wednesday = LocalDateTime.parseIso(
        '2026-09-23T15:00',
      );

      test('is the next such day that falls on that weekday', () {
        for (final (String phrase, String date, String? time)
            in <(String, String, String?)>[
              ('on Monday the 5th at 9', '2026-10-05', '09:00'),
              ('Thursday the 1st', '2026-10-01', null),
              ('on Monday, the 5th', '2026-10-05', null),
              ('Monday the fifth', '2026-10-05', null),
              ('on Monday, October fifth', '2026-10-05', null),
              ('on Thursday, October the 1st', '2026-10-01', null),
              ('Thursday morning, October fifteenth', '2026-10-15', '09:00'),
              // The 5th of October is a Monday; November's is the Thursday.
              ('Thursday the 5th', '2026-11-05', null),
              ('Wednesday the 23rd', '2026-09-23', null),
            ]) {
          final ParsedWhen parsed = parser.parse(phrase, now: wednesday);
          expect(parsed.date?.toIso(), date, reason: phrase);
          expect(parsed.time?.toIso(), time, reason: phrase);
          expect(parsed.confidence, Confidence.high, reason: phrase);
          expect(
            (parsed.matchStart, parsed.matchEnd),
            (0, phrase.length),
            reason: '$phrase: none of it may stay in the title',
          );
        }
      });

      test('"October the 1st" is a date on its own too', () {
        final ParsedWhen parsed = parser.parse('on October the 1st', now: now);
        expect(parsed.date?.toIso(), '2026-10-01');
        expect(parsed.confidence, Confidence.high);
      });

      test('that never agrees keeps the date, and asks', () {
        // Neither the 5th of October (a Monday) nor of November (a Thursday)
        // is a Tuesday, and a Tuesday months away would be a silent guess.
        final ParsedWhen parsed = parser.parse(
          'Tuesday the 5th',
          now: wednesday,
        );
        expect(parsed.date?.toIso(), '2026-10-05');
        expect(parsed.confidence, Confidence.low);
      });

      test('a spelled ordinal that counts something is not a date', () {
        for (final String phrase in <String>[
          'Monday the second meeting',
          'Monday the first thing',
          // "the second I land" is "the moment I land".
          'Monday the second I land',
          'Monday the second we land',
        ]) {
          final ParsedWhen parsed = parser.parse(phrase, now: wednesday);
          expect(parsed.date?.toIso(), '2026-09-28', reason: phrase);
          expect(parsed.matchEnd, 'Monday'.length, reason: phrase);
        }
      });

      test('said apart, or after a past weekday, they stay apart', () {
        expect(
          parser.parse('Monday and the 5th', now: wednesday).date?.toIso(),
          '2026-09-28',
        );
        expect(
          parser.parse('last Monday the 5th', now: wednesday).date?.toIso(),
          '2026-09-21',
          reason: 'the day of the month only ever looks ahead',
        );
      });
    });

    test('the match span covers the whole date phrase', () {
      const String phrase = 'submit the form on 2026-12-25';
      final ParsedWhen parsed = parser.parse(phrase, now: now);
      expect(
        phrase.substring(parsed.matchStart, parsed.matchEnd),
        '2026-12-25',
      );
    });
  });
}
