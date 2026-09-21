import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

void main() {
  const WhenParser parser = WhenParser();
  final LocalDateTime monday = LocalDateTime.parseIso('2026-09-21T10:00');
  final LocalDateTime friday = LocalDateTime.parseIso('2026-09-25T09:00');

  group('weekdays', () {
    test('the rule this file exists to pin', () {
      expect(ExtractionDefaults.bareWeekdayIsStrictlyForward, isTrue);
    });

    test('a bare weekday resolves forward', () {
      expect(parser.parse('monday', now: monday).date?.toIso(), '2026-09-28');
      expect(parser.parse('tuesday', now: monday).date?.toIso(), '2026-09-22');
      expect(parser.parse('friday', now: monday).date?.toIso(), '2026-09-25');
      expect(parser.parse('sunday', now: monday).date?.toIso(), '2026-09-27');
    });

    test('Friday said on a Friday is the NEXT Friday, never today', () {
      expect(parser.parse('friday', now: friday).date?.toIso(), '2026-10-02');
    });

    test('"this Friday" said on a Friday is the day you are standing in', () {
      // The one forward form that may land on today: "this" points at the week
      // you are in, "Friday" on its own points at the one coming up.
      expect(
        parser.parse('this friday', now: friday).date?.toIso(),
        '2026-09-25',
      );
    });

    test('"next Friday" is the following week, from any day of the week', () {
      expect(
        parser.parse('next friday', now: monday).date?.toIso(),
        '2026-10-02',
      );
      expect(
        parser.parse('next friday', now: friday).date?.toIso(),
        '2026-10-02',
      );
      expect(
        parser
            .parse(
              'next friday',
              now: LocalDateTime.parseIso('2026-09-27T10:00'),
            )
            .date
            ?.toIso(),
        '2026-10-02',
        reason: 'said on a Sunday, next Friday is still that same Friday',
      );
    });

    test('"last Friday" is strictly backward', () {
      expect(
        parser.parse('last friday', now: monday).date?.toIso(),
        '2026-09-18',
      );
      expect(
        parser.parse('last friday', now: friday).date?.toIso(),
        '2026-09-18',
      );
    });

    test(
      'three-letter abbreviations count when the context is date-shaped',
      () {
        expect(parser.parse('on mon', now: monday).date?.toIso(), '2026-09-28');
        expect(parser.parse('by fri', now: monday).date?.toIso(), '2026-09-25');
        expect(
          parser.parse('sat morning', now: monday).date?.toIso(),
          '2026-09-26',
        );
        expect(
          parser.parse('wed 23', now: monday).date?.toIso(),
          '2026-09-23',
          reason: 'a day number beside it is date-shaped context',
        );
      },
    );

    test('a weekday carries a part of the day with it', () {
      final ParsedWhen parsed = parser.parse('friday evening', now: monday);
      expect(parsed.date?.toIso(), '2026-09-25');
      expect(parsed.time?.minuteOfDay, ExtractionDefaults.eveningMinute);
    });

    test('a weekday and a clock time together', () {
      final ParsedWhen parsed = parser.parse('friday at 3pm', now: monday);
      expect(parsed.date?.toIso(), '2026-09-25');
      expect(parsed.time?.toIso(), '15:00');
      expect(parsed.confidence, Confidence.high);
    });

    test('the weekend is the coming Saturday, and is only a guess', () {
      final ParsedWhen parsed = parser.parse('this weekend', now: monday);
      expect(parsed.date?.toIso(), '2026-09-26');
      expect(parsed.confidence, Confidence.low);
      expect(
        parser.parse('next weekend', now: monday).date?.toIso(),
        '2026-10-03',
      );
      expect(
        parser
            .parse(
              'this weekend',
              now: LocalDateTime.parseIso('2026-09-26T11:00'),
            )
            .date
            ?.toIso(),
        '2026-09-26',
        reason: 'said on a Saturday, this weekend is the one you are in',
      );
    });
  });
}
