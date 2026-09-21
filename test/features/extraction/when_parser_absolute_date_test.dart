import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
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
