import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';

/// Split, parse, clean, build — the whole pipeline with no model in it.
void main() {
  const TaskExtractor extractor = RuleBasedTaskExtractor();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');

  test('it is always ready, because there is nothing to load', () async {
    expect(await extractor.isReady(), isTrue);
  });

  test('the spec utterance, end to end', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      'Tomorrow at 3 PM send the build to James and Friday check App Store',
      now: now,
    );
    expect(tasks, hasLength(2));

    expect(tasks[0].title, 'Send the build to James');
    expect(tasks[0].date?.toIso(), '2026-09-22');
    expect(tasks[0].time?.toIso(), '15:00');
    expect(tasks[0].hasReminder, isTrue, reason: 'a spoken time wants telling');
    expect(tasks[0].whenText, 'Tomorrow at 3 PM');
    expect(tasks[0].confidence, Confidence.high);

    expect(tasks[1].title, 'Check App Store');
    expect(tasks[1].date?.toIso(), '2026-09-25');
    expect(tasks[1].time, isNull);
    expect(tasks[1].hasReminder, isFalse, reason: 'a bare date does not');
    expect(tasks[1].whenText, 'Friday');
  });

  test('one task, no date', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      'call Mark',
      now: now,
    );
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Call Mark');
    expect(tasks.single.date, isNull);
    expect(tasks.single.time, isNull);
    expect(tasks.single.whenText, isNull);
    expect(tasks.single.hasReminder, isFalse);
  });

  test('fillers come off the front', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      "remind me to pay the rent on friday, and don't forget to call the vet",
      now: now,
    );
    expect(tasks.map((ExtractedTask t) => t.title), <String>[
      'Pay the rent',
      'Call the vet',
    ]);
    expect(tasks[0].date?.toIso(), '2026-09-25');
    expect(
      tasks[0].hasReminder,
      isTrue,
      reason: '"remind me" asks for one outright, with no time given',
    );
  });

  test('a conjoined object stays one task', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      'send the build and the release notes to James tomorrow',
      now: now,
    );
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Send the build and the release notes to James');
    expect(tasks.single.date?.toIso(), '2026-09-22');
  });

  test('an utterance with nothing in it produces nothing', () async {
    expect(await extractor.extract('', now: now), isEmpty);
    expect(await extractor.extract('   \n ', now: now), isEmpty);
  });

  test('a clause that is only a date keeps the words as its title', () async {
    // Better a task called "Tomorrow at 3 PM" that the user renames than a
    // capture that silently produced nothing.
    final List<ExtractedTask> tasks = await extractor.extract(
      'tomorrow at 3 PM',
      now: now,
    );
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Tomorrow at 3 PM');
    expect(tasks.single.date?.toIso(), '2026-09-22');
    expect(tasks.single.time?.toIso(), '15:00');
  });

  test('a long list of clauses is capped', () async {
    final String utterance = List<String>.generate(
      ExtractionDefaults.maxTasksPerCapture + 10,
      (int i) => 'call person$i',
    ).join(' and ');
    final List<ExtractedTask> tasks = await extractor.extract(
      utterance,
      now: now,
    );
    expect(tasks, hasLength(ExtractionDefaults.maxTasksPerCapture));
  });

  test('titles are clamped to what the database will take', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      'call Mark about ${'the quarterly numbers ' * 40}',
      now: now,
    );
    expect(tasks.single.title.length, lessThanOrEqualTo(200));
  });

  test('the same utterance twice gives the same answer', () async {
    const String utterance =
        'buy milk tomorrow morning and call the dentist on the 5th';
    final List<ExtractedTask> first = await extractor.extract(
      utterance,
      now: now,
    );
    final List<ExtractedTask> second = await extractor.extract(
      utterance,
      now: now,
    );
    expect(first, second);
  });

  test('a vague date is flagged for the Confirm card', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      'review the roadmap next week',
      now: now,
    );
    expect(tasks.single.title, 'Review the roadmap');
    expect(tasks.single.date?.toIso(), '2026-09-28');
    expect(tasks.single.confidence, Confidence.low);
  });

  test('three tasks, three different ways of saying when', () async {
    final List<ExtractedTask> tasks = await extractor.extract(
      'pay the electricity bill on the 5th, then book the flights for '
      'next month and water the plants this evening',
      now: now,
    );
    expect(tasks, hasLength(3));
    expect(tasks[0].title, 'Pay the electricity bill');
    expect(tasks[0].date?.toIso(), '2026-10-05');
    expect(tasks[1].title, 'Book the flights');
    expect(tasks[1].date?.toIso(), '2026-10-01');
    expect(tasks[1].confidence, Confidence.low);
    expect(tasks[2].title, 'Water the plants');
    expect(tasks[2].date?.toIso(), '2026-09-21');
    expect(tasks[2].time?.toIso(), '18:00');
  });

  test('the whole when comes out of the title, not just its start', () async {
    // Each of these once left a piece of its date or time in the title, and
    // most of them the wrong date or time as well.
    for (final (String utterance, String title, String? date, String? time)
        in <(String, String, String?, String?)>[
          (
            'Pay the rent on the 5th of December.',
            'Pay the rent',
            '2026-12-05',
            null,
          ),
          (
            'Pay the rent on the fifth of December.',
            'Pay the rent',
            '2026-12-05',
            null,
          ),
          (
            'Book flights for the 12th of January 2027.',
            'Book flights',
            '2027-01-12',
            null,
          ),
          (
            'Dentist appointment on Thursday, October 15th at 10 am.',
            'Dentist appointment',
            '2026-10-15',
            '10:00',
          ),
          ('On the 1st of October pay rent.', 'Pay rent', '2026-10-01', null),
          (
            'Call the plumber in an hour and a half.',
            'Call the plumber',
            '2026-09-21',
            '11:30',
          ),
          (
            'Remind me in half an hour to call mom.',
            'Call mom',
            '2026-09-21',
            '10:30',
          ),
          (
            'Call Anna tomorrow at 12 midnight.',
            'Call Anna',
            '2026-09-22',
            '00:00',
          ),
          ('Call Anna at 12 noon.', 'Call Anna', '2026-09-21', '12:00'),
          ('Call Anna at twelve midnight.', 'Call Anna', '2026-09-22', '00:00'),
          ('Call Anna in a half-hour.', 'Call Anna', '2026-09-21', '10:30'),
          ('Call Anna in 2.25 hours.', 'Call Anna', '2026-09-21', '12:15'),
          (
            'Pay rent by 12 midnight tomorrow.',
            'Pay rent',
            '2026-09-22',
            '00:00',
          ),
        ]) {
      final List<ExtractedTask> tasks = await extractor.extract(
        utterance,
        now: now,
      );
      expect(tasks, hasLength(1), reason: utterance);
      expect(tasks.single.title, title, reason: utterance);
      expect(tasks.single.date?.toIso(), date, reason: utterance);
      expect(tasks.single.time?.toIso(), time, reason: utterance);
    }
  });

  test('a time under a "tonight" heading is that night\'s', () async {
    // ⚠️ The heading's evening made every bare hour the afternoon one: "at
    // midnight" was noon, and "at 2" 14:00 instead of 02:00.
    for (final (String at, String utterance, String expected)
        in <(String, String, String)>[
          (
            '2026-09-21T10:00',
            'Tonight I have one thing. Call Anna at midnight.',
            '2026-09-22 00:00',
          ),
          (
            '2026-09-21T10:00',
            'This evening I have one thing. Call Anna at midnight.',
            '2026-09-22 00:00',
          ),
          (
            '2026-09-21T10:00',
            'Tonight I have one thing. Take the pills at 2.',
            '2026-09-22 02:00',
          ),
          // Said at 00:40, tonight is the night already under way.
          (
            '2026-09-24T00:40',
            'Tonight I have one thing. Take the pills at 2.',
            '2026-09-24 02:00',
          ),
          // Unchanged: an evening hour, and a small hour on another day.
          (
            '2026-09-21T10:00',
            'Tonight I have one thing. Call Anna at 9.',
            '2026-09-21 21:00',
          ),
          (
            '2026-09-21T10:00',
            'Tonight I have things. Tomorrow call Anna at 9. Then at 2 take '
                'the pills.',
            '2026-09-22 14:00',
          ),
        ]) {
      final List<ExtractedTask> tasks = await extractor.extract(
        utterance,
        now: LocalDateTime.parseIso(at),
      );
      final ExtractedTask last = tasks.last;
      expect(
        '${last.date?.toIso()} ${last.time?.toIso()}',
        expected,
        reason: '$utterance at $at',
      );
    }
  });

  group('found by the adversarial review', () {
    // A Wednesday afternoon: 5 October is a Monday, 1 October a Thursday.
    final LocalDateTime wednesday = LocalDateTime.parseIso('2026-09-23T15:00');

    test('one card per utterance, with the whole when cut from its title', () async {
      for (final (String utterance, String title, String expected)
          in <(String, String, String)>[
            // A weekday with a day of the month was the coming weekday.
            (
              'Call the plumber on Monday the 5th at 9.',
              'Call the plumber',
              '2026-10-05 09:00',
            ),
            ('Pay rent Thursday the 1st.', 'Pay rent', '2026-10-01 null'),
            ('Meeting on Monday, October fifth.', 'Meeting', '2026-10-05 null'),
            (
              'Pay rent on Thursday, October the 1st.',
              'Pay rent',
              '2026-10-01 null',
            ),
            // "X to H" under a tonight heading was built from H: an hour late,
            // and "a quarter to twelve" moved past midnight.
            (
              'Tonight I have one thing. Call Anna at a quarter to twelve.',
              'Call Anna',
              '2026-09-23 23:45',
            ),
            (
              'Tonight I have one thing. Take the pills at ten to one.',
              'Take the pills',
              '2026-09-24 00:50',
            ),
            // …and a time already in the small hours turned 15:00 today.
            (
              'Tonight I have one thing. Take the pills at 3 in the morning.',
              'Take the pills',
              '2026-09-24 03:00',
            ),
            (
              'Tonight I have one thing. Take the pills at ten to one in the '
                  'morning.',
              'Take the pills',
              '2026-09-24 00:50',
            ),
            // "the second I land" is the moment, not the 2nd of a month.
            (
              'Text Anna on Monday the second I land.',
              'Text Anna the second I land',
              '2026-09-28 null',
            ),
            // A weekday's part of the day before the comma split the date in
            // two: a card for the weekday and a junk card for the date.
            (
              'Dentist appointment on Thursday morning, October 15th at 10.',
              'Dentist appointment',
              '2026-10-15 10:00',
            ),
            (
              'Dinner with Anna Saturday evening, October 3rd at 8.',
              'Dinner with Anna',
              '2026-10-03 20:00',
            ),
            // "'s time" was left in the title.
            (
              "Call Anna in half an hour's time.",
              'Call Anna',
              '2026-09-23 15:30',
            ),
            ("Call Anna in an hour's time.", 'Call Anna', '2026-09-23 16:00'),
            ("Call Anna in two hours' time.", 'Call Anna', '2026-09-23 17:00'),
            ('Call Anna in two hours time.', 'Call Anna', '2026-09-23 17:00'),
          ]) {
        final List<ExtractedTask> tasks = await extractor.extract(
          utterance,
          now: wednesday,
        );
        expect(tasks, hasLength(1), reason: utterance);
        expect(tasks.single.title, title, reason: utterance);
        expect(
          '${tasks.single.date?.toIso()} ${tasks.single.time?.toIso()}',
          expected,
          reason: utterance,
        );
        expect(tasks.single.confidence, Confidence.high, reason: utterance);
      }
    });

    test('a part of the day with no date after it still ends a task', () async {
      final List<ExtractedTask> tasks = await extractor.extract(
        'Pick up Max in the morning, Anna at 3.',
        now: wednesday,
      );
      expect(tasks.map((ExtractedTask t) => t.title), <String>[
        'Pick up Max',
        'Anna',
      ]);
      expect(tasks.last.time?.toIso(), '15:00');
    });
  });

  group('complex spoken notes', () {
    // A Wednesday afternoon: "Friday" is the 25th, "next Tuesday" the 29th.
    final LocalDateTime wednesday = LocalDateTime.parseIso('2026-09-23T15:00');

    Future<List<(String, String?, String?)>> run(
      String note, {
      LocalDateTime? at,
    }) async => <(String, String?, String?)>[
      for (final ExtractedTask t in await extractor.extract(
        note,
        now: at ?? wednesday,
      ))
        (t.title, t.date?.toIso(), t.time?.toIso()),
    ];

    test('a when that names no connective still starts a task', () async {
      final LocalDateTime early = LocalDateTime.parseIso('2026-09-23T03:40');
      final List<(String, String?, String?)> three = await run(
        'On Monday at 3 PM go to the dentist, on October 5th pay the rent, '
        'and buy milk.',
        at: early,
      );
      expect(three.map(((String, String?, String?) t) => t.$1), <String>[
        'Go to the dentist',
        'Pay the rent',
        'Buy milk',
      ]);
      expect(three[0], ('Go to the dentist', '2026-09-28', '15:00'));
      expect(three[1], ('Pay the rent', '2026-10-05', null));
      // The milk's day is left open on purpose: the corpora carry a day said
      // first to the rest of its sentence, and nobody labelled this shape.
      // ⚠️ The "and" inside "an hour and a half" joins nothing.
      expect(
        await run(
          'In two hours call mom, and the day after tomorrow at 7:30 in the '
          'morning go to the gym.',
          at: early,
        ),
        <(String, String?, String?)>[
          ('Call mom', '2026-09-23', '05:40'),
          ('Go to the gym', '2026-09-25', '07:30'),
        ],
      );
      expect(
        await run('Next week on Tuesday at noon lunch with Sardor', at: early),
        <(String, String?, String?)>[
          ('Lunch with Sardor', '2026-09-29', '12:00'),
        ],
      );
      expect(
        await run(
          'Remind me in 45 minutes to take the laundry out, and in an hour '
          'and a half pick up Madina.',
        ),
        <(String, String?, String?)>[
          ('Take the laundry out', '2026-09-23', '15:45'),
          ('Pick up Madina', '2026-09-23', '16:30'),
        ],
      );
    });

    test('a day said first covers the rest of its sentence', () async {
      expect(
        await run(
          'Tomorrow buy a charger and call Umid, oh and on Saturday take the '
          'kids to the zoo.',
        ),
        <(String, String?, String?)>[
          ('Buy a charger', '2026-09-24', null),
          ('Call Umid', '2026-09-24', null),
          ('Take the kids to the zoo', '2026-09-26', null),
        ],
      );
      // A day said last is the day of the "and" after it too — the day, not
      // the hour — but not past the end of the sentence.
      expect(
        await run('Call mom tonight and pay the electricity bill.'),
        <(String, String?, String?)>[
          ('Call mom', '2026-09-23', '20:00'),
          ('Pay the electricity bill', '2026-09-23', null),
        ],
      );
      expect(
        await run('Today buy milk. Call Anna.'),
        <(String, String?, String?)>[
          ('Buy milk', '2026-09-23', null),
          ('Call Anna', null, null),
        ],
      );
      // "at some point" says there is no day, out loud.
      expect(
        await run(
          'Today pay for the internet, and at some point call Dildora back.',
        ),
        <(String, String?, String?)>[
          ('Pay for the internet', '2026-09-23', null),
          ('Call Dildora back', null, null),
        ],
      );
    });

    test('"both on Friday" is for every task of its sentence', () async {
      expect(
        await run('Call the vet and book a grooming slot, both on Friday.'),
        <(String, String?, String?)>[
          ('Call the vet', '2026-09-25', null),
          ('Book a grooming slot', '2026-09-25', null),
        ],
      );
      expect(
        await run('Buy milk and call them all on Friday.'),
        <(String, String?, String?)>[
          ('Buy milk', null, null),
          ('Call them all', '2026-09-25', null),
        ],
        reason: 'a bare "all" belongs to the object',
      );
    });

    test('the speaker correcting themselves', () async {
      expect(
        await run(
          'Call Sardor at 4, no wait, at 4.30. And send him the photos.',
        ),
        <(String, String?, String?)>[
          ('Call Sardor', '2026-09-23', '16:30'),
          ('Send him the photos', null, null),
        ],
      );
      expect(
        await run(
          'Take the lagman out of the freezer. Uh, no, not lagman, the manti.',
        ),
        <(String, String?, String?)>[
          ('Take the manti out of the freezer', null, null),
        ],
      );
      expect(
        await run('Meet at 5, no later than 6.'),
        hasLength(1),
        reason: '"no later than" takes nothing back',
      );
    });

    test("someone else's plans frame the task, or explain it", () async {
      expect(
        await run(
          'My sister is coming from Moscow on the 28th, I need to pick her up '
          'from the airport at 11 at night.',
        ),
        <(String, String?, String?)>[
          ('Pick her up from the airport', '2026-09-28', '23:00'),
        ],
      );
      expect(
        await run(
          'Cook dinner before 6, my husband is coming home early today.',
        ),
        <(String, String?, String?)>[('Cook dinner', '2026-09-23', '18:00')],
      );
      expect(
        await run(
          'Sardor called, he said the meeting is moved to Friday. So Friday at '
          '4 meeting with Sardor.',
        ),
        <(String, String?, String?)>[
          ('Meeting with Sardor', '2026-09-25', '16:00'),
        ],
      );
    });

    test('one task said twice, and two tasks counted out', () async {
      expect(
        await run('On Monday I have to, uh, update my CV and print it.'),
        <(String, String?, String?)>[
          ('Update my CV and print it', '2026-09-28', null),
        ],
      );
      expect(
        await run('Madina asked me to print her homework, do it tonight.'),
        <(String, String?, String?)>[
          ('Print her homework', '2026-09-23', '20:00'),
        ],
      );
      expect(
        (await run('First, finish the deck, second, print it.'))
            .map(((String, String?, String?) t) => t.$1),
        <String>['Finish the deck', 'Print it'],
      );
    });

    test('a verb said once and meant for a list', () async {
      expect(
        await run('On the 1st pay the mortgage, on the 2nd the gas bill.'),
        <(String, String?, String?)>[
          ('Pay the mortgage', '2026-10-01', null),
          ('Pay the gas bill', '2026-10-02', null),
        ],
      );
      expect(
        (await run('Tomorrow buy milk, in the evening the laundry.'))
            .map(((String, String?, String?) t) => t.$1),
        isNot(contains('Buy the laundry')),
        reason: 'only between two whens of the same shape',
      );
    });

    test('the time of the task just said', () async {
      expect(
        await run(
          'The day after tomorrow I am flying to Seoul, the flight is at 6 in '
          'the morning.',
        ),
        <(String, String?, String?)>[('Fly to Seoul', '2026-09-25', '06:00')],
      );
    });

    test('remind me to …, to …, and to …', () async {
      expect(
        await run(
          'Remind me to call Nargiza at 4, to order the cake on Monday, and to '
          'buy balloons.',
        ),
        <(String, String?, String?)>[
          ('Call Nargiza', '2026-09-23', '16:00'),
          ('Order the cake', '2026-09-28', null),
          ('Buy balloons', null, null),
        ],
      );
    });

    test(
      'talk that is not a task, even with a day or an event in it',
      () async {
        for (final String note in <String>[
          'Oh no, I forgot what I wanted to say. Um, wait. No, nothing, sorry.',
          'Um, is this thing on? My brother said this app is very good, so '
              "I'm just trying it. Okay, bye.",
          'Ooh, today was crazy at work, the boss was angry at everybody.',
          "So I'm at the gym now, it's very crowded today.",
          'So today is my father\'s birthday actually.',
          'My phone is almost dead.',
        ]) {
          expect(await run(note), isEmpty, reason: note);
        }
      },
    );

    group('found by the second adversarial review', () {
      test("somebody else's appointment stays an event before a task with a "
          'day of its own', () async {
        // ⚠️ Framed, the electrician was lost and his 10:00 went to Anna.
        expect(
          await run(
            'The electrician is coming tomorrow at 10, so today buy the '
            'cable and call Anna.',
          ),
          <(String, String?, String?)>[
            ('The electrician is coming', '2026-09-24', '10:00'),
            ('Buy the cable', '2026-09-23', null),
            ('Call Anna', '2026-09-23', null),
          ],
        );
        expect(
          await run(
            'The plumber is coming on Friday at 2 p.m. to fix the heater, '
            'and on Monday I have a doctor appointment.',
          ),
          <(String, String?, String?)>[
            ('The plumber is coming to fix the heater', '2026-09-25', '14:00'),
            ('Doctor appointment', '2026-09-28', null),
          ],
        );
        // Its day said again, it still frames: the pickup is at 5.
        expect(
          await run(
            'My sister is coming tomorrow at 5, tomorrow pick her up from '
            'the station.',
          ),
          <(String, String?, String?)>[
            ('Pick her up from the station', '2026-09-24', '17:00'),
          ],
        );
        // A plan with only a day is the reason, not an appointment.
        expect(
          await run('My parents are coming on Saturday, clean the house.'),
          <(String, String?, String?)>[('Clean the house', '2026-09-26', null)],
        );
      });

      test("somebody else's time after a task is that task's", () async {
        expect(
          await run(
            'Tomorrow go to the bank, the manager is waiting at 11 a.m.',
          ),
          <(String, String?, String?)>[
            ('Go to the bank', '2026-09-24', '11:00'),
          ],
        );
        expect(
          await run('Cook dinner, my husband is coming home at 7.'),
          <(String, String?, String?)>[('Cook dinner', null, null)],
          reason: 'no day to put it on: a bare 7 alone is 07:00 tomorrow',
        );
      });

      test('"my X is at T" is the time of the task only if X is it', () async {
        expect(
          await run('Tomorrow iron my shirt, my interview is at 10 a.m.'),
          <(String, String?, String?)>[
            ('Iron my shirt', '2026-09-24', null),
            ('My interview', '2026-09-24', '10:00'),
          ],
        );
        expect(
          await run('Tomorrow buy flowers for Aziza, her party is at 7 p.m.'),
          <(String, String?, String?)>[
            ('Buy flowers for Aziza', '2026-09-24', null),
            ('Her party', '2026-09-24', '19:00'),
          ],
        );
        expect(
          await run('Tomorrow go to the dentist, the appointment is at 10.'),
          <(String, String?, String?)>[
            ('Go to the dentist', '2026-09-24', '10:00'),
          ],
        );
      });

      test('"called" after a task verb names its object', () async {
        for (final String note in <String>[
          "Install app called Payme on mom's phone.",
          'Read book called Atomic Habits this weekend.',
          'Watch film called Dune tonight.',
          'Download app called Click.',
        ]) {
          expect(await run(note), hasLength(1), reason: note);
        }
      });

      test('"today is the last day to pay…" is the paying, today', () async {
        expect(
          await run('Today is the last day to pay the parking fine.'),
          <(String, String?, String?)>[
            ('Pay the parking fine', '2026-09-23', null),
          ],
        );
      });

      test('"listen" is a verb before "to", filler elsewhere', () async {
        expect(
          await run('Listen to the podcast tonight.'),
          <(String, String?, String?)>[
            ('Listen to the podcast', '2026-09-23', '20:00'),
          ],
        );
        expect(
          await run(
            'Uh, listen, the internet is not working again, so call the '
            'provider tomorrow morning.',
          ),
          <(String, String?, String?)>[
            ('Call the provider', '2026-09-24', '09:00'),
          ],
        );
      });

      test('the same day said twice is not a list to gap', () async {
        expect(
          await run('Tomorrow buy milk, tomorrow evening the laundry.'),
          <(String, String?, String?)>[
            ('Buy milk', '2026-09-24', null),
            ('The laundry', '2026-09-24', '18:00'),
          ],
        );
        expect(
          (await run('Tomorrow buy milk, tomorrow at 6 Anna.'))
              .map(((String, String?, String?) t) => t.$1),
          <String>['Buy milk', 'Anna'],
        );
      });

      test('a when alone before a comma is for the task after it', () async {
        for (final String note in <String>[
          'Tomorrow afternoon take the results to the doctor, and on Friday '
              'afternoon, pick up her glasses.',
          'Tomorrow afternoon take the results to the doctor, and on Thursday '
              'afternoon, no, Friday afternoon, pick up her glasses.',
        ]) {
          expect(await run(note), <(String, String?, String?)>[
            ('Take the results to the doctor', '2026-09-24', '14:00'),
            ('Pick up her glasses', '2026-09-25', '14:00'),
          ], reason: note);
        }
      });

      test('titles without what was said around the task', () async {
        expect(
          await run(
            'My god, I totally forgot, the car insurance ends on Monday.',
          ),
          <(String, String?, String?)>[
            ('The car insurance ends', '2026-09-28', null),
          ],
        );
        expect(
          await run(
            'The bank called and said I need to bring my passport on Friday.',
          ),
          <(String, String?, String?)>[
            ('Bring my passport', '2026-09-25', null),
          ],
        );
        expect(
          await run(
            'Tomorrow call the accountant, and before noon send the invoice '
            'to Sherzod aka.',
          ),
          <(String, String?, String?)>[
            ('Call the accountant', '2026-09-24', null),
            ('Send the invoice to Sherzod aka', '2026-09-24', '12:00'),
          ],
        );
        expect(
          await run('My mom called and asked me to buy bread.'),
          <(String, String?, String?)>[('Buy bread', null, null)],
        );
      });

      test('"wake up" is a task of its own', () async {
        expect(
          await run(
            'Tonight at 11 take the pills, and at 7 in the morning wake up '
            'Otabek for school.',
          ),
          <(String, String?, String?)>[
            ('Take the pills', '2026-09-23', '23:00'),
            ('Wake up Otabek for school', '2026-09-24', '07:00'),
          ],
        );
      });
    });

    test('an aside after a comma is not part of the title', () async {
      expect(
        await run(
          'Tonight at 1 call my brother in New York, it\'s his birthday.',
        ),
        <(String, String?, String?)>[
          ('Call my brother in New York', '2026-09-24', '01:00'),
        ],
      );
      expect(
        await run('Send the build, the release notes and the slides to James.'),
        hasLength(1),
        reason: 'an object list is not an aside',
      );
    });
  });

  group('found by the generalisation and robustness reviews', () {
    // The reviewers' own moments: a Wednesday afternoon for the speech of
    // people learning English, a Wednesday and a Monday morning for the rest.
    final LocalDateTime wednesday = LocalDateTime.parseIso('2026-09-23T15:00');
    final LocalDateTime wednesdayMorning = LocalDateTime.parseIso(
      '2026-09-23T10:00',
    );
    final LocalDateTime monday = LocalDateTime.parseIso('2026-09-21T10:00');

    Future<List<(String, String?, String?)>> run(
      String note, {
      required LocalDateTime at,
    }) async => <(String, String?, String?)>[
      for (final ExtractedTask t in await extractor.extract(note, now: at))
        (t.title, t.date?.toIso(), t.time?.toIso()),
    ];

    Future<void> expectAll(
      LocalDateTime at,
      Map<String, List<(String, String?, String?)>> cases,
    ) async {
      for (final MapEntry<String, List<(String, String?, String?)>> c
          in cases.entries) {
        expect(await run(c.key, at: at), c.value, reason: c.key);
      }
    }

    test('"eh", "ee", "mm" and a comma-set "like" are not cards', () async {
      await expectAll(wednesday, <String, List<(String, String?, String?)>>{
        'Eh, call Anna at 5.': <(String, String?, String?)>[
          ('Call Anna', '2026-09-23', '17:00'),
        ],
        'Ehh, so, pay the phone bill tomorrow.': <(String, String?, String?)>[
          ('Pay the phone bill', '2026-09-24', null),
        ],
        'Eh, what else... oh yes, Friday, uh, sorry, Saturday, meet with '
            'Jamshid for coffee at 3.': <(String, String?, String?)>[
          ('Meet with Jamshid for coffee', '2026-09-26', '15:00'),
        ],
        'I have to, like, buy milk tomorrow.': <(String, String?, String?)>[
          ('Buy milk', '2026-09-24', null),
        ],
        'I need to, like, call mom tonight.': <(String, String?, String?)>[
          ('Call mom', '2026-09-23', '20:00'),
        ],
        'Like, buy eggs at 6.': <(String, String?, String?)>[
          ('Buy eggs', '2026-09-23', '18:00'),
        ],
        'Ee, call Anna at 5.': <(String, String?, String?)>[
          ('Call Anna', '2026-09-23', '17:00'),
        ],
        'Mm, call Anna at 5.': <(String, String?, String?)>[
          ('Call Anna', '2026-09-23', '17:00'),
        ],
        'Eh call Anna at 5.': <(String, String?, String?)>[
          ('Call Anna', '2026-09-23', '17:00'),
        ],
        'So, like, call the dentist tomorrow.': <(String, String?, String?)>[
          ('Call the dentist', '2026-09-24', null),
        ],
        // "like" that is not set off is the task.
        "I'd like to buy milk tomorrow.": <(String, String?, String?)>[
          ('Buy milk', '2026-09-24', null),
        ],
        'Buy a dress like this for the party.': <(String, String?, String?)>[
          ('Buy a dress like this for the party', null, null),
        ],
      });
    });

    test('filler, a stutter and a hedge leave the middle of a title', () async {
      await expectAll(wednesday, <String, List<(String, String?, String?)>>{
        'Um, so, uh, I have to, like, call the plumber, uh, tomorrow at, at '
            '10 about the leak.': <(String, String?, String?)>[
          ('Call the plumber about the leak', '2026-09-24', '10:00'),
        ],
        'Call Anna at, at 5 about the tickets.': <(String, String?, String?)>[
          ('Call Anna about the tickets', '2026-09-23', '17:00'),
        ],
        'Call the plumber, uh, about the leak tomorrow.':
            <(String, String?, String?)>[
              ('Call the plumber about the leak', '2026-09-24', null),
            ],
        'Call, like, the bank at 5.': <(String, String?, String?)>[
          ('Call the bank', '2026-09-23', '17:00'),
        ],
        'Call the dentist, um, tomorrow at 3.': <(String, String?, String?)>[
          ('Call the dentist', '2026-09-24', '15:00'),
        ],
        'Email, uh, John about the report.': <(String, String?, String?)>[
          ('Email John about the report', null, null),
        ],
        'Change the oil on Saturday maybe.': <(String, String?, String?)>[
          ('Change the oil', '2026-09-26', null),
        ],
        'Maybe change the oil on Saturday.': <(String, String?, String?)>[
          ('Change the oil', '2026-09-26', null),
        ],
        'Uh, testing. Okay. Buy cat food, the one with the fish, you know, '
            'the blue package.': <(String, String?, String?)>[
          ('Buy cat food', null, null),
        ],
        // Between two items the filler goes and the list comma stays.
        'Buy milk, uh, eggs, and bread.': <(String, String?, String?)>[
          ('Buy milk, eggs and bread', null, null),
        ],
      });
    });

    test('the thing said first is what "it" and "them" stand for', () async {
      await expectAll(wednesday, <String, List<(String, String?, String?)>>{
        'The car, I need to wash it on Sunday.': <(String, String?, String?)>[
          ('Wash the car', '2026-09-27', null),
        ],
        'My passport, I have to renew it next week.':
            <(String, String?, String?)>[
              ('Renew my passport', '2026-09-28', null),
            ],
        'The rent, pay it on Friday.': <(String, String?, String?)>[
          ('Pay the rent', '2026-09-25', null),
        ],
        'The documents, send them to Aziz tomorrow.':
            <(String, String?, String?)>[
              ('Send the documents to Aziz', '2026-09-24', null),
            ],
        'The car. I need to wash it on Sunday.': <(String, String?, String?)>[
          ('Wash the car', '2026-09-27', null),
        ],
        'Milk, eggs, bread, buy them tomorrow.': <(String, String?, String?)>[
          ('Buy milk, eggs, bread', '2026-09-24', null),
        ],
        'Mom, call her tomorrow.': <(String, String?, String?)>[
          ('Call Mom', '2026-09-24', null),
        ],
        'The tickets, I need to buy them and send them to Aziz.':
            <(String, String?, String?)>[
              ('Buy the tickets', null, null),
              ('Send the tickets to Aziz', null, null),
            ],
        'So the passport, I have to renew it, and the visa, I need to apply '
            'for it.': <(String, String?, String?)>[
          ('Renew the passport', null, null),
          ('Apply for the visa', null, null),
        ],
        // With no pronoun the thing stays in front of what to do about it.
        'Ah, and, and one more thing, uh, the car, I need to change the oil, '
            'on Saturday maybe.': <(String, String?, String?)>[
          ('The car: change the oil', '2026-09-26', null),
        ],
        // A list said slowly is still a list, and a possessive "her" is not
        // the person named.
        'Milk. Eggs. Bread.': <(String, String?, String?)>[
          ('Milk', null, null),
          ('Eggs', null, null),
          ('Bread', null, null),
        ],
      });
      expect(
        (await run(
          'My sister, pick up her kids at 5.',
          at: wednesday,
        )).map(((String, String?, String?) t) => t.$1),
        isNot(contains('Pick up my sister kids')),
      );
    });

    test('"I am need to" is "I need to"', () async {
      await expectAll(wednesday, <String, List<(String, String?, String?)>>{
        'Okay so tomorrow, I am need go to university and give my documents '
            'to dean office.': <(String, String?, String?)>[
          (
            'Go to university and give my documents to dean office',
            '2026-09-24',
            null,
          ),
        ],
        'I am need to go to the bank and take money tomorrow.':
            <(String, String?, String?)>[
              ('Go to the bank and take money', '2026-09-24', null),
            ],
        'I am need to call the bank tomorrow.': <(String, String?, String?)>[
          ('Call the bank', '2026-09-24', null),
        ],
        'We are need to buy milk tomorrow.': <(String, String?, String?)>[
          ('Buy milk', '2026-09-24', null),
        ],
        'I am going to go to the bank and take money tomorrow.':
            <(String, String?, String?)>[
              ('Go to the bank and take money', '2026-09-24', null),
            ],
      });
    });

    test('"in the evening at 7" is 19:00, however it is ordered', () async {
      await expectAll(
        wednesdayMorning,
        <String, List<(String, String?, String?)>>{
          'In the evening go to the gym at 7.': <(String, String?, String?)>[
            ('Go to the gym', '2026-09-23', '19:00'),
          ],
          'Go to the gym in the evening at 7.': <(String, String?, String?)>[
            ('Go to the gym', '2026-09-23', '19:00'),
          ],
          'Tomorrow in the evening at 7 call my brother.':
              <(String, String?, String?)>[
                ('Call my brother', '2026-09-24', '19:00'),
              ],
          'Call my brother in the evening at 8.': <(String, String?, String?)>[
            ('Call my brother', '2026-09-23', '20:00'),
          ],
          'In the morning at 7 go jogging.': <(String, String?, String?)>[
            ('Go jogging', '2026-09-24', '07:00'),
          ],
          'At 7 go jogging in the morning.': <(String, String?, String?)>[
            ('Go jogging', '2026-09-24', '07:00'),
          ],
          'In the afternoon at 3 call the bank.': <(String, String?, String?)>[
            ('Call the bank', '2026-09-23', '15:00'),
          ],
          'In the evening at seven call my brother.':
              <(String, String?, String?)>[
                ('Call my brother', '2026-09-23', '19:00'),
              ],
          'At night at 11 take the pills.': <(String, String?, String?)>[
            ('Take the pills', '2026-09-23', '23:00'),
          ],
          'Tomorrow evening at 7 call my brother.':
              <(String, String?, String?)>[
                ('Call my brother', '2026-09-24', '19:00'),
              ],
        },
      );
    });

    test('"after work" and the task straight after it is a time', () async {
      await expectAll(monday, <String, List<(String, String?, String?)>>{
        'After work buy milk, bread and eggs.': <(String, String?, String?)>[
          ('After work buy milk, bread and eggs', null, null),
        ],
        'Tomorrow after work buy milk, bread and eggs.':
            <(String, String?, String?)>[
              ('After work buy milk, bread and eggs', '2026-09-22', null),
            ],
        'After school pick up Max, buy bread.': <(String, String?, String?)>[
          ('After school pick up Max', null, null),
          ('Buy bread', null, null),
        ],
        'Before the trip on Friday pack the passport, tickets and charger.':
            <(String, String?, String?)>[
              (
                'Before the trip pack the passport, tickets and charger',
                '2026-09-25',
                null,
              ),
            ],
        'Before the meeting print the slides, the agenda and the report.':
            <(String, String?, String?)>[
              (
                'Before the meeting print the slides, the agenda and the '
                    'report',
                null,
                null,
              ),
            ],
        'After dinner wash the dishes, take out the trash.':
            <(String, String?, String?)>[
              ('After dinner wash the dishes', null, null),
              ('Take out the trash', null, null),
            ],
        // A condition with a subject still ends at its comma.
        'When I get home, call mom.': <(String, String?, String?)>[
          ('Call mom', null, null),
        ],
        'After Anna leaves, clean the kitchen.': <(String, String?, String?)>[
          ('Clean the kitchen', null, null),
        ],
        'after work, buy milk, bread and eggs': <(String, String?, String?)>[
          ('Buy milk, bread and eggs', null, null),
        ],
      });
    });

    test('"around 11," and "remind me the day before" are not cards', () async {
      await expectAll(
        wednesdayMorning,
        <String, List<(String, String?, String?)>>{
          'Tomorrow morning at 8 I have to take the kids to school. After '
              'that, around 11, I have a meeting with Sardor about the new '
              'project in the office.': <(String, String?, String?)>[
            ('Take the kids to school', '2026-09-24', '08:00'),
            (
              'Meeting with Sardor about the new project in the office',
              '2026-09-24',
              '11:00',
            ),
          ],
          'Tomorrow around 11 I have a meeting with Sardor.':
              <(String, String?, String?)>[
                ('Meeting with Sardor', '2026-09-24', '11:00'),
              ],
          'Water the plants every evening.': <(String, String?, String?)>[
            ('Water the plants', '2026-09-23', '18:00'),
          ],
          // "about" before a count is still a count.
          'Buy about 5 apples.': <(String, String?, String?)>[
            ('Buy about 5 apples', null, null),
          ],
        },
      );
      // The reminder moves the task to the moment it was asked for…
      final List<ExtractedTask> report = await extractor.extract(
        'Next week Wednesday submit the report to my boss, and remind me the '
        'day before at 9 am.',
        now: wednesdayMorning,
      );
      expect(report, hasLength(1));
      expect(report.single.title, 'Submit the report to my boss');
      expect(report.single.date?.toIso(), '2026-09-29');
      expect(report.single.time?.toIso(), '09:00');
      expect(report.single.hasReminder, isTrue);
      final List<ExtractedTask> dayBefore = await extractor.extract(
        'Next week Wednesday submit the report to my boss, and remind me a '
        'day before.',
        now: wednesdayMorning,
      );
      expect(dayBefore, hasLength(1));
      expect(dayBefore.single.date?.toIso(), '2026-09-29');
      expect(dayBefore.single.hasReminder, isTrue);
      // …but an appointment keeps its own day and time.
      final List<ExtractedTask> dentist = await extractor.extract(
        'Dentist on Friday at 3, remind me the day before.',
        now: wednesdayMorning,
      );
      expect(dentist, hasLength(1));
      expect(dentist.single.date?.toIso(), '2026-09-25');
      expect(dentist.single.time?.toIso(), '15:00');
      expect(dentist.single.hasReminder, isTrue);
    });

    test('"call X and Y to invite them" is one call', () async {
      await expectAll(monday, <String, List<(String, String?, String?)>>{
        'On Sunday call Shahnoza and Timur to invite them to the wedding.':
            <(String, String?, String?)>[
              (
                'Call Shahnoza and Timur to invite them to the wedding',
                '2026-09-27',
                null,
              ),
            ],
        'Call Anna and Timur to invite them to the party.':
            <(String, String?, String?)>[
              ('Call Anna and Timur to invite them to the party', null, null),
            ],
        'On Sunday call grandma, grandpa, aunt Malika, uncle Rustam, Shahnoza '
                'and Timur to invite them to the wedding.':
            <(String, String?, String?)>[
              (
                'Call grandma, grandpa, aunt Malika, uncle Rustam, Shahnoza '
                    'and Timur to invite them to the wedding',
                '2026-09-27',
                null,
              ),
            ],
        'Text Bobur and Aziz to confirm the dinner.':
            <(String, String?, String?)>[
              ('Text Bobur and Aziz to confirm the dinner', null, null),
            ],
        // Somebody who does something is still a clause of their own.
        'Buy milk and Anna needs to go to the doctor.':
            <(String, String?, String?)>[
              ('Buy milk', null, null),
              ('Anna needs to go to the doctor', null, null),
            ],
      });
    });

    test(
      'people in the plural and a verb are a condition, not a card',
      () async {
        await expectAll(monday, <String, List<(String, String?, String?)>>{
          'After the guests leave, wash the dishes.':
              <(String, String?, String?)>[('Wash the dishes', null, null)],
          'After the kids go to bed, clean the kitchen.':
              <(String, String?, String?)>[('Clean the kitchen', null, null)],
          'After the kids come back from school, give them lunch.':
              <(String, String?, String?)>[('Give them lunch', null, null)],
          // An event in the plural is still an event.
          'After classes pick up Max, buy bread.': <(String, String?, String?)>[
            ('After classes pick up Max', null, null),
            ('Buy bread', null, null),
          ],
        });
      },
    );

    test(
      'a condition takes the first task after it, not all of them',
      () async {
        await expectAll(monday, <String, List<(String, String?, String?)>>{
          'After dinner, wash the dishes, take out the trash.':
              <(String, String?, String?)>[
                ('Wash the dishes', null, null),
                ('Take out the trash', null, null),
              ],
          'When I get home, call mom, buy milk.': <(String, String?, String?)>[
            ('Call mom', null, null),
            ('Buy milk', null, null),
          ],
          // More of a list is not another task.
          'Before the doctor, buy a notebook, a pen and water.':
              <(String, String?, String?)>[
                ('Buy a notebook, a pen and water', null, null),
              ],
          // A when inside the condition does not cut it off from its task.
          'After work tomorrow buy milk, bread and eggs.':
              <(String, String?, String?)>[
                ('After work buy milk, bread and eggs', '2026-09-22', null),
              ],
        });
      },
    );

    test('the event before a task may be longer, or a number', () async {
      await expectAll(monday, <String, List<(String, String?, String?)>>{
        'After work I need to buy milk, bread and eggs.':
            <(String, String?, String?)>[
              ('After work buy milk, bread and eggs', null, null),
            ],
        'After 5 call the bank, buy milk.': <(String, String?, String?)>[
          ('After 5 call the bank', null, null),
          ('Buy milk', null, null),
        ],
        'After the meeting with Sardor send the notes, call Anna.':
            <(String, String?, String?)>[
              ('After the meeting with Sardor send the notes', null, null),
              ('Call Anna', null, null),
            ],
        'Before leaving lock the door, turn off the gas.':
            <(String, String?, String?)>[
              ('Before leaving lock the door', null, null),
              ('Turn off the gas', null, null),
            ],
        'Before bed take the pills, brush teeth.': <(String, String?, String?)>[
          ('Before bed take the pills', null, null),
          ('Brush teeth', null, null),
        ],
        // Read as a condition, what follows the comma is still the list.
        'After the holidays buy new shoes, a coat and a scarf.':
            <(String, String?, String?)>[
              (
                'After the holidays buy new shoes, a coat and a scarf',
                null,
                null,
              ),
            ],
        // "before Friday" is the deadline; its "before" is not the title.
        'Before Friday send the report, call Anna.':
            <(String, String?, String?)>[
              ('Send the report', '2026-09-25', null),
              ('Call Anna', null, null),
            ],
      });
    });

    test('a thing said first, then what to do, is one card', () async {
      await expectAll(monday, <String, List<(String, String?, String?)>>{
        'The car, change the oil tomorrow.': <(String, String?, String?)>[
          ('The car: change the oil', '2026-09-22', null),
        ],
        'The keys, give them to Anna, and the car, wash it.':
            <(String, String?, String?)>[
              ('Give the keys to Anna', null, null),
              ('Wash the car', null, null),
            ],
        // "The last thing" is what comes next, not what it is about…
        'The last thing, call Anna.': <(String, String?, String?)>[
          ('Call Anna', null, null),
        ],
        // …and an event is a task of its own.
        'Tomorrow the dentist, call Anna at 5.': <(String, String?, String?)>[
          ('The dentist', '2026-09-22', null),
          ('Call Anna', '2026-09-22', '17:00'),
        ],
      });
      // A name is somebody spoken to, not what the task is about. Only that
      // is pinned here — not the card the name makes on its own.
      final List<(String, String?, String?)> spokenTo = await run(
        'Anna, call me back tomorrow.',
        at: monday,
      );
      expect(spokenTo, contains(('Call me back', '2026-09-22', null)));
      expect(
        spokenTo.map(((String, String?, String?) t) => t.$1),
        everyElement(isNot(contains('Anna:'))),
      );
    });

    test('hedges, "every" and "the … one" leave the title', () async {
      await expectAll(monday, <String, List<(String, String?, String?)>>{
        'Probably buy milk tomorrow.': <(String, String?, String?)>[
          ('Buy milk', '2026-09-22', null),
        ],
        'Every Monday take out the trash.': <(String, String?, String?)>[
          ('Take out the trash', '2026-09-28', null),
        ],
        'Uh, buy milk, you know, the oat one.': <(String, String?, String?)>[
          ('Buy milk', null, null),
        ],
        'Buy a charger, the big blue one, tomorrow.':
            <(String, String?, String?)>[('Buy a charger', '2026-09-22', null)],
        // Not a count, and not somebody's name.
        'Buy two, the red one and the blue one.': <(String, String?, String?)>[
          ('Buy two, the red one and the blue one', null, null),
        ],
      });
      // With no task before it, "remind me the day before" is about nothing.
      expect(await run('Remind me the day before.', at: monday), isEmpty);
    });
  });

  // Each rule here was broader than its finding, and none of these showed in
  // a corpus: the scorer's title match is lenient, so a garbled title still
  // counts. Hence exact titles.
  group('found by the review of those fixes', () {
    final LocalDateTime wednesday = LocalDateTime.parseIso('2026-09-23T15:00');

    Future<List<(String, String?, String?)>> run(String note) async =>
        <(String, String?, String?)>[
          for (final ExtractedTask t in await extractor.extract(
            note,
            now: wednesday,
          ))
            (t.title, t.date?.toIso(), t.time?.toIso()),
        ];

    Future<void> expectAll(
      Map<String, List<(String, String?, String?)>> cases,
    ) async {
      for (final MapEntry<String, List<(String, String?, String?)>> c
          in cases.entries) {
        expect(await run(c.key), c.value, reason: c.key);
      }
    }

    test('a task that drops its "I" is not a name before a "to"', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Buy milk, need to call Anna at 5.': <(String, String?, String?)>[
          ('Buy milk', null, null),
          ('Need to call Anna', '2026-09-23', '17:00'),
        ],
        'Buy bread, time to call Anna at 5.': <(String, String?, String?)>[
          ('Buy bread', null, null),
          ('Time to call Anna', '2026-09-23', '17:00'),
        ],
        'Pay the rent and need to renew the car insurance on Friday.':
            <(String, String?, String?)>[
              ('Pay the rent', null, null),
              ('Need to renew the car insurance', '2026-09-25', null),
            ],
        // A name after a comma is somebody else's errand, not one more
        // person for the verb before.
        'Buy milk, Ali to pick up Max at 5.': <(String, String?, String?)>[
          ('Buy milk', null, null),
          ('Ali to pick up Max', '2026-09-23', '17:00'),
        ],
        // After "and", still one more person.
        'Ask Bobur and Aziz to confirm the dinner tomorrow.':
            <(String, String?, String?)>[
              ('Ask Bobur and Aziz to confirm the dinner', '2026-09-24', null),
            ],
      });
    });

    test(
      'a part of the day that belongs to a thing is not the task\'s',
      () async {
        await expectAll(<String, List<(String, String?, String?)>>{
          'At 9 buy flowers for the party in the evening.':
              <(String, String?, String?)>[
                (
                  'Buy flowers for the party in the evening',
                  '2026-09-24',
                  '09:00',
                ),
              ],
          'Tomorrow at 7 wake up Timur for the flight in the afternoon.':
              <(String, String?, String?)>[
                (
                  'Wake up Timur for the flight in the afternoon',
                  '2026-09-24',
                  '07:00',
                ),
              ],
          'At 10 call the hotel about the late check-in in the evening.':
              <(String, String?, String?)>[
                (
                  'Call the hotel about the late check-in in the evening',
                  '2026-09-24',
                  '10:00',
                ),
              ],
          // Said after the task's own words, it is the task's — 6 included.
          'At 6 go running in the morning.': <(String, String?, String?)>[
            ('Go running', '2026-09-24', '06:00'),
          ],
          'At 11 take the pills at night.': <(String, String?, String?)>[
            ('Take the pills', '2026-09-23', '23:00'),
          ],
          // "about 5 people" is a count, "at 12 in the morning" midnight
          // whichever way round it is said.
          'In the evening about 5 people come for dinner, buy wine.':
              <(String, String?, String?)>[
                ('About 5 people come for dinner', '2026-09-23', '18:00'),
                ('Buy wine', null, null),
              ],
          'In the morning at 12 call Anna.': <(String, String?, String?)>[
            ('Call Anna', '2026-09-24', '00:00'),
          ],
          'At 12 in the morning call Anna.': <(String, String?, String?)>[
            ('Call Anna', '2026-09-24', '00:00'),
          ],
        });
      },
    );

    test('a reaction or a name is not what "it" stands for', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Perfect, send it to Anna tomorrow.': <(String, String?, String?)>[
          ('Send it to Anna', '2026-09-24', null),
        ],
        'Nice, book it for Friday.': <(String, String?, String?)>[
          ('Book it', '2026-09-25', null),
        ],
        'Excellent, now call him at 5.': <(String, String?, String?)>[
          ('Call him', '2026-09-23', '17:00'),
        ],
        'Thanks Anna. Send it to me tomorrow.': <(String, String?, String?)>[
          ('Send it to me', '2026-09-24', null),
        ],
        'Done. Send it to the client.': <(String, String?, String?)>[
          ('Send it to the client', null, null),
        ],
        // A bare thing that agrees with its pronoun still is the thing.
        'Groceries, buy them tomorrow.': <(String, String?, String?)>[
          ('Buy groceries', '2026-09-24', null),
        ],
        'Rent, pay it on Friday.': <(String, String?, String?)>[
          ('Pay rent', '2026-09-25', null),
        ],
      });
      // Who is spoken to, or how: the card they make on their own is not
      // pinned, only that they stay out of the task.
      for (final (String note, (String, String?, String?) task)
          in <(String, (String, String?, String?))>[
            (
              'Timur, pick them up at 5.',
              ('Pick them up', '2026-09-23', '17:00'),
            ),
            (
              'Anna, send it to me tomorrow.',
              ('Send it to me', '2026-09-24', null),
            ),
            (
              'Seriously, send it to Anna tomorrow.',
              ('Send it to Anna', '2026-09-24', null),
            ),
          ]) {
        expect(await run(note), contains(task), reason: note);
      }
    });

    test('only a little word said twice is a stutter', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Buy chocolate, chocolate milk and eggs.': <(String, String?, String?)>[
          ('Buy chocolate, chocolate milk and eggs', null, null),
        ],
        'Buy paper, paper towels and tea, tea bags.':
            <(String, String?, String?)>[
              ('Buy paper, paper towels and tea, tea bags', null, null),
            ],
        'Check in in the morning at the hotel.': <(String, String?, String?)>[
          ('Check in at the hotel', '2026-09-24', '09:00'),
        ],
        'Buy milk for, for the kids.': <(String, String?, String?)>[
          ('Buy milk for the kids', null, null),
        ],
        // Three times over is a whisper loop, whatever the word.
        'Buy milk, milk, milk, milk.': <(String, String?, String?)>[
          ('Buy milk', null, null),
        ],
        // After a number "mm" is millimetres.
        'Buy drill bits, 8 mm, and wood screws tomorrow.':
            <(String, String?, String?)>[
              ('Buy drill bits, 8 mm and wood screws', '2026-09-24', null),
            ],
      });
    });

    test('"remind me … before" moves a to-do, never an event', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Wedding on October 10th, remind me a week before.':
            <(String, String?, String?)>[('Wedding', '2026-10-10', null)],
        'The exam is on Monday, remind me the evening before.':
            <(String, String?, String?)>[('The exam', '2026-09-28', null)],
        'The rent is due on October 1st, remind me two days before.':
            <(String, String?, String?)>[
              ('The rent is due', '2026-10-01', null),
            ],
        'Pay the rent on October 1st, remind me two days before.':
            <(String, String?, String?)>[('Pay the rent', '2026-09-29', null)],
        // With a task of its own, the reminder is that task's day.
        'My flight is on Friday, remind me the day before to pack.':
            <(String, String?, String?)>[
              ('My flight', '2026-09-25', null),
              ('Pack', '2026-09-24', null),
            ],
        'Remind me the day before to buy a gift.': <(String, String?, String?)>[
          ('Buy a gift', null, null),
        ],
      });
      final List<ExtractedTask> wedding = await extractor.extract(
        'Wedding on October 10th, remind me a week before.',
        now: wednesday,
      );
      expect(wedding.single.hasReminder, isTrue);
    });

    test('notes that failed before the fixes too', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        // A when said before the first "to" is every "to"'s…
        'Remind me at 7 pm to take my pills and to lock the garage.':
            <(String, String?, String?)>[
              ('Take my pills', '2026-09-23', '19:00'),
              ('Lock the garage', '2026-09-23', '19:00'),
            ],
        'Remind me tomorrow to call the bank, to pay the rent, and to buy '
            'milk.': <(String, String?, String?)>[
          ('Call the bank', '2026-09-24', null),
          ('Pay the rent', '2026-09-24', null),
          ('Buy milk', '2026-09-24', null),
        ],
        // …and one said after it is that task's alone.
        'Remind me to call the bank at 10 and to pay the rent.':
            <(String, String?, String?)>[
              ('Call the bank', '2026-09-24', '10:00'),
              ('Pay the rent', null, null),
            ],
        'Hmm, what was it... ah yes, the washing machine, call master for fix '
            'it, maybe Thursday.': <(String, String?, String?)>[
          ('Call master for fix the washing machine', '2026-09-24', null),
        ],
        'So, like, the electricity bill, I forgot it again, pay it before '
            'Friday please.': <(String, String?, String?)>[
          ('Pay the electricity bill', '2026-09-25', null),
        ],
        'Uh, so tomorrow I must to go to the tax office, no wait, on Friday, '
            'and give them the papers.': <(String, String?, String?)>[
          ('Go to the tax office and give them the papers', '2026-09-25', null),
        ],
        'Tomorrow call Anna, no, Friday.': <(String, String?, String?)>[
          ('Call Anna', '2026-09-25', null),
        ],
        'At 4 pick up the kids, no wait, at 5.': <(String, String?, String?)>[
          ('Pick up the kids', '2026-09-23', '17:00'),
        ],
        'Tomorrow I must to go to the bank and take money.':
            <(String, String?, String?)>[
              ('Go to the bank and take money', '2026-09-24', null),
            ],
      });
      // A when that is followed by a task of its own replaces nothing.
      expect(
        await run('Tomorrow call Anna, no, on Friday call Bob.'),
        contains(('Call Bob', '2026-09-25', null)),
      );
    });
  });

  // extraction_correct_input_guard.json and the typed and whisper-style pairs
  // (2026-09-23 review). Exact titles again: the corpus scorer cannot tell
  // "Booked the flight" from "Book the flight".
  group('found by the correct-input guard review', () {
    final LocalDateTime wednesday = LocalDateTime.parseIso('2026-09-23T15:00');

    Future<List<(String, String?, String?)>> run(String note) async =>
        <(String, String?, String?)>[
          for (final ExtractedTask t in await extractor.extract(
            note,
            now: wednesday,
          ))
            (t.title, t.date?.toIso(), t.time?.toIso()),
        ];

    Future<void> expectAll(
      Map<String, List<(String, String?, String?)>> cases,
    ) async {
      for (final MapEntry<String, List<(String, String?, String?)>> c
          in cases.entries) {
        expect(await run(c.key), c.value, reason: c.key);
      }
    }

    test('a past tense keeps its card, in the words said', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Called the bank, the card is ready. Pick it up tomorrow at 10.':
            <(String, String?, String?)>[
              ('Called the bank', null, null),
              ('Pick it up', '2026-09-24', '10:00'),
            ],
        'Booked the flight for Friday, now pack the bags.':
            <(String, String?, String?)>[
              ('Booked the flight', '2026-09-25', null),
              ('Pack the bags', null, null),
            ],
        "Ordered the new phone, it's arriving on Friday.":
            <(String, String?, String?)>[('Ordered the new phone', null, null)],
        'Texted Madina the photos, now call Otabek.':
            <(String, String?, String?)>[
              ('Texted Madina the photos', null, null),
              ('Call Otabek', null, null),
            ],
        "Replied to Rustam's email and scheduled the team meeting for "
            'Thursday at 11.': <(String, String?, String?)>[
          ("Replied to Rustam's email", null, null),
          ('Scheduled the team meeting', '2026-09-24', '11:00'),
        ],
        // A past tense with a day still ahead is whisper's order.
        'So tomorrow packed the suitcase and exchanged some dollars.':
            <(String, String?, String?)>[
              ('Pack the suitcase', '2026-09-24', null),
              ('Exchange some dollars', '2026-09-24', null),
            ],
      });
    });

    test('a thing done on a day already gone is no card', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Fixed the sink yesterday, so today paint the bathroom.':
            <(String, String?, String?)>[
              ('Paint the bathroom', '2026-09-23', null),
            ],
        'Sent the contract to the lawyer this morning, now wait for his '
            'reply.': <(String, String?, String?)>[
          ('Wait for his reply', null, null),
        ],
        'Called the bank at 9 this morning, call them again tomorrow.':
            <(String, String?, String?)>[
              ('Call them again', '2026-09-24', null),
            ],
      });
    });

    test('the first task\'s day is the day of the "and" after it', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Buy a birthday cake for Nodira on Saturday and order balloons.':
            <(String, String?, String?)>[
              ('Buy a birthday cake for Nodira', '2026-09-26', null),
              ('Order balloons', '2026-09-26', null),
            ],
        'Call the plumber tomorrow at 2 pm, and text Bekzod the address.':
            <(String, String?, String?)>[
              ('Call the plumber', '2026-09-24', '14:00'),
              ('Text Bekzod the address', '2026-09-24', null),
            ],
        // whisper's full stop before the "And".
        'Book a table at the restaurant for Friday at 7pm. And invite '
            'Dilnoza and Timur.': <(String, String?, String?)>[
          ('Book a table at the restaurant', '2026-09-25', '19:00'),
          ('Invite Dilnoza and Timur', '2026-09-25', null),
        ],
        'Water the garden plants tonight and take out the trash.':
            <(String, String?, String?)>[
              ('Water the garden plants', '2026-09-23', '20:00'),
              ('Take out the trash', '2026-09-23', null),
            ],
        'On Friday at 10am. I have a dentist appointment. And after that, by '
            'flowers for mom.': <(String, String?, String?)>[
          ('Dentist appointment', '2026-09-25', '10:00'),
          ('Buy flowers for mom', '2026-09-25', null),
        ],
        'Call the plumber tomorrow, then text Bekzod.':
            <(String, String?, String?)>[
              ('Call the plumber', '2026-09-24', null),
              ('Text Bekzod', '2026-09-24', null),
            ],
      });
    });

    test('…but not a deadline, a moment, or a when of its own', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Submit the report by Friday and email Anna.':
            <(String, String?, String?)>[
              ('Submit the report', '2026-09-25', null),
              ('Email Anna', null, null),
            ],
        'Call Anna in 2 hours and buy milk.': <(String, String?, String?)>[
          ('Call Anna', '2026-09-23', '17:00'),
          ('Buy milk', null, null),
        ],
        'Call the plumber tomorrow, then later today buy milk.':
            <(String, String?, String?)>[
              ('Call the plumber', '2026-09-24', null),
              ('Buy milk', '2026-09-23', null),
            ],
        // A list, and an afterthought, say nothing of whose day it is.
        'Call the plumber tomorrow, text Bekzod.': <(String, String?, String?)>[
          ('Call the plumber', '2026-09-24', null),
          ('Text Bekzod', null, null),
        ],
        'Call mom tonight. Oh, and pay the bill.': <(String, String?, String?)>[
          ('Call mom', '2026-09-23', '20:00'),
          ('Pay the bill', null, null),
        ],
        // Only the first task's day: "…to check the hall tomorrow and to buy
        // candles" leaves the candles undated.
        'Remind me to call Otabek at 5, to order the cake on Friday, to check '
                'the hall tomorrow and to buy candles.':
            <(String, String?, String?)>[
              ('Call Otabek', '2026-09-23', '17:00'),
              ('Order the cake', '2026-09-25', null),
              ('Check the hall', '2026-09-24', null),
              ('Buy candles', null, null),
            ],
      });
    });

    test('"it\'s due at noon" is the time of the task before it', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        "Next Monday submit the quarterly report, it's due at noon.":
            <(String, String?, String?)>[
              ('Submit the quarterly report', '2026-09-28', '12:00'),
            ],
        "Next Monday, submit the Quarterly Report. It's due at noon.":
            <(String, String?, String?)>[
              ('Submit the Quarterly Report', '2026-09-28', '12:00'),
            ],
      });
    });

    test('how things or the speaker stand is not a task', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Ah yes, the Wi-Fi at home is not working, call the provider tomorrow '
            'at 10.': <(String, String?, String?)>[
          ('Call the provider', '2026-09-24', '10:00'),
        ],
        'I guess the Wi-Fi at home is not working. Call the provider tomorrow '
            'at 10.': <(String, String?, String?)>[
          ('Call the provider', '2026-09-24', '10:00'),
        ],
        "I'm close to the mall, buy milk.": <(String, String?, String?)>[
          ('Buy milk', null, null),
        ],
        // …but its day is the day of the task after it.
        "I'm free tomorrow, clean the garage.": <(String, String?, String?)>[
          ('Clean the garage', '2026-09-24', null),
        ],
        "I'm set for Friday, so today buy the gift.":
            <(String, String?, String?)>[('Buy the gift', '2026-09-23', null)],
        'The kids and their friends are coming on Saturday, bake a cake.':
            <(String, String?, String?)>[('Bake a cake', '2026-09-26', null)],
      });
      // "set to" is the task.
      expect(await run("I'm set to call Anna tomorrow."), hasLength(1));
    });
  });

  group('found by the review of the carried day', () {
    // The reviewer's moment: Wednesday 2026-09-23, 15:00. Thursday is the
    // 24th, Friday the 25th, Saturday the 26th, Sunday the 27th, Monday the
    // 28th.
    final LocalDateTime wednesday = LocalDateTime.parseIso('2026-09-23T15:00');

    Future<List<(String, String?, String?)>> run(String note) async =>
        <(String, String?, String?)>[
          for (final ExtractedTask t in await extractor.extract(
            note,
            now: wednesday,
          ))
            (t.title, t.date?.toIso(), t.time?.toIso()),
        ];

    Future<void> expectAll(
      Map<String, List<(String, String?, String?)>> cases,
    ) async {
      for (final MapEntry<String, List<(String, String?, String?)>> c
          in cases.entries) {
        expect(await run(c.key), c.value, reason: c.key);
      }
    }

    test('"eventually", "someday", "one day", "later this week" say no '
        'day', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Visit grandma on Saturday and eventually fix her fence.':
            <(String, String?, String?)>[
              ('Visit grandma', '2026-09-26', null),
              ('Fix her fence', null, null),
            ],
        'Send the slides to Kamila tonight and someday learn Spanish.':
            <(String, String?, String?)>[
              ('Send the slides to Kamila', '2026-09-23', '20:00'),
              ('Learn Spanish', null, null),
            ],
        'Um, on Saturday, clean the house. And, uh, one day we should '
            'repaint the kitchen.': <(String, String?, String?)>[
          ('Clean the house', '2026-09-26', null),
          ('Repaint the kitchen', null, null),
        ],
        "Tomorrow at 10 I have the doctor's appointment. And then, someday, "
            'I need to learn to swim.': <(String, String?, String?)>[
          ("Doctor's appointment", '2026-09-24', '10:00'),
          ('Learn to swim', null, null),
        ],
        'Tomorrow meeting at 9, then later this week visit grandma.':
            <(String, String?, String?)>[
              ('Meeting', '2026-09-24', '09:00'),
              ('Visit grandma', null, null),
            ],
        'Tomorrow, meeting with the team at 9. Then, later this week, visit '
            'Grandma.': <(String, String?, String?)>[
          ('Meeting with the team', '2026-09-24', '09:00'),
          ('Visit Grandma', null, null),
        ],
        'So tonight, uh, call mom. And, um, I also need to, like, eventually '
            'clean out the garage.': <(String, String?, String?)>[
          ('Call mom', '2026-09-23', '20:00'),
          ('Clean out the garage', null, null),
        ],
        // A length, not a someday.
        'Rent a car for one day tomorrow.': <(String, String?, String?)>[
          ('Rent a car for one day', '2026-09-24', null),
        ],
        'Take one day off on Friday.': <(String, String?, String?)>[
          ('Take one day off', '2026-09-25', null),
        ],
      });
    });

    test('a task that waits for something else has no day', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Wash the car on Sunday and then after payday buy new tires.':
            <(String, String?, String?)>[
              ('Wash the car', '2026-09-27', null),
              ('After payday buy new tires', null, null),
            ],
        'Tomorrow buy a new phone and cancel the old contract once it '
            'arrives.': <(String, String?, String?)>[
          ('Buy a new phone', '2026-09-24', null),
          ('Cancel the old contract once it arrives', null, null),
        ],
        "Take the car to the service tomorrow and once it's fixed drive to "
            'Samarkand.': <(String, String?, String?)>[
          ('Take the car to the service', '2026-09-24', null),
          ("Once it's fixed drive to Samarkand", null, null),
        ],
        'Pay the gas bill today and when the salary comes pay off the credit '
            'card.': <(String, String?, String?)>[
          ('Pay the gas bill', '2026-09-23', null),
          ('When the salary comes pay off the credit card', null, null),
        ],
        'Call the bank tomorrow at 11. And then when Aziz sends the '
                'documents, forward them to the lawyer.':
            <(String, String?, String?)>[
              ('Call the bank', '2026-09-24', '11:00'),
              ('Forward them to the lawyer', null, null),
            ],
        'Tomorrow call the bank and once they approve the loan, sign the '
            'papers.': <(String, String?, String?)>[
          ('Call the bank', '2026-09-24', null),
          ('Sign the papers', null, null),
        ],
        'On Friday pay the rent and when I get paid buy a new phone.':
            <(String, String?, String?)>[
              ('Pay the rent', '2026-09-25', null),
              ('When I get paid buy a new phone', null, null),
            ],
        // The speaker's own day, and what happens on the occasion itself.
        'Call Anna tomorrow and when I get home cook dinner.':
            <(String, String?, String?)>[
              ('Call Anna', '2026-09-24', null),
              ('When I get home cook dinner', '2026-09-24', null),
            ],
        'Visit the bank on Friday and after work pick up the kids.':
            <(String, String?, String?)>[
              ('Visit the bank', '2026-09-25', null),
              ('After work pick up the kids', '2026-09-25', null),
            ],
        'Call the landlord tomorrow and when he answers ask about the '
            'deposit.': <(String, String?, String?)>[
          ('Call the landlord', '2026-09-24', null),
          ('When he answers ask about the deposit', '2026-09-24', null),
        ],
      });
    });

    test('a statement of its own after "and" does not take the day', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Call Anna tomorrow and I also need to renew my passport.':
            <(String, String?, String?)>[
              ('Call Anna', '2026-09-24', null),
              ('Renew my passport', null, null),
            ],
        'Call the vet on Friday and I should really start going to the gym.':
            <(String, String?, String?)>[
              ('Call the vet', '2026-09-25', null),
              ('Start going to the gym', null, null),
            ],
        'Fix the shelf tomorrow and I need to buy screws.':
            <(String, String?, String?)>[
              ('Fix the shelf', '2026-09-24', null),
              ('Buy screws', null, null),
            ],
        // "Then" still orders it after the task, on its day…
        'Fix the shelf tomorrow and then I need to buy screws.':
            <(String, String?, String?)>[
              ('Fix the shelf', '2026-09-24', null),
              ('Buy screws', '2026-09-24', null),
            ],
        // …and a day said first is the whole sentence's.
        'Tomorrow fix the shelf and I need to buy screws.':
            <(String, String?, String?)>[
              ('Fix the shelf', '2026-09-24', null),
              ('Buy screws', '2026-09-24', null),
            ],
      });
    });

    test('a question or a musing is not a card', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Call the dentist tomorrow and, um, did I pay the phone bill?':
            <(String, String?, String?)>[
              ('Call the dentist', '2026-09-24', null),
            ],
        'Send the contract to Jasur tomorrow morning. And is the printer '
            'still broken?': <(String, String?, String?)>[
          ('Send the contract to Jasur', '2026-09-24', '09:00'),
        ],
        'Call the landlord tomorrow. And I wonder if he fixed the heating.':
            <(String, String?, String?)>[
              ('Call the landlord', '2026-09-24', null),
            ],
        'Tomorrow buy a cake. And, um, what time does the party start?':
            <(String, String?, String?)>[('Buy a cake', '2026-09-24', null)],
        'Where did I put the car keys?': <(String, String?, String?)>[],
      });
      // An order whisper ended with a question mark is still the task.
      expect(await run('Do the laundry tomorrow?'), hasLength(1));
      expect(await run('Have lunch with Sherzod on Friday?'), hasLength(1));
      expect(
        await run('Can you remind me to call Anna tomorrow?'),
        hasLength(1),
      );
    });

    test('"by the way" is an afterthought, not a card', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Buy the concert tickets tomorrow. And by the way, get the tyres '
            'changed on the car.': <(String, String?, String?)>[
          ('Buy the concert tickets', '2026-09-24', null),
          ('Get the tyres changed on the car', null, null),
        ],
        'Visit grandma on Sunday. Oh and by the way, bring her the medicine.':
            <(String, String?, String?)>[
              ('Visit grandma', '2026-09-27', null),
              ('Bring her the medicine', null, null),
            ],
      });
    });

    test(
      "a remark about something else's hours is not the task's time",
      () async {
        await expectAll(<String, List<(String, String?, String?)>>{
          "Go to the bank tomorrow, it's always crowded in the morning.":
              <(String, String?, String?)>[
                ('Go to the bank', '2026-09-24', null),
              ],
          'Buy bread, the shop closes at noon.': <(String, String?, String?)>[
            ('Buy bread', null, null),
          ],
          'Buy bread, the shop closes at 8.': <(String, String?, String?)>[
            ('Buy bread', null, null),
          ],
          "Walk the dog tomorrow, it's too hot in the afternoon.":
              <(String, String?, String?)>[
                ('Walk the dog', '2026-09-24', null),
              ],
          'Call Aziz on Friday, he is usually free in the evening.':
              <(String, String?, String?)>[('Call Aziz', '2026-09-25', null)],
          'Buy milk tomorrow, the shop is closed in the morning.':
              <(String, String?, String?)>[('Buy milk', '2026-09-24', null)],
          // When the task itself is due still is.
          "Send the report on Friday, it's due at noon.":
              <(String, String?, String?)>[
                ('Send the report', '2026-09-25', '12:00'),
              ],
        });
      },
    );

    test('two things said as done are one card, unless the second has a '
        'when', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Called Anna and asked her about the party.':
            <(String, String?, String?)>[
              ('Called Anna and asked her about the party', null, null),
            ],
        'Called the landlord and asked about the deposit.':
            <(String, String?, String?)>[
              ('Called the landlord and asked about the deposit', null, null),
            ],
        'Called the plumber and fixed the leak.': <(String, String?, String?)>[
          ('Called the plumber and fixed the leak', null, null),
        ],
        'Called the dentist and booked a cleaning for Friday at 10.':
            <(String, String?, String?)>[
              ('Called the dentist', null, null),
              ('Booked a cleaning', '2026-09-25', '10:00'),
            ],
      });
    });

    test('two who are coming give their day to the task after them', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'My parents and my sister are coming on Sunday, clean the guest room.':
            <(String, String?, String?)>[
              ('Clean the guest room', '2026-09-27', null),
            ],
        'Aziz and Madina are coming on Sunday, cook plov.':
            <(String, String?, String?)>[('Cook plov', '2026-09-27', null)],
        'Timur and Lola are arriving tomorrow, clean the guest room.':
            <(String, String?, String?)>[
              ('Clean the guest room', '2026-09-24', null),
            ],
        // Two people to call are the task.
        'Call Aziz and Madina tomorrow.': <(String, String?, String?)>[
          ('Call Aziz and Madina', '2026-09-24', null),
        ],
      });
    });

    test('a thing done on a day gone is no card, however its verb is '
        'spelled', () async {
      await expectAll(<String, List<(String, String?, String?)>>{
        'Paid the rent yesterday, buy groceries today.':
            <(String, String?, String?)>[('Buy groceries', '2026-09-23', null)],
        'Bought the tickets yesterday, now pack the bags.':
            <(String, String?, String?)>[('Pack the bags', null, null)],
        'Went to the bank this morning, now call Aziz.':
            <(String, String?, String?)>[('Call Aziz', null, null)],
        'Took the car to the service yesterday, pick it up tomorrow.':
            <(String, String?, String?)>[('Pick it up', '2026-09-24', null)],
        'Did the laundry this morning, iron it tonight.':
            <(String, String?, String?)>[('Iron it', '2026-09-23', '20:00')],
      });
      // "Got to" is a "have to"; and a part still to do keeps the card.
      expect(await run('Got to call the bank tomorrow morning.'), hasLength(1));
      expect(
        await run('Did the laundry this morning, fold it tonight.'),
        hasLength(1),
      );
    });

    test(
      "the speaker's own day said mid-sentence is the next task's",
      () async {
        await expectAll(<String, List<(String, String?, String?)>>{
          "Call Anna tomorrow, and I'm free on Saturday, so clean the garage.":
              <(String, String?, String?)>[
                ('Call Anna', '2026-09-24', null),
                ('Clean the garage', '2026-09-26', null),
              ],
          "Call the bank tomorrow, and we're free on Sunday, so visit grandma.":
              <(String, String?, String?)>[
                ('Call the bank', '2026-09-24', null),
                ('Visit grandma', '2026-09-27', null),
              ],
        });
      },
    );
  });

  test('a negative phrase does not lose any of its title', () async {
    for (final String utterance in <String>[
      'buy 3 apples',
      'version 2.1 needs a changelog',
      'march to the store',
      'send the 2026 report',
    ]) {
      final List<ExtractedTask> tasks = await extractor.extract(
        utterance,
        now: now,
      );
      expect(tasks, hasLength(1), reason: utterance);
      expect(tasks.single.date, isNull, reason: utterance);
      expect(
        tasks.single.title.toLowerCase(),
        utterance.toLowerCase(),
        reason: utterance,
      );
    }
  });
}
