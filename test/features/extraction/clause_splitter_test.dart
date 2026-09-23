import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/features/extraction/domain/clause_splitter.dart';

void main() {
  const ClauseSplitter splitter = ClauseSplitter();

  group('splitting', () {
    test('the spec example', () {
      expect(
        splitter.splitClauses(
          'Tomorrow at 3 PM send the build to James and Friday check App Store',
        ),
        <String>[
          'Tomorrow at 3 PM send the build to James',
          'Friday check App Store',
        ],
      );
    });

    test('every connective people actually say', () {
      expect(splitter.splitClauses('call mark and email jane'), <String>[
        'call mark',
        'email jane',
      ]);
      expect(splitter.splitClauses('call mark then email jane'), <String>[
        'call mark',
        'email jane',
      ]);
      expect(splitter.splitClauses('call mark also email jane'), <String>[
        'call mark',
        'email jane',
      ]);
      expect(splitter.splitClauses('call mark, and then email jane'), <String>[
        'call mark',
        'email jane',
      ]);
      expect(splitter.splitClauses('call mark after that email jane'), <String>[
        'call mark',
        'email jane',
      ]);
      expect(splitter.splitClauses('call mark plus email jane'), <String>[
        'call mark',
        'email jane',
      ]);
      expect(splitter.splitClauses('call mark; email jane'), <String>[
        'call mark',
        'email jane',
      ]);
    });

    test('three tasks in one breath', () {
      expect(
        splitter.splitClauses(
          'buy milk and call the dentist and then pay the rent',
        ),
        <String>['buy milk', 'call the dentist', 'pay the rent'],
      );
    });

    test('a new leading temporal anchor splits without any connective', () {
      expect(
        splitter.splitClauses(
          'Tomorrow at 3 PM send the build to James Friday check App Store',
        ),
        <String>[
          'Tomorrow at 3 PM send the build to James',
          'Friday check App Store',
        ],
      );
    });
  });

  group('complex spoken notes', () {
    test('a when the splitter knows only because the grammar does', () {
      // ⚠️ "the day after tomorrow", "in an hour and a half" — and the "and"
      // inside the second one joins nothing.
      expect(
        splitter.splitClauses(
          'the day after tomorrow book the car inspection and change the oil',
        ),
        <String>[
          'the day after tomorrow book the car inspection',
          'change the oil',
        ],
      );
      expect(
        splitter.splitClauses(
          'in an hour and a half call mom and at 7 cook dinner',
        ),
        <String>['in an hour and a half call mom', 'at 7 cook dinner'],
      );
    });

    test('filler between two tasks goes with the second', () {
      expect(
        splitter.splitClauses(
          'call Umid about the car, oh and on Saturday take the kids to the zoo',
        ),
        <String>[
          'call Umid about the car',
          'oh, on Saturday take the kids to the zoo',
        ],
      );
    });

    test('a verb said once for a list of dated items', () {
      expect(
        splitter.splitClauses(
          'on the 1st pay the mortgage, on the 2nd the gas bill',
        ),
        <String>['on the 1st pay the mortgage', 'on the 2nd pay the gas bill'],
      );
    });

    test('"… and print it" is the same task; a verb still to come joins', () {
      expect(
        splitter.splitClauses(
          'on Monday I have to, uh, update my CV and print it',
        ),
        <String>['on Monday I have to, uh, update my CV and print it'],
      );
    });

    test('a new request is never the purpose of an errand', () {
      expect(
        splitter.splitClauses(
          'stop at the pharmacy for her vitamins, and remind me on Saturday to buy shoes',
        ),
        <String>[
          'stop at the pharmacy for her vitamins',
          'remind me on Saturday to buy shoes',
        ],
      );
    });
  });

  group('what must stay one clause', () {
    test('the critical negative case', () {
      const String utterance = 'send the build and the release notes to James';
      expect(splitter.splitClauses(utterance), <String>[utterance]);
    });

    test('a conjoined object is not a second task', () {
      for (final String utterance in <String>[
        'buy milk and eggs',
        'call mom and dad',
        'buy bread and butter and jam',
        'review the design and the copy',
        'email the invoice and the receipt to accounting',
        'pack the charger and the passport',
      ]) {
        expect(splitter.splitClauses(utterance), <String>[
          utterance,
        ], reason: utterance);
      }
    });

    test('a trailing temporal phrase belongs to the clause it follows', () {
      expect(
        splitter.splitClauses('send the build to James on Friday'),
        <String>['send the build to James on Friday'],
      );
      expect(splitter.splitClauses('buy milk tomorrow morning'), <String>[
        'buy milk tomorrow morning',
      ]);
    });

    test('a fragment with no verb of its own is glued back on', () {
      expect(splitter.splitClauses('order the cake then the flowers'), <String>[
        'order the cake then the flowers',
      ]);
    });

    test('a weekday\'s part of the day and the date after it are one', () {
      // ⚠️ "morning" counted as a time, so the rule against two times in one
      // task cut the appointment at the comma.
      for (final String utterance in <String>[
        'Dentist appointment on Thursday morning, October 15th at 10.',
        'Dinner with Anna Saturday evening, October 3rd at 8.',
        'Dentist on Thursday morning, the 15th at 10.',
      ]) {
        expect(splitter.splitClauses(utterance), <String>[
          utterance,
        ], reason: utterance);
      }
      expect(
        splitter.splitClauses('Pick up Max in the morning, Anna at 3.'),
        hasLength(2),
        reason: 'no date after the comma: two times, two tasks',
      );
    });

    test('a when said alone before a comma opens the task after it', () {
      // ⚠️ Glued onto the task before, it put "and on Friday" in that title
      // and left the glasses with the doctor's day.
      expect(
        splitter.splitClauses(
          'Tomorrow afternoon take the results to the doctor, and on Friday '
          'afternoon, pick up her glasses.',
        ),
        <String>[
          'Tomorrow afternoon take the results to the doctor',
          'on Friday afternoon, pick up her glasses.',
        ],
      );
      expect(
        splitter.splitClauses('Call Anna tomorrow, at 5, and buy milk.'),
        <String>['Call Anna tomorrow, at 5', 'buy milk.'],
        reason: 'followed by "and", the 5 is the call\'s',
      );
      expect(
        splitter.splitClauses(
          "Tomorrow is Otabek's farewell party, at 7 p.m., he is moving to "
          'Korea.',
        ),
        isNot(contains(startsWith('at 7 p.m., he'))),
        reason: "somebody else's plan after it is not a task for the 7",
      );
    });

    test('"tell Anna to …, and to …" is one errand for Anna', () {
      expect(
        splitter.splitClauses('Tell Anna to call me and to bring the keys.'),
        hasLength(1),
      );
      expect(
        splitter.splitClauses(
          'Remind me to ask Timur to call me and to send the photos.',
        ),
        hasLength(1),
      );
      expect(
        splitter.splitClauses('I need to call Anna and to send the report.'),
        hasLength(2),
        reason: "the speaker's own list is still one task per \"to\"",
      );
    });

    test('a pronoun continues a task, not a remark', () {
      expect(
        splitter.splitClauses(
          'Oh man, the car insurance ends on Monday, renew it on Saturday.',
        ),
        hasLength(2),
        reason: 'nothing before "renew it" is a task for it to repeat',
      );
    });

    test('a trip after "after work" still has its purpose after "and"', () {
      expect(
        splitter.splitClauses('After work go to Korzinka and buy eggs.'),
        hasLength(1),
      );
    });

    test('an anchor behind a preposition does not start a new task', () {
      expect(
        splitter.splitClauses('meet Ana on Friday check the agenda'),
        hasLength(1),
        reason: '"on Friday" is the tail of the first clause',
      );
    });
  });

  group('shape', () {
    test('whitespace is collapsed and the utterance is trimmed', () {
      expect(
        splitter.splitClauses('  call   mark \n and  email jane  '),
        <String>['call mark', 'email jane'],
      );
    });

    test('an empty utterance produces no clauses', () {
      expect(splitter.splitClauses(''), isEmpty);
      expect(splitter.splitClauses('   '), isEmpty);
      expect(splitter.splitClauses(' and ; then '), isEmpty);
    });

    test('a leading connective is dropped, not kept as a clause', () {
      expect(splitter.splitClauses('also call mark'), <String>['call mark']);
    });

    test('an utterance with no connective at all is one clause', () {
      expect(
        splitter.splitClauses('remind me to call Mark tomorrow at 3 PM'),
        <String>['remind me to call Mark tomorrow at 3 PM'],
      );
    });
  });

  group('the lexicon the guard shares with the date grammar', () {
    test('verbs are verbs', () {
      expect(ClauseLexicon.isImperativeVerb('call'), isTrue);
      expect(ClauseLexicon.isImperativeVerb('check'), isTrue);
      expect(ClauseLexicon.isImperativeVerb('send'), isTrue);
    });

    test('linking verbs are not, or "Sun is out" becomes a Sunday', () {
      for (final String word in <String>['is', 'was', 'are', 'am', 'be']) {
        expect(ClauseLexicon.isImperativeVerb(word), isFalse, reason: word);
      }
    });

    test('"listen" is filler only when nothing is listened to', () {
      expect(ClauseLexicon.isFillerAt('uh, listen, call the bank', 4), isTrue);
      expect(ClauseLexicon.isFillerAt('listen to the podcast', 0), isFalse);
      expect(ClauseLexicon.isFillerAt('um, call the bank', 0), isTrue);
    });

    test('nouns that double as verbs are kept out on purpose', () {
      for (final String word in <String>[
        'build',
        'release',
        'note',
        'notes',
        'report',
        'plan',
      ]) {
        expect(ClauseLexicon.isImperativeVerb(word), isFalse, reason: word);
      }
    });
  });
}
