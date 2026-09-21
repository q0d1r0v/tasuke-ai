import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/title_cleaner.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

/// The half of the parser that matters most.
///
/// A missed date costs one tap on the Confirm screen. An invented one puts a
/// notification on the user's phone at a time they never asked for, and eats
/// the words it thought were a date out of the title on the way.
void main() {
  const WhenParser parser = WhenParser();
  const TitleCleaner cleaner = TitleCleaner();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');

  void expectNothing(String phrase) {
    final ParsedWhen parsed = parser.parse(phrase, now: now);
    expect(parsed.isEmpty, isTrue, reason: '"$phrase" must parse to nothing');
    expect(parsed.date, isNull, reason: phrase);
    expect(parsed.time, isNull, reason: phrase);
    expect(
      parsed.matchStart,
      parsed.matchEnd,
      reason: '"$phrase" must not claim any of the title',
    );
    expect(
      cleaner
          .clean(
            phrase,
            matchStart: parsed.matchStart,
            matchEnd: parsed.matchEnd,
            spans: parsed.spans,
          )
          .toLowerCase(),
      phrase.toLowerCase().replaceAll(RegExp(r'\.$'), ''),
      reason: '"$phrase" must survive the title cleaner whole',
    );
  }

  group('phrases that are not dates', () {
    test('the ones from the spec', () {
      for (final String phrase in <String>[
        'call Mark',
        'buy 3 apples',
        'version 2.1',
        'room 15',
        'send the 2026 report',
        'at the office',
        'march to the store',
        'may I call him',
        'sun is out',
        'I sat on the bench',
        'a quarter of the team',
      ]) {
        expectNothing(phrase);
      }
    });

    test('a month name used as an ordinary word', () {
      expectNothing('march to the store');
      expectNothing('we may go');
      expectNothing('august heat');
      expectNothing('mark the release as done');
    });

    test('a day abbreviation used as an ordinary word', () {
      expectNothing('sun is out');
      expectNothing('sat down and cried');
      expectNothing('I sat on the bench');
    });

    test('numbers that are not clocks', () {
      expectNothing('version 2.1');
      expectNothing('version 2.30');
      expectNothing('buy 5 to 10 apples');
      expectNothing('room 15');
      expectNothing('buy 3 apples');
      expectNothing('the 3rd edition');
    });

    test('a bare weekday word inside a longer word is not a weekday', () {
      expectNothing('buy a sunflower');
      expectNothing('call Markus');
      expectNothing('monitor the queue');
    });

    test(
      'an out-of-range clock or calendar value is nothing, never a guess',
      () {
        expectNothing('feb 30');
        expectNothing('2026-13-01');
        expectNothing('at 25');
        expectNothing('13pm');
      },
    );

    test('sentence-initial "Friday" IS a date when a verb follows it', () {
      // The other side of the guard: this must not be over-tightened into
      // rejecting the spec's own example.
      expect(
        parser.parse('Friday check App Store', now: now).date?.toIso(),
        '2026-09-25',
      );
      expect(
        parser.parse('Sat call the vet', now: now).date?.toIso(),
        '2026-09-26',
      );
    });
  });
}
