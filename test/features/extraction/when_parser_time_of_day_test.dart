import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/time_grammar.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

void main() {
  const WhenParser parser = WhenParser();
  // Early enough that none of the times below has gone past, so this file is
  // about the clock and never about the rollover.
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T00:05');

  String? timeOf(String phrase) => parser.parse(phrase, now: now).time?.toIso();

  group('times of day', () {
    test('the named times are the ones ExtractionDefaults declares', () {
      expect(
        TimeGrammar.dayPartMinute('morning'),
        ExtractionDefaults.morningMinute,
      );
      expect(
        TimeGrammar.dayPartMinute('afternoon'),
        ExtractionDefaults.afternoonMinute,
      );
      expect(
        TimeGrammar.dayPartMinute('evening'),
        ExtractionDefaults.eveningMinute,
      );
      expect(
        TimeGrammar.dayPartMinute('night'),
        ExtractionDefaults.nightMinute,
      );
      expect(TimeGrammar.dayPartMinute('noon'), ExtractionDefaults.noonMinute);
      expect(
        TimeGrammar.dayPartMinute('midnight'),
        ExtractionDefaults.midnightMinute,
      );
      expect(TimeGrammar.dayPartMinute('brunch'), isNull);
    });

    test('however the meridiem is written', () {
      expect(timeOf('3pm'), '15:00');
      expect(timeOf('3 pm'), '15:00');
      expect(timeOf('3 PM'), '15:00');
      expect(timeOf('3 p.m.'), '15:00');
      expect(timeOf('3P.M.'), '15:00');
      expect(timeOf('3:30pm'), '15:30');
      expect(timeOf('at 11:45 a.m.'), '11:45');
    });

    test('the two that everyone gets wrong', () {
      expect(timeOf('12am'), '00:00');
      expect(timeOf('12pm'), '12:00');
      expect(timeOf('12:30am'), '00:30');
    });

    test('24-hour clocks, with either separator', () {
      expect(timeOf('15:00'), '15:00');
      expect(timeOf('15.00'), '15:00');
      expect(timeOf('at 18:45'), '18:45');
      expect(timeOf('23:59'), '23:59');
    });

    test('an hour with no meridiem reads 1–6 as the afternoon', () {
      // "at 3" is three in the afternoon to everyone who has ever said it.
      expect(timeOf('at 3'), '15:00');
      expect(timeOf('at 5'), '17:00');
      expect(timeOf("at 3 o'clock"), '15:00');
      expect(
        timeOf('at 9'),
        '09:00',
        reason: 'but nine is nine in the morning',
      );
      expect(timeOf('at 11'), '11:00');
      expect(timeOf('at 15'), '15:00', reason: 'and 15 is already 24-hour');
      expect(
        timeOf('03:30'),
        '03:30',
        reason: 'a leading zero says the speaker meant the 24-hour clock',
      );
    });

    test('a part of the day spells out which hour was meant', () {
      expect(timeOf('at 3 in the afternoon'), '15:00');
      expect(timeOf('8 in the morning'), '08:00');
      expect(timeOf('9:30 in the evening'), '21:30');
      expect(timeOf('12 in the morning'), '00:00');
      expect(timeOf('12 in the afternoon'), '12:00');
    });

    test('times said as words', () {
      expect(timeOf('quarter past three'), '15:15');
      expect(timeOf('half past three'), '15:30');
      expect(timeOf('quarter to four'), '15:45');
      expect(timeOf('a quarter past nine'), '09:15');
      expect(timeOf('ten past nine'), '09:10');
      expect(timeOf('twenty to five'), '16:40');
      expect(timeOf('half past seven in the morning'), '07:30');
      expect(timeOf('quarter past 3 pm'), '15:15');
      expect(
        timeOf('ten to midnight'),
        '23:50',
        reason: 'ten minutes before midnight is the evening before',
      );
    });

    test('noon, midday and midnight', () {
      expect(timeOf('noon'), '12:00');
      expect(timeOf('at midday'), '12:00');
      expect(timeOf('midnight'), '00:00');
    });

    test('a bare part of the day', () {
      expect(timeOf('morning'), '09:00');
      expect(timeOf('in the afternoon'), '14:00');
      expect(timeOf('this evening'), '18:00');
      expect(timeOf('night'), '20:00');
    });

    test('an impossible clock time is no time at all', () {
      for (final String phrase in <String>[
        'at 25',
        '13pm',
        '0pm',
        '25:00',
        '15:61',
      ]) {
        expect(parser.parse(phrase, now: now).time, isNull, reason: phrase);
      }
    });

    test('the longer reading wins when two start at the same word', () {
      // "at 3" and "at 3 in the afternoon" both begin at the same character.
      final ParsedWhen parsed = parser.parse('at 3 in the afternoon', now: now);
      expect(parsed.time?.toIso(), '15:00');
      expect(parsed.matchEnd, 'at 3 in the afternoon'.length);
    });
  });
}
