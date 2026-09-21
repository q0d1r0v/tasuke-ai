import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

/// The rule that decides whether a task lands today or tomorrow.
///
/// ⚠️ It is asymmetric on purpose, and the asymmetry is the product decision:
/// a bare time that has gone past is almost always tomorrow's, but a time said
/// *with* a date is a deliberately overdue task and moving it would be the app
/// arguing with the user.
void main() {
  const WhenParser parser = WhenParser();
  final LocalDateTime afternoon = LocalDateTime.parseIso('2026-09-21T16:30');

  group('rollover', () {
    test('the rule this file exists to pin', () {
      expect(ExtractionDefaults.bareTimeRollsToTomorrow, isTrue);
    });

    test('a bare time already past today is tomorrow', () {
      final ParsedWhen parsed = parser.parse('3 PM', now: afternoon);
      expect(parsed.date?.toIso(), '2026-09-22');
      expect(parsed.time?.toIso(), '15:00');
    });

    test('a bare time still to come today is today', () {
      final ParsedWhen parsed = parser.parse('6 PM', now: afternoon);
      expect(parsed.date?.toIso(), '2026-09-21');
      expect(parsed.time?.toIso(), '18:00');
    });

    test('the same minute as now is not past', () {
      expect(
        parser
            .parse('3 PM', now: LocalDateTime.parseIso('2026-09-21T15:00'))
            .date
            ?.toIso(),
        '2026-09-21',
      );
      expect(
        parser
            .parse('3 PM', now: LocalDateTime.parseIso('2026-09-21T15:01'))
            .date
            ?.toIso(),
        '2026-09-22',
        reason: 'one minute later it is',
      );
    });

    test('"today at 3 PM" at 4 PM stays today, and is overdue', () {
      final ParsedWhen parsed = parser.parse('today at 3 PM', now: afternoon);
      expect(parsed.date?.toIso(), '2026-09-21');
      expect(parsed.time?.toIso(), '15:00');
    });

    test('any explicit date suppresses the rollover', () {
      expect(
        parser.parse('monday at 9am', now: afternoon).date?.toIso(),
        '2026-09-28',
      );
      expect(
        parser.parse('sep 21 at 9am', now: afternoon).date?.toIso(),
        '2026-09-21',
      );
      expect(
        parser.parse('yesterday at 3pm', now: afternoon).date?.toIso(),
        '2026-09-20',
      );
      expect(
        parser.parse('the 21st at 9am', now: afternoon).date?.toIso(),
        '2026-09-21',
      );
    });

    test('a bare part of the day rolls by the same rule', () {
      expect(
        parser.parse('morning', now: afternoon).date?.toIso(),
        '2026-09-22',
      );
      expect(
        parser.parse('evening', now: afternoon).date?.toIso(),
        '2026-09-21',
      );
      expect(
        parser.parse('midnight', now: afternoon).date?.toIso(),
        '2026-09-22',
        reason: 'midnight is 00:00, which is behind every other hour',
      );
    });

    test('the rollover crosses a month and a year boundary', () {
      expect(
        parser
            .parse('9am', now: LocalDateTime.parseIso('2026-09-30T23:00'))
            .date
            ?.toIso(),
        '2026-10-01',
      );
      expect(
        parser
            .parse('9am', now: LocalDateTime.parseIso('2026-12-31T23:00'))
            .date
            ?.toIso(),
        '2027-01-01',
      );
    });
  });
}
