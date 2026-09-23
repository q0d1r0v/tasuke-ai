import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/non_task.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';

/// How people actually talk into the app, one rule per test.
///
/// Every case here came from a real capture or from the labelled corpora, and
/// each one names the rule that handles it, so a failure says which rule
/// broke rather than only that a score went down.
void main() {
  // Monday 21 September 2026, 10:00.
  const LocalDateTime now = LocalDateTime(
    LocalDate(2026, 9, 21),
    LocalTimeOfDay.hm(10, 0),
  );

  Future<List<ExtractedTask>> extract(String note) =>
      const RuleBasedTaskExtractor().extract(note, now: now);

  List<String> titles(List<ExtractedTask> tasks) =>
      tasks.map((ExtractedTask t) => t.title).toList();

  group('not a task', () {
    for (final String note in <String>[
      'Hello, how are you?',
      'Thank you.',
      "Let's go.",
      'I have some tasks for today.',
      'Okay, so I have a few tasks for today, let me think.',
      "Thank you, that's all for now.",
      'Testing, testing, one, two, three.',
      'Is this thing working?',
      'The weather is really nice today.',
      "I'm on the bus right now and it's really crowded.",
      'Have a nice day.',
    ]) {
      test('"$note"', () async => expect(await extract(note), isEmpty));
    }

    test('a meeting is not narration, even in the progressive', () async {
      final List<ExtractedTask> tasks = await extract(
        "I'm meeting Sardor at 5.",
      );
      expect(tasks, hasLength(1));
      expect(tasks.single.time, LocalTimeOfDay.hm(17, 0));
    });

    test('NonTask does not swallow real tasks', () {
      for (final String task in <String>[
        'Thank Aziz for the gift',
        'Call Anna',
        'Buy milk',
        'Meeting with Sardor',
        'Go to the gym',
      ]) {
        expect(NonTask.isNonTask(task), isFalse, reason: task);
      }
    });
  });

  group('where one task ends and the next begins', () {
    test('a full stop', () async {
      expect(
        titles(await extract('I have some tasks. Call Anna. Buy milk.')),
        <String>['Call Anna', 'Buy milk'],
      );
    });

    test('a comma before a new verb, but not inside a list', () async {
      expect(
        titles(
          await extract(
            'Check my email, reply to Aziz, and buy eggs, milk and bread.',
          ),
        ),
        <String>['Check my email', 'Reply to Aziz', 'Buy eggs, milk and bread'],
      );
    });

    test('first, second, third', () async {
      expect(
        titles(
          await extract(
            'Okay, so first I need to finish the presentation, second I need '
            'to print it, and third bring it to the office tomorrow.',
          ),
        ),
        <String>[
          'Finish the presentation',
          'Print it',
          'Bring it to the office',
        ],
      );
    });

    test('"go to <place> and <do>" is one errand', () async {
      expect(
        titles(await extract('Tomorrow go to the bazaar and buy meat.')),
        <String>['Go to the bazaar and buy meat'],
      );
    });

    test('an event noun starts a task without a verb', () async {
      final List<ExtractedTask> tasks = await extract(
        'Tomorrow at 9 the bank, then at twelve lunch with Dilnoza.',
      );
      expect(titles(tasks).last, 'Lunch with Dilnoza');
    });

    test('"and remind me" belongs to the task before it', () async {
      final List<ExtractedTask> tasks = await extract(
        'Send the invoice by Friday and remind me on Thursday evening.',
      );
      expect(tasks, hasLength(1));
      expect(tasks.single.hasReminder, isTrue);
    });

    test('a sentence said twice is one task', () async {
      expect(
        await extract('Call the dentist tomorrow. Call the dentist tomorrow.'),
        hasLength(1),
      );
    });
  });

  group('titles', () {
    test('filler, modal and subject are not part of the title', () async {
      expect(
        titles(await extract('So, um, I also need to call my brother.')),
        <String>['Call my brother'],
      );
      expect(titles(await extract('I go to the market.')), <String>[
        'Go to the market',
      ]);
      expect(
        titles(await extract('Tomorrow I have a meeting with Sardor at 10.')),
        <String>['Meeting with Sardor'],
      );
    });

    test(
      '"…, it\'s due on the 25th" leaves the task, not the remnant',
      () async {
        final List<ExtractedTask> tasks = await extract(
          "Pay the internet bill, it's due on the 25th.",
        );
        expect(titles(tasks), <String>['Pay the internet bill']);
        expect(tasks.single.date, const LocalDate(2026, 9, 25));
      },
    );
  });

  group('when', () {
    test('spelled-out hours', () async {
      expect(
        (await extract('Go to the gym at six.')).single.time,
        LocalTimeOfDay.hm(18, 0),
      );
      expect(
        (await extract('Call Anna at nine thirty.')).single.time,
        LocalTimeOfDay.hm(9, 30),
      );
    });

    test('"at one point" is not one o\'clock', () async {
      expect(
        (await extract('At one point call the bank.')).single.time,
        isNull,
      );
    });

    test('ordinal dates in words', () async {
      expect(
        (await extract('Pay rent on the first of October.')).single.date,
        const LocalDate(2026, 10, 1),
      );
      expect(
        (await extract('I may first call him.')).single.date,
        isNull,
        reason: '"may first" is not May 1',
      );
    });

    test('a time at the very end of the note', () async {
      expect(
        (await extract('Call May from accounting tomorrow at 9.30.'))
            .single
            .time,
        LocalTimeOfDay.hm(9, 30),
      );
    });

    test('tonight at 8.45 is the evening', () async {
      expect(
        (await extract('Pick up Anna from the airport tonight at 8.45.'))
            .single
            .time,
        LocalTimeOfDay.hm(20, 45),
      );
    });

    test('a later time with no day of its own keeps the day said', () async {
      final List<ExtractedTask> tasks = await extract(
        'Tomorrow morning at nine go to the bank, then at twelve lunch with '
        'Dilnoza, and in the evening prepare the visa documents.',
      );
      expect(tasks.map((ExtractedTask t) => t.date).toSet(), <LocalDate>{
        const LocalDate(2026, 9, 22),
      });
      expect(tasks.map((ExtractedTask t) => t.time).toList(), <LocalTimeOfDay>[
        LocalTimeOfDay.hm(9, 0),
        LocalTimeOfDay.hm(12, 0),
        LocalTimeOfDay.hm(18, 0),
      ]);
    });

    test('an undated task does not borrow a neighbour\'s day', () async {
      // Across a full stop, the bill has no day…
      final List<ExtractedTask> apart = await extract(
        'Call my mom tonight. Pay the electricity bill.',
      );
      expect(apart.last.date, isNull);
      // …and joined with "and", it has the day of the call but not its hour.
      final List<ExtractedTask> joined = await extract(
        'Call my mom tonight and pay the electricity bill.',
      );
      expect(joined.last.date, const LocalDate(2026, 9, 21));
      expect(joined.last.time, isNull);
    });

    test('a heading gives its day to the list under it', () async {
      final List<ExtractedTask> tasks = await extract(
        'Okay, for Saturday. Order the balloons, pick up the cake at 11, and '
        'call the grandparents.',
      );
      expect(tasks, hasLength(3));
      for (final ExtractedTask task in tasks) {
        expect(task.date, const LocalDate(2026, 9, 26), reason: task.title);
      }
    });

    test('a note that is only a when is still a task to rename', () async {
      final List<ExtractedTask> tasks = await extract('tomorrow at 3 PM');
      expect(tasks, hasLength(1));
      expect(tasks.single.time, LocalTimeOfDay.hm(15, 0));
    });
  });
}
