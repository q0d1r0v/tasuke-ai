import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
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
