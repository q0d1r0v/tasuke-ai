import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';

/// What happens when the JSON decodes perfectly and means nothing.
void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');
  final Map<String, Object?> fixtures = jsonDecode(
    File('test/fixtures/llm/malformed_responses.json').readAsStringSync(),
  ) as Map<String, Object?>;

  ValidationResult validate(String raw) => validator.validate(raw, now: now);

  group('the wrong top-level shape', () {
    test('a number or a string is not an array of tasks', () {
      expect(validate(fixtures['notAList']! as String).isRejected, isTrue);
      expect(validate(fixtures['stringOnly']! as String).isRejected, isTrue);
    });

    test('a null literal is no JSON at all', () {
      expect(
        validate(fixtures['nullLiteral']! as String).rejection,
        ValidationRejection.noJsonFound,
      );
    });

    test('an array wrapped in an object is still the array', () {
      // {"tasks": [...]} is what a model does when it decides the schema needed
      // a name. The array inside it is the answer, not the wrapper.
      final ValidationResult result = validate(
        fixtures['nestedWrapper']! as String,
      );
      expect(result.isRejected, isFalse);
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.title, 'Call Mark');
    });

    test('a bare value inside the array is skipped, the rest is kept', () {
      final ValidationResult result = validate(
        '[42, "call Mark", null, true, {"title": "Call Mark"}]',
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.title, 'Call Mark');
    });
  });

  group('rows the array should not have contained', () {
    test('a missing, empty or non-string title drops the row', () {
      final ValidationResult result = validate(
        '[{"when_text": "tomorrow"},'
        ' {"title": ""},'
        ' {"title": "   "},'
        ' {"title": null},'
        ' {"title": 7},'
        ' {"title": ["Call Mark"]},'
        ' {"title": {"text": "Call Mark"}},'
        ' {"title": "Call Mark"}]',
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.title, 'Call Mark');
    });

    test('a when_text of the wrong type is ignored, the task is kept', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": 3}]',
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.date, isNull);
      expect(result.tasks.single.whenText, isNull);
    });

    test('an unparseable when_text keeps the task and lowers confidence', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": "sometime soonish"}]',
      );
      expect(result.tasks.single.date, isNull);
      expect(result.tasks.single.confidence.name, 'low');
      expect(
        result.tasks.single.whenText,
        'sometime soonish',
        reason:
            'the phrase is kept so the failing case can be pasted into the '
            'corpus',
      );
    });

    test('an empty when_text is not a failure to parse', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": ""}]',
      );
      expect(result.tasks.single.confidence.name, 'high');
    });
  });

  group('the parser outranks the model', () {
    test('when both speak, the parser wins', () {
      // The model is asked for the words, never for the arithmetic: it is the
      // one part of this pipeline that cannot be tested at a hundred cases a
      // second.
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": "tomorrow at 3 PM", '
        '"date": "2027-01-01", "time": "08:00"}]',
      );
      expect(result.tasks.single.date?.toIso(), '2026-09-22');
      expect(result.tasks.single.time?.toIso(), '15:00');
      expect(result.tasks.single.confidence.name, 'high');
    });

    test('the model is the fallback when the phrase could not be read', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "when_text": "when the shipment clears customs", '
        '"date": "2026-12-13", "time": "10:30"}]',
      );
      expect(result.tasks.single.date?.toIso(), '2026-12-13');
      expect(result.tasks.single.time?.toIso(), '10:30');
      expect(
        result.tasks.single.confidence.name,
        'low',
        reason: 'a date nobody checked is a date the user should look at',
      );
    });

    test('a malformed model date is ignored rather than thrown on', () {
      for (final String date in <String>[
        '"2026-13-01"',
        '"2026-02-30"',
        '"tomorrow"',
        '""',
        '7',
        'null',
        '{"y": 2026}',
      ]) {
        final ValidationResult result = validate(
          '[{"title": "Call Mark", "date": $date}]',
        );
        expect(result.tasks, hasLength(1), reason: date);
        expect(result.tasks.single.date, isNull, reason: date);
      }
    });

    test('a model time without a model date is not used on its own', () {
      final ValidationResult result = validate(
        '[{"title": "Call Mark", "time": "10:30"}]',
      );
      expect(result.tasks.single.date, isNull);
      expect(result.tasks.single.time, isNull);
    });
  });
}
