import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';

/// A 1B model quantised to four bits will happily date a task to the year 3000.
///
/// The rule throughout: a date that fails the range check is dropped, and the
/// task is kept. The user said something; losing the date costs them a tap,
/// losing the task costs them the thing they wanted to remember.
void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');

  ValidationResult validate(String raw) => validator.validate(raw, now: now);

  group('dates outside the plausible range', () {
    test('the limits this file is built on', () {
      expect(ExtractionDefaults.maxFutureDays, 3650);
      expect(ExtractionDefaults.maxPastDays, 1);
    });

    test('a date far in the future is dropped and the task kept', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "date": "3000-01-01"}]',
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.title, 'Call Mark');
      expect(result.tasks.single.date, isNull);
      expect(result.tasks.single.confidence, Confidence.low);
    });

    test('a date far in the past is dropped and the task kept', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "date": "1999-12-31"}]',
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.date, isNull);
      expect(result.tasks.single.confidence, Confidence.low);
    });

    test('yesterday survives, because an overdue task is a real task', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": "yesterday"}]',
      );
      expect(result.tasks.single.date?.toIso(), '2026-09-20');
    });

    test('the day before yesterday does not', () {
      // maxPastDays is 1. Two days back is the model inventing history.
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": "the day before yesterday"}]',
      );
      expect(result.tasks.single.date, isNull);
      expect(result.tasks.single.confidence, Confidence.low);
    });

    test(
      '"last friday" from the parser is out of range and drops its date',
      () {
        final ValidationResult result = validate(
          '[{"title": "Call Mark", "when_text": "last friday"}]',
        );
        expect(result.tasks, hasLength(1));
        expect(result.tasks.single.date, isNull);
        expect(result.tasks.single.confidence, Confidence.low);
      },
    );

    test('the boundaries themselves', () {
      final String lastGoodDay = now.date
          .addDays(ExtractionDefaults.maxFutureDays)
          .toIso();
      final String firstBadDay = now.date
          .addDays(ExtractionDefaults.maxFutureDays + 1)
          .toIso();
      expect(
        validate('[{"title": "t", "date": "$lastGoodDay"}]').tasks.single.date
            ?.toIso(),
        lastGoodDay,
      );
      expect(
        validate('[{"title": "t", "date": "$firstBadDay"}]').tasks.single.date,
        isNull,
      );
    });

    test('the time goes with the date it belonged to', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": "3000-01-01 at 3pm"}]',
      );
      expect(result.tasks.single.date, isNull);
      expect(
        result.tasks.single.time,
        isNull,
        reason: 'a time without the date it was attached to is a wrong alarm',
      );
    });
  });

  group('other ways a model invents', () {
    test('a flood of tasks is capped, not rendered', () {
      final StringBuffer flood = StringBuffer('[');
      for (int i = 0; i < 200; i++) {
        if (i > 0) flood.write(',');
        flood.write('{"title": "Task $i", "when_text": "tomorrow"}');
      }
      flood.write(']');
      expect(
        validate(flood.toString()).tasks,
        hasLength(ExtractionDefaults.maxTasksPerCapture),
      );
    });

    test('a duplicated task is not the validator’s problem to solve', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark"}, {"title": "Call Mark"}]',
      );
      expect(
        result.tasks,
        hasLength(2),
        reason:
            'the Confirm screen is where a duplicate gets thrown away, '
            'and only the user can tell a duplicate from a repeat',
      );
    });

    test('an essay as a title is clamped, not rejected', () {
      final String essay = 'Call Mark about ${'the quarterly numbers ' * 40}';
      final ValidationResult result = validate('[{"title": "$essay"}]');
      expect(result.tasks.single.title.length, lessThanOrEqualTo(200));
      expect(result.tasks.single.title, startsWith('Call Mark about'));
    });
  });
}
