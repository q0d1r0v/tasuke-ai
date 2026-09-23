import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/clause_splitter.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/transcript_normaliser.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

/// The three ways whisper on the owner's phone (2026-09-23) broke the six
/// test sentences, each as the general rule that now reads it. The labelled
/// transcripts themselves are the 'device transcripts' quality corpus.
void main() {
  const TranscriptNormaliser normaliser = TranscriptNormaliser();
  const ClauseSplitter splitter = ClauseSplitter();
  const WhenParser parser = WhenParser();
  const RuleBasedTaskExtractor extractor = RuleBasedTaskExtractor();
  // When the owner recorded them: Wednesday 23 September 2026, 03:40.
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-23T03:40');

  Future<List<String>> cards(String note) async => <String>[
    for (final ExtractedTask t in await extractor.extract(note, now: now))
      '${t.title} | ${t.date?.toIso()} ${t.time?.toIso()}',
  ];

  group('the device failures', () {
    test('"cent the report" is "send the report", a task of its own', () async {
      expect(
        await cards(
          'Remind me in half an hour to take my medicine, then tonight at 10 '
          'cent the report to Amma.',
        ),
        <String>[
          'Take my medicine | 2026-09-23 04:10',
          'Send the report to Amma | 2026-09-23 22:00',
        ],
      );
    });

    test('a stop after "then tonight at 10" does not take the when back', () async {
      expect(
        await cards(
          'Remind me in half an hour to take my medicine, then tonight at 10. '
          'Send the report to Anna.',
        ),
        <String>[
          'Take my medicine | 2026-09-23 04:10',
          'Send the report to Anna | 2026-09-23 22:00',
        ],
      );
    });

    test(
      'no comma before "on October 5th pay…" still ends the dentist',
      () async {
        expect(
          await cards(
            'On Monday at 3 p.m. go to the dentist on October 5th pay the rent '
            'and buy milk.',
          ),
          <String>[
            'Go to the dentist | 2026-09-28 15:00',
            'Pay the rent | 2026-10-05 null',
            'Buy milk | 2026-10-05 null',
          ],
        );
      },
    );
  });

  group('"send" as whisper hears it where a task starts', () {
    test('"cent" and "scent" before the thing sent are "send"', () {
      expect(
        normaliser.normalise('Then tonight at 10 cent the report to Amma.'),
        'Then tonight at 10 send the report to Amma.',
      );
      expect(
        normaliser.normalise('Call Anna, then scent the photos to Timur.'),
        'Call Anna, then send the photos to Timur.',
      );
      expect(
        normaliser.normalise('Cent it to the printer tomorrow.'),
        'Send it to the printer tomorrow.',
      );
      expect(
        normaliser.normalise('Buy bread, then cent them the address.'),
        'Buy bread, then send them the address.',
      );
    });

    test('said as done, "cent" is "sent"', () {
      expect(
        normaliser.normalise('Yesterday cent the contract to the lawyer.'),
        'Yesterday sent the contract to the lawyer.',
      );
      expect(
        normaliser.normalise(
          'Sardor called and cent the photos, print them tomorrow.',
        ),
        'Sardor called and sent the photos, print them tomorrow.',
      );
    });

    test('a "cent" that is not where a task starts is kept', () {
      for (final String said in <String>[
        'It costs 50 cent the kilo, buy two kilos.',
        'Pay the fifty cent fee.',
        'Buy stamps, cent.',
      ]) {
        expect(normaliser.normalise(said), said, reason: said);
      }
    });

    test('"sent" is "send" where the past-tense rule already reads it', () {
      expect(
        normaliser.normalise(
          'Take my medicine, then tonight at 10 sent the report to Anna.',
          now: now,
        ),
        'Take my medicine, then tonight at 10 send the report to Anna.',
      );
      expect(
        normaliser.normalise('Sent the report to Anna yesterday.', now: now),
        'Sent the report to Anna yesterday.',
      );
    });
  });

  group('"then" and a when open the next task', () {
    test('whatever whisper made of the verb after the when', () {
      expect(
        splitter.splitClauses(
          'Call Anna, and then tomorrow at 9 fax the documents to Bob.',
        ),
        <String>['Call Anna', 'tomorrow at 9 fax the documents to Bob.'],
      );
      expect(
        splitter.splitClauses(
          'Clean the kitchen and then tonight relax a bit.',
        ),
        <String>['Clean the kitchen', 'tonight relax a bit.'],
      );
    });

    test('not before a subject, a name alone, an adverb or filler', () {
      for (final String said in <String>[
        'Call Anna and then tomorrow it rains.',
        'Call Anna then tomorrow Bob.',
        'Order the parts then next week hopefully the mechanic fixes it.',
        'Buy flowers then on Friday everything the same as last year.',
        'Go to the gym then in the evening just relax.',
        'Call Anna, then tonight at 10.',
      ]) {
        expect(splitter.splitClauses(said), hasLength(1), reason: said);
      }
    });
  });

  group('"…, then <when>." is the when of the sentence after it', () {
    test('when that sentence opens with its verb and has no when', () async {
      expect(
        await cards('Call Anna, then tomorrow at 9. Buy the train tickets.'),
        <String>[
          'Call Anna | null null',
          'Buy the train tickets | 2026-09-24 09:00',
        ],
      );
      expect(
        await cards(
          'Take the pills in 15 minutes, then at 9 in the evening. Um, send '
          'the photos to Anna.',
        ),
        <String>[
          'Take the pills | 2026-09-23 03:55',
          'Send the photos to Anna | 2026-09-23 21:00',
        ],
      );
    });

    test('not when it has a when of its own, or no verb first', () async {
      expect(await cards('Buy milk, then tomorrow. Call Anna at 5.'), <String>[
        'Buy milk | 2026-09-24 null',
        'Call Anna | 2026-09-24 17:00',
      ]);
      expect(
        await cards('Buy milk then tomorrow. I need to call Anna.'),
        <String>['Buy milk | 2026-09-24 null', 'Call Anna | null null'],
      );
      // No "then": the when is the task's before it, as ever.
      expect(await cards('Buy milk. Tomorrow.'), hasLength(1));
    });
  });

  group('"<task> on <date> <verb>…" said without its comma', () {
    test('is two tasks, the date the second one\'s', () async {
      expect(
        splitter.splitClauses(
          'Tomorrow at 9 call the insurance on the 30th renew the car '
          'registration.',
        ),
        <String>[
          'Tomorrow at 9 call the insurance',
          'on the 30th renew the car registration.',
        ],
      );
      expect(
        await cards(
          'On Wednesday take the car to the garage on Friday pick up the new '
          'tyres.',
        ),
        <String>[
          // Said on a Wednesday, a bare "Wednesday" is next week's.
          'Take the car to the garage | 2026-09-30 null',
          'Pick up the new tyres | 2026-09-25 null',
        ],
      );
    });

    test('but not without a verb straight after the date', () {
      for (final String said in <String>[
        'Meet Anna on Friday at the cafe.',
        'Book a table on Friday for dinner.',
        'Pay the rent on the 1st of every month.',
        'On Monday at 3 p.m. go to the dentist on October 5th at 10 pay the '
            'rent.',
      ]) {
        expect(splitter.splitClauses(said), hasLength(1), reason: said);
      }
    });

    test('nor after an errand handed over, nor before a day of its own', () {
      for (final String said in <String>[
        'Tell Anna on Friday bring the documents.',
        'Ask my brother on Saturday help with the move.',
        'Book the flight on Friday return on Sunday.',
      ]) {
        expect(splitter.splitClauses(said), hasLength(1), reason: said);
      }
    });
  });

  group('two whens in one clause', () {
    String said(String phrase) {
      final ParsedWhen when = parser.parse(phrase, now: now);
      return '${when.date?.toIso()} ${when.time?.toIso()} '
          '${phrase.substring(when.matchStart, when.matchEnd)}';
    }

    test('a clock said with a day of its own is not the first when\'s', () {
      // The root cause of the 10:00: "at 10" took the half hour's place and
      // was read as the half hour's hour, and "tonight" was never read.
      expect(
        said(
          'remind me in half an hour to take my medicine then tonight at 10',
        ),
        '2026-09-23 04:10 in half an hour',
      );
      expect(
        said('remind me in two hours to call Anna tomorrow at 9'),
        '2026-09-23 05:40 in two hours',
      );
      expect(said('Friday call Anna tonight at 8'), '2026-09-25 null Friday');
    });

    test('said of the same day, they are one moment', () {
      expect(
        said('today call Anna tonight at 8'),
        '2026-09-23 20:00 today call Anna tonight at 8',
      );
    });

    test('and the second when stays in the title, never dropped', () async {
      expect(
        await cards(
          'Remind me in half an hour to take my medicine then tonight at 10.',
        ),
        <String>['Take my medicine then tonight at 10 | 2026-09-23 04:10'],
      );
      expect(
        await cards('Today pay the electricity bill tonight at 9.'),
        <String>['Pay the electricity bill | 2026-09-23 21:00'],
      );
    });

    test('a clock said with the first when is still its own', () {
      expect(
        said('tomorrow at 9 call the bank about Friday'),
        '2026-09-24 09:00 tomorrow at 9',
      );
      expect(
        said('in two days at 5 call Anna'),
        '2026-09-25 17:00 in two days at 5',
      );
      expect(
        said('tonight call Anna at 8'),
        '2026-09-23 20:00 tonight call Anna at 8',
      );
    });
  });
}
