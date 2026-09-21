import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';

/// Inference runs to a token budget on a phone, and the budget runs out
/// wherever it runs out. This is the cheapest test in the project and it covers
/// the entire class: cut a known-good payload at every single character and
/// assert that none of the cuts throws.
void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');
  final String happy = File('test/fixtures/llm/happy_three_tasks.json')
      .readAsStringSync();
  final Map<String, Object?> fixtures = jsonDecode(
    File('test/fixtures/llm/malformed_responses.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('every prefix of a good payload is handled', () {
    for (int i = 0; i <= happy.length; i++) {
      final String cut = happy.substring(0, i);
      expect(
        () => validator.validate(cut, now: now),
        returnsNormally,
        reason: 'cut at $i characters',
      );
    }
  });

  test('every prefix of a fenced payload is handled', () {
    final String fenced = fixtures['fenced']! as String;
    for (int i = 0; i <= fenced.length; i++) {
      expect(
        () => validator.validate(fenced.substring(0, i), now: now),
        returnsNormally,
        reason: 'cut at $i characters',
      );
    }
  });

  test(
    'every prefix is either a rejection or tasks, never a half-built one',
    () {
      for (int i = 0; i <= happy.length; i++) {
        final ValidationResult result = validator.validate(
          happy.substring(0, i),
          now: now,
        );
        if (result.isRejected) {
          expect(result.tasks, isEmpty, reason: 'cut at $i');
        } else {
          for (final Object? task in result.tasks) {
            expect(task, isNotNull, reason: 'cut at $i');
          }
        }
      }
    },
  );

  test('the tasks that did arrive before the cut are kept', () {
    // ⚠️ Not just "does not throw": two complete tasks followed by half of a
    // third is two tasks, not a failed capture. This is the difference between
    // the user losing a sentence and the user losing their whole utterance.
    final ValidationResult result = validator.validate(
      fixtures['salvageable']! as String,
      now: now,
    );
    expect(result.tasks, hasLength(1));
    expect(result.tasks.single.title, 'Call Mark');
    expect(result.tasks.single.date?.toIso(), '2026-09-22');
  });

  test('an unclosed object keeps the keys that made it through', () {
    final ValidationResult result = validator.validate(
      fixtures['unclosedObject']! as String,
      now: now,
    );
    expect(result.isRejected || result.tasks.isNotEmpty, isTrue);
  });

  test('an unclosed string is a rejection, not an exception', () {
    final ValidationResult result = validator.validate(
      fixtures['unclosedString']! as String,
      now: now,
    );
    expect(result.isRejected, isTrue);
    expect(result.tasks, isEmpty);
  });

  test('truncation inside a multi-byte character is handled', () {
    const String payload =
        '[{"title": "Позвонить Марку", "when_text": "tomorrow"}]';
    for (int i = 0; i <= payload.length; i++) {
      expect(
        () => validator.validate(payload.substring(0, i), now: now),
        returnsNormally,
        reason: 'cut at $i',
      );
    }
  });
}
