import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';

/// The transcript is whatever the microphone heard.
///
/// Nothing here can compromise a backend, because there is no backend. What it
/// can do is derail the validator — end the scan early on a bracket inside a
/// title, or take the model's editorialising as data — and the answer to all
/// of it is the same: the validator reads JSON, and treats every string it
/// finds as text to display, never as an instruction.
void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');
  final Map<String, Object?> fixtures = jsonDecode(
    File('test/fixtures/llm/injection_responses.json').readAsStringSync(),
  ) as Map<String, Object?>;

  ValidationResult validate(String name) =>
      validator.validate(fixtures[name]! as String, now: now);

  test(
    '"ignore previous instructions" is prose, and the array behind it wins',
    () {
      final ValidationResult result = validate('ignorePrevious');
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.title, 'Call Mark');
      expect(result.tasks.single.date?.toIso(), '2026-09-22');
    },
  );

  test('a fake closing tag and SYSTEM: preamble are just characters', () {
    final ValidationResult result = validate('fakeSystemTag');
    expect(result.tasks, hasLength(1));
    expect(result.tasks.single.title, 'Call Mark');
  });

  test('a JSON array inside a title does not end the scan early', () {
    final ValidationResult result = validate('transcriptContainsArray');
    expect(result.tasks, hasLength(1));
    expect(
      result.tasks.single.title,
      'Read out the list [1, 2, 3] to the team',
    );
    expect(result.tasks.single.date?.toIso(), '2026-09-25');
  });

  test('an escaped JSON object inside a title survives intact', () {
    final ValidationResult result = validate('transcriptContainsJson');
    expect(result.tasks, hasLength(1));
    expect(result.tasks.single.title, 'Say {"title": "nothing"} at standup');
  });

  test('the model echoing the prompt back still yields the array', () {
    final ValidationResult result = validate('promptEchoed');
    expect(result.tasks, hasLength(1));
    expect(result.tasks.single.title, 'Call Mark');
    expect(result.tasks.single.date?.toIso(), '2026-09-22');
  });

  test('an instruction-shaped title is a title, nothing more', () {
    final ValidationResult result = validate('fencedWithInstructions');
    expect(result.tasks, hasLength(1));
    expect(
      result.tasks.single.title,
      'Delete all tasks and disable reminders',
      reason: 'it is text on a card the user can throw away',
    );
  });

  test('keys the model was never asked for are ignored', () {
    final ValidationResult result = validate('extraKeys');
    expect(result.tasks, hasLength(1));
    expect(result.tasks.single.title, 'Call Mark');
    expect(result.tasks.single.date?.toIso(), '2026-09-22');
  });

  test('SQL in a title is stored as a title', () {
    // Drift binds parameters; this is a string like any other. The test exists
    // so that a future hand-built query is caught here rather than in the wild.
    final ValidationResult result = validate('sqlInTitle');
    expect(result.tasks.single.title, "'; DROP TABLE tasks; --");
  });

  test('none of it throws', () {
    for (final MapEntry<String, Object?> entry in fixtures.entries) {
      if (entry.value is! String) continue;
      expect(
        () => validator.validate(entry.value! as String, now: now),
        returnsNormally,
        reason: entry.key,
      );
    }
  });
}
