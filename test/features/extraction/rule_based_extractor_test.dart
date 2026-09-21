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
