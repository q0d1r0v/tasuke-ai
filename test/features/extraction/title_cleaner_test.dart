import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/title_cleaner.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

void main() {
  const TitleCleaner cleaner = TitleCleaner();
  const WhenParser parser = WhenParser();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');

  /// What the pipeline actually does: parse, then cut what the parser claimed.
  String titleOf(String clause) {
    final ParsedWhen parsed = parser.parse(clause, now: now);
    return cleaner.clean(
      clause,
      matchStart: parsed.matchStart,
      matchEnd: parsed.matchEnd,
      spans: parsed.spans,
    );
  }

  group('cutting the temporal span', () {
    test('the spec example', () {
      expect(
        titleOf('Tomorrow at 3 PM send the build to James'),
        'Send the build to James',
      );
    });

    test('the cut works at either end and in the middle', () {
      expect(
        titleOf('send the build to James tomorrow'),
        'Send the build to James',
      );
      expect(titleOf('on Friday call the vet'), 'Call the vet');
      expect(
        titleOf('Friday check App Store at 3pm'),
        'Check App Store',
        reason: 'two spans with the whole title between them',
      );
    });

    test('an explicit span is cut even without the parser', () {
      expect(
        cleaner.clean('tomorrow send the build', matchStart: 0, matchEnd: 8),
        'Send the build',
      );
    });

    test('a span outside the string does not throw', () {
      expect(
        cleaner.clean('call Mark', matchStart: 40, matchEnd: 90),
        'Call Mark',
      );
      expect(
        cleaner.clean('call Mark', matchStart: 5, matchEnd: 2),
        'Call Mark',
      );
    });
  });

  group('fillers', () {
    test('the ones people open with', () {
      expect(titleOf('remind me to call Mark'), 'Call Mark');
      expect(titleOf('remind me call Mark'), 'Call Mark');
      expect(titleOf('i need to call Mark'), 'Call Mark');
      expect(titleOf('i have to call Mark'), 'Call Mark');
      expect(titleOf("don't forget to call Mark"), 'Call Mark');
      expect(titleOf('don’t forget to call Mark'), 'Call Mark');
      expect(titleOf('make sure to call Mark'), 'Call Mark');
      expect(titleOf('i should call Mark'), 'Call Mark');
      expect(titleOf('please call Mark'), 'Call Mark');
    });

    test('stacked fillers are all removed', () {
      expect(titleOf('please remind me to call Mark'), 'Call Mark');
      expect(titleOf("Tomorrow please don't forget to call Mark"), 'Call Mark');
    });

    test('a filler in the middle of the title is left alone', () {
      expect(
        titleOf('ask Ana to remind me about the keys'),
        'Ask Ana to remind me about the keys',
      );
    });
  });

  group('tidying', () {
    test('a preposition left dangling by the cut is dropped', () {
      expect(titleOf('pay the rent by friday'), 'Pay the rent');
      expect(titleOf('call the vet on monday'), 'Call the vet');
      expect(titleOf('move the meeting to tomorrow'), 'Move the meeting');
    });

    test('whitespace is collapsed and a trailing period removed', () {
      expect(titleOf('  buy   milk  .'), 'Buy milk');
      expect(titleOf('buy milk,'), 'Buy milk');
    });

    test('the first letter is raised and the rest is left alone', () {
      expect(titleOf('send the build to James'), 'Send the build to James');
      expect(titleOf('eMail the PDF to HR'), 'EMail the PDF to HR');
      expect(titleOf('Call Mark'), 'Call Mark');
    });

    test('a title that is nothing but a date comes back empty', () {
      expect(titleOf('tomorrow at 3 PM'), '');
      expect(cleaner.clean('please', matchStart: 0, matchEnd: 0), '');
    });

    test('a non-ASCII first character is not mangled', () {
      expect(
        cleaner.clean('позвонить Марку', matchStart: 0, matchEnd: 0),
        'Позвонить Марку',
      );
      expect(
        cleaner.clean('🎉 buy the cake', matchStart: 0, matchEnd: 0),
        '🎉 buy the cake',
      );
    });
  });

  group('contracts the rest of the pipeline relies on', () {
    test('clean is idempotent', () {
      for (final String clause in <String>[
        'Tomorrow at 3 PM send the build to James',
        'remind me to call Mark',
        'please, buy milk.',
        'call the vet on monday',
        '',
        '🎉 buy the cake',
        'позвонить Марку',
      ]) {
        final String once = titleOf(clause);
        final String twice = cleaner.clean(once, matchStart: 0, matchEnd: 0);
        expect(twice, once, reason: clause);
      }
    });

    test('the result is clamped to a storable title', () {
      final String long = 'call ${'Mark ' * 200}';
      final String title = cleaner.clean(long, matchStart: 0, matchEnd: 0);
      expect(title.length, lessThanOrEqualTo(Task.maxTitleLength));
      expect(title, TaskTitle.normalise(title));
    });
  });
}
