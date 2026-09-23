import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/transcript_normaliser.dart';

import '../../helpers/extraction_scoring.dart';

/// How whisper writes a spoken note down, and what the extractor makes of it.
///
/// Every note in the "whisper wrote" groups is a real transcript: whisper
/// base.en on a clip of the voice evaluation's TUNE half (dev, fresh and
/// complex-dev cases), verbatim, with the clip's own labels and the moment it
/// was said. Each was a note the extractor lost to whisper's way of writing
/// speech down, not to a word whisper misheard. The few rules no TUNE clip
/// exercised yet are pinned with notes written in the same shape, and say so.
void main() {
  const TranscriptNormaliser normaliser = TranscriptNormaliser();
  const RuleBasedTaskExtractor extractor = RuleBasedTaskExtractor();

  // The complex corpora are said on Wednesday 23 September 2026 at 15:00, the
  // dev and fresh corpora on Monday 21 September at 10:00.
  final LocalDateTime complexNow = LocalDateTime.parseIso('2026-09-23T15:00');
  final LocalDateTime devNow = LocalDateTime.parseIso('2026-09-21T10:00');

  List<String> titles(List<ExtractedTask> tasks) =>
      tasks.map((ExtractedTask t) => t.title).toList();

  /// Scores [transcript] against its clip's labels the way the corpora are
  /// scored, and fails with every problem when it is not exact.
  Future<void> exact(
    String transcript,
    List<ExpectedTask> labels, {
    LocalDateTime? now,
  }) async {
    final List<ExtractedTask> tasks = await extractor.extract(
      transcript,
      now: now ?? complexNow,
    );
    final NoteScore score = scoreNote(LabelledNote(transcript, labels), tasks);
    expect(
      score.exact,
      isTrue,
      reason:
          '${score.problems.join('; ')}\n'
          'got: ${tasks.map((ExtractedTask t) => '${t.title} '
              '${t.date?.toIso()} ${t.time?.toIso()}').join(' | ')}',
    );
  }

  group('whisper wrote a hesitation as a word', () {
    test('"I\'m so next Tuesday…" is "Um, so, next Tuesday…"', () async {
      await exact(
        "I'm so next Tuesday I have job interview at 11am in the new bank "
        'office in Tashguent City so on Monday I have to up-make my CV and '
        'print it.',
        const <ExpectedTask>[
          ExpectedTask(
            'Job interview at the bank office in Tashkent City',
            '2026-09-29',
            '11:00',
          ),
          ExpectedTask('Update and print my CV', '2026-09-28', null),
        ],
      );
    });

    test('"On Ok work stuff." is "Um, okay, work stuff."', () async {
      await exact(
        'On Ok work stuff. Send a monthly report to Bexard Aco until the '
        '30th. On October 5th we have the tax audit so collect all the '
        'receipts by Monday.',
        const <ExpectedTask>[
          ExpectedTask('Send the monthly report to Bekzod', '2026-09-30', null),
          ExpectedTask('Tax audit', '2026-10-05', null),
          ExpectedTask('Collect all the receipts', '2026-09-28', null),
        ],
      );
    });

    test('"Ugh." is a hesitation, not a card', () async {
      final List<ExtractedTask> tasks = await extractor.extract(
        'Ugh. Call the car dealer, send Jess or the contractor after half an '
        'hour, and pay the property tax by next Friday.',
        now: complexNow,
      );
      expect(titles(tasks), isNot(contains('Ugh')));
      expect(titles(tasks).first, 'Call the car dealer');
    });

    test('an "I\'m" that is said is kept', () {
      for (final String said in <String>[
        "I'm going to call the bank.",
        "I'm so tired, call mom tomorrow.",
        "I'm just testing if this thing works.",
        "I'm okay with Friday for the meeting.",
        "I'm at the gym now, it's very crowded today.",
        "I'm back tomorrow, call Anna in the evening.",
        "I'm tomorrow in Samarkand, call Anna.",
        "I'm called Anna.",
      ]) {
        expect(normaliser.normalise(said), said, reason: said);
      }
    });

    test('"I\'m" before what cannot follow it', () {
      expect(
        normaliser.normalise("I'm just quickly buy bread and kefir."),
        'Um just quickly buy bread and kefir.',
      );
      expect(
        normaliser.normalise("I'm okay, so today was very long day."),
        'Um okay, so today was very long day.',
      );
      expect(
        normaliser.normalise("I'm today I still need vacuum the living room."),
        'Um today I still need vacuum the living room.',
      );
      expect(
        normaliser.normalise(
          "I'm called Jasper about the group project at 4 p.m.",
        ),
        'Um call Jasper about the group project at 4 p.m.',
      );
      expect(
        normaliser.normalise('Unremind me to transfer 50,000 to Josser.'),
        'Um, remind me to transfer 50,000 to Josser.',
      );
    });
  });

  group('whisper wrote a clock time its own way', () {
    test('"730 in the morning" is 7:30', () async {
      await exact(
        'At 730 in the morning drive Farrok to the airport, then at noon '
        'pick up my passport from the migration office. Also buy a charger '
        'for my laptop.',
        const <ExpectedTask>[
          ExpectedTask('Drive Farrukh to the airport', '2026-09-24', '07:30'),
          ExpectedTask(
            'Pick up my passport from the migration office',
            '2026-09-24',
            '12:00',
          ),
          ExpectedTask('Buy a charger for my laptop', null, null),
        ],
      );
      // A number that names a thing is not a time.
      expect(
        normaliser.normalise('Book room 730 in the morning.'),
        'Book room 730 in the morning.',
      );
    });

    test('"then a noon" is "then at noon"', () async {
      final List<ExtractedTask> tasks = await extractor.extract(
        'At 7.30 in the morning dry farad to the airport then a noon pick up '
        'my passport from the migration office. Also buy a charger from my '
        'laptop.',
        now: complexNow,
      );
      final ExtractedTask passport = tasks.firstWhere(
        (ExtractedTask t) => t.title.contains('passport'),
      );
      expect(passport.title, 'Pick up my passport from the migration office');
      expect(passport.time?.toIso(), '12:00');
      // "a 12 pack of beer" is a count.
      expect(
        normaliser.normalise('Buy milk then a 12 pack of beer.'),
        'Buy milk then a 12 pack of beer.',
      );
    });

    test('"at 6th pick up" is "at 6, pick up"', () {
      expect(
        normaliser.normalise('then at 6th pick up Madina from dance class'),
        'then at 6 pick up Madina from dance class',
      );
      expect(
        normaliser.normalise('Meet at 5th avenue.'),
        'Meet at 5th avenue.',
      );
    });

    // No TUNE clip has these yet; written in the shape whisper leaves them.
    test('"at 4.0" and "at 15 0 0" are whole hours', () async {
      expect(normaliser.normalise('Call Anna at 4.0.'), 'Call Anna at 4.');
      expect(
        normaliser.normalise('Call Anna at 15 0 0.'),
        'Call Anna at 15:00.',
      );
      expect(
        normaliser.normalise('Update to version 2.0 tomorrow.'),
        'Update to version 2.0 tomorrow.',
      );
      final List<ExtractedTask> tasks = await extractor.extract(
        'Call Anna at 15 0 0.',
        now: devNow,
      );
      expect(titles(tasks), <String>['Call Anna']);
      expect(tasks.single.time?.toIso(), '15:00');
    });

    test('"before six", spelled out, is a deadline on the clock', () async {
      final List<ExtractedTask> tasks = await extractor.extract(
        'Cook dinner before six.',
        now: devNow,
      );
      expect(titles(tasks), <String>['Cook dinner']);
      expect(tasks.single.time?.toIso(), '18:00');
      final List<ExtractedTask> count = await extractor.extract(
        'Check the boxes one by one.',
        now: devNow,
      );
      expect(count.single.time, isNull);
    });

    // No TUNE clip has it yet; the shape whisper and speakers leave it in.
    test('"on 25th", without the "the"', () async {
      final List<ExtractedTask> tasks = await extractor.extract(
        'Pay the rent on 25th.',
        now: devNow,
      );
      expect(titles(tasks), <String>['Pay the rent']);
      expect(tasks.single.date?.toIso(), '2026-09-25');
    });
  });

  group('whisper wrote a task\'s verb as a word that sounds the same', () {
    test('"called", "canceled" where a task starts', () async {
      await exact(
        'Next Wednesday called the Internet provider about the slow '
        "connection and on the fifth pay my son's school fees at the bank. "
        'Oh, and canceled the old TV subscription.',
        const <ExpectedTask>[
          ExpectedTask(
            'Call the internet provider about the slow connection',
            '2026-09-30',
            null,
          ),
          ExpectedTask(
            "Pay my son's school fees at the bank",
            '2026-10-05',
            null,
          ),
          ExpectedTask('Cancel the old TV subscription', null, null),
        ],
      );
    });

    test('a past tense that is said is kept', () {
      for (final String said in <String>[
        'Sardor called and asked me to buy bread.',
        'My boss emailed and sent the contract, review it tomorrow.',
        'Booked the table already, now call the guests.',
        'Yesterday called the bank about the card, call them again tomorrow.',
        'Buy the book, called Atomic Habits.',
        'Install the app called Payme.',
        // A "now" after it sets what is done against what is left to do.
        'Booked the flight for Friday, now pack the bags.',
        'Sent the contract to the lawyer this morning, now wait for his reply.',
        // A "for" that dates the thing, not the doing.
        'Booked the flight for Friday.',
        "Replied to Rustam's email and scheduled the team meeting for "
            'Thursday at 11.',
      ]) {
        expect(normaliser.normalise(said), said, reason: said);
      }
      // Said at 15:00, "at 9 this morning" is over: done, not an order.
      expect(
        normaliser.normalise(
          'Called the bank at 9 this morning.',
          now: complexNow,
        ),
        'Called the bank at 9 this morning.',
      );
      // …and a when still ahead is whisper's "call".
      expect(
        normaliser.normalise('So tomorrow called the bank.', now: complexNow),
        'So tomorrow call the bank.',
      );
    });

    test('"I\'m I need to…" is "Um, I need to…"', () {
      expect(
        normaliser.normalise(
          "I'm I need to renew my driver's license so on Monday get new "
          'photos taken.',
        ),
        "Um I need to renew my driver's license so on Monday get new photos "
        'taken.',
      );
    });

    test('"by a new charger" where a task starts is "buy"', () {
      expect(
        normaliser.normalise(
          'Tomorrow by a new charger for my phone and call you mid about the '
          'car.',
        ),
        'Tomorrow buy a new charger for my phone and call you mid about the '
        'car.',
      );
      for (final String said in <String>[
        'By Friday send the report.',
        'By the end of the week finish the slides.',
        'By the way, call Anna.',
        'Tomorrow by train go to Samarkand.',
        'By 5 pick up the kids.',
        'Then by the bakery pick up bread.',
        // By an event, not buying one.
        'By the birthday party, clean the house.',
        'By the meeting prepare the slides.',
        'By the dentist appointment tomorrow.',
      ]) {
        expect(normaliser.normalise(said), said, reason: said);
      }
      // An event word in front of the thing does not make it an event.
      expect(
        normaliser.normalise(
          'By a birthday cake for Nodira on Saturday and order balloons.',
        ),
        'Buy a birthday cake for Nodira on Saturday and order balloons.',
      );
      expect(
        normaliser.normalise('By a lunch box for Timur.'),
        'Buy a lunch box for Timur.',
      );
    });

    test('"pickup" where a task starts is "pick up"', () async {
      await exact(
        'Remind me in 45 minutes to take the laundry out of the washing '
        'machine and in an hour and a half pickup mat in a firmer dance '
        'class.',
        const <ExpectedTask>[
          ExpectedTask(
            'Take the laundry out of the washing machine',
            '2026-09-23',
            '15:45',
          ),
          ExpectedTask(
            'Pick up Madina from her dance class',
            '2026-09-23',
            '16:30',
          ),
        ],
      );
      expect(
        normaliser.normalise('The pickup is at 5.'),
        'The pickup is at 5.',
      );
    });
  });

  group('whisper left out a comma, or put in a full stop', () {
    test('a list of "to"s said without its commas', () async {
      await exact(
        'Remind me to call Nargis at 4 about the wedding menu to order the '
        'cake on Monday to check the hall tomorrow morning and to buy '
        'balloons.',
        const <ExpectedTask>[
          ExpectedTask(
            'Call Nargiza about the wedding menu',
            '2026-09-23',
            '16:00',
          ),
          ExpectedTask('Order the cake', '2026-09-28', null),
          ExpectedTask('Check the hall', '2026-09-24', '09:00'),
          ExpectedTask('Buy balloons', null, null),
        ],
      );
      for (final String said in <String>[
        'Remind me to ask Timur to call me and to send the photos.',
        'Remind me to call Anna to ask about the party and to buy a gift.',
        'I need to go to the bank to pay the bill, to call Anna and to buy '
            'milk.',
      ]) {
        expect(normaliser.normalise(said), said, reason: said);
      }
    });

    test('somebody\'s news run into the task after its time', () async {
      for (final String transcript in <String>[
        'Remind me at 10am to send the documents to the notary. Oh, and the '
            'day after tomorrow is Audibix farewell party at 7pm he is moving '
            'to Korea.',
        'Ramani at 10am to send the documents to the notary. Oh, and the day '
            "after tomorrow is Athebak's farewell party at 7pm he is moving to "
            'Korea.',
      ]) {
        await exact(transcript, const <ExpectedTask>[
          ExpectedTask(
            'Send the documents to the notary',
            '2026-09-24',
            '10:00',
          ),
          ExpectedTask("Otabek's farewell party", '2026-09-25', '19:00'),
        ]);
      }
      expect(
        normaliser.normalise('Tell mom she is coming with us.'),
        'Tell mom she is coming with us.',
      );
    });

    test('a sentence whisper began with a capital and no stop', () {
      expect(
        normaliser.normalise(
          'Go to the library and return the books Meet Nadira at 12 and '
          'finish the presentation slides.',
        ),
        'Go to the library and return the books, Meet Nadira at 12 and '
        'finish the presentation slides.',
      );
      expect(
        normaliser.normalise('Watch Clean Code talk tonight.'),
        'Watch Clean Code talk tonight.',
      );
    });

    test('"so" and a new day, the comma left out', () async {
      await exact(
        "Next week on Tuesday I have to renew my driver's license so on "
        'Monday get new photos taken for it.',
        const <ExpectedTask>[
          ExpectedTask("Renew my driver's license", '2026-09-29', null),
          ExpectedTask(
            'Get new photos taken for the license',
            '2026-09-28',
            null,
          ),
        ],
      );
    });

    test('quote marks around a hesitant phrase', () async {
      await exact(
        '"Remind me at 10am to send the documents to the notary. Oh, and the '
        'day after tomorrow is Aotibix farewell party, at 7pm he is moving to '
        'Korea."',
        const <ExpectedTask>[
          ExpectedTask(
            'Send the documents to the notary',
            '2026-09-24',
            '10:00',
          ),
          ExpectedTask("Otabek's farewell party", '2026-09-25', '19:00'),
        ],
      );
      await exact(
        '"I\'m what else?" "Ah, yes. The Internet at home is not working since '
        'yesterday, call the provider in the morning. And, Ah Madner asked me '
        'to print her homework do it tonight."',
        const <ExpectedTask>[
          ExpectedTask('Call the internet provider', '2026-09-24', '09:00'),
          ExpectedTask("Print Madina's homework", '2026-09-23', '20:00'),
        ],
      );
    });
  });

  group('whisper wrote a stretch in Title Case', () {
    // ⚠️ It used to be lower-cased after a determiner, and a typed name went
    // with it: "the Head Of Sales", "the Harry Potter book", "the Amir Timur
    // Museum" (extraction_correct_input_guard.json). No rule tells whisper's
    // capitals from a name's, and a wrong capital costs less than a lost
    // name, so the capitals stay as said.
    test('after a determiner, the run keeps its capitals', () async {
      final List<ExtractedTask> grant = await extractor.extract(
        'On Monday the 5th at 9am, I must submit the Grant Report so this '
        'Sunday, write the first draft.',
        now: complexNow,
      );
      expect(titles(grant).first, 'Submit the Grant Report');
      final List<ExtractedTask> room = await extractor.extract(
        'My sister, Don Noser, is coming from Moscow on the 28th. I need to '
        'pick her up from the airport at 11 at night. I\'m in Clean the Gas '
        'Room on Sunday.',
        now: complexNow,
      );
      expect(titles(room).last, 'Clean the Gas Room');
    });

    test('a name keeps its capitals', () {
      // One capitalised word is taken for a name; so is a word the note
      // capitalises elsewhere between lower-case words.
      expect(
        normaliser.normalise('Book the Istanbul flight.'),
        'Book the Istanbul flight.',
      );
      expect(
        normaliser.normalise(
          'Tomorrow call Malika about the order and pick up the Malika Bazaar '
          'receipt.',
        ),
        'Tomorrow call Malika about the order and pick up the Malika Bazaar '
        'receipt.',
      );
      expect(
        normaliser.normalise('Cancel the old TV subscription.'),
        'Cancel the old TV subscription.',
      );
    });
  });
}
