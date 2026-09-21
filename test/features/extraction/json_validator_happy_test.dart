import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';

void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');
  final String happy = File('test/fixtures/llm/happy_three_tasks.json')
      .readAsStringSync();

  group('a well-behaved response', () {
    test('every task comes through, with the parser resolving when_text', () {
      final ValidationResult result = validator.validate(happy, now: now);
      expect(result.isRejected, isFalse);
      expect(result.tasks, hasLength(3));

      final ExtractedTask first = result.tasks[0];
      expect(first.title, 'Send the build to James');
      expect(first.date?.toIso(), '2026-09-22');
      expect(first.time?.toIso(), '15:00');
      expect(first.hasReminder, isTrue);
      expect(first.confidence, Confidence.high);
      expect(first.whenText, 'tomorrow at 3 PM');

      expect(result.tasks[1].date?.toIso(), '2026-09-25');
      expect(result.tasks[1].time, isNull);
      expect(result.tasks[1].hasReminder, isFalse);

      expect(result.tasks[2].title, 'Call the dentist');
      expect(result.tasks[2].date, isNull);
      expect(result.tasks[2].whenText, isNull);
    });

    test('an empty array is a valid answer, not an error', () {
      final ValidationResult result = validator.validate('[]', now: now);
      expect(result.isRejected, isFalse);
      expect(result.tasks, isEmpty);
    });

    test('a bare object is taken as a one-element array', () {
      final ValidationResult result = validator.validate(
        '{"title": "Call Mark", "when_text": "tomorrow"}',
        now: now,
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.date?.toIso(), '2026-09-22');
    });

    test('has_reminder is coerced from everything a model emits for yes', () {
      for (final String raw in <String>[
        'true',
        '"true"',
        '"True"',
        '"yes"',
        '1',
        '"1"',
      ]) {
        final ValidationResult result = validator.validate(
          '[{"title": "Call Mark", "has_reminder": $raw}]',
          now: now,
        );
        expect(result.tasks.single.hasReminder, isTrue, reason: raw);
      }
      for (final String raw in <String>[
        'false',
        '"false"',
        '0',
        'null',
        '"maybe"',
        '[]',
      ]) {
        final ValidationResult result = validator.validate(
          '[{"title": "Call Mark", "has_reminder": $raw}]',
          now: now,
        );
        expect(result.tasks.single.hasReminder, isFalse, reason: raw);
      }
      expect(
        validator
            .validate('[{"title": "Call Mark"}]', now: now)
            .tasks
            .single
            .hasReminder,
        isFalse,
        reason: 'a missing key defaults to no reminder',
      );
    });

    test('unknown keys are ignored rather than rejected', () {
      final ValidationResult result = validator.validate(
        '[{"title": "Call Mark", "priority": "high", "tags": ["a"], '
        '"when_text": "tomorrow"}]',
        now: now,
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.date?.toIso(), '2026-09-22');
    });

    test('the list is capped rather than rendered', () {
      final String flood = jsonEncode(
        List<Map<String, Object?>>.generate(
          ExtractionDefaults.maxTasksPerCapture + 25,
          (int i) => <String, Object?>{'title': 'Task $i'},
        ),
      );
      expect(
        validator.validate(flood, now: now).tasks,
        hasLength(ExtractionDefaults.maxTasksPerCapture),
      );
    });

    test('titles are clamped the same way a typed title is', () {
      final String long = 'a' * 500;
      final ValidationResult result = validator.validate(
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'title': long},
        ]),
        now: now,
      );
      expect(result.tasks.single.title.length, 200);
    });

    test('whitespace in a title is collapsed', () {
      final ValidationResult result = validator.validate(
        '[{"title": "  Call   Mark\\n"}]',
        now: now,
      );
      expect(result.tasks.single.title, 'Call Mark');
    });
  });
}
