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
