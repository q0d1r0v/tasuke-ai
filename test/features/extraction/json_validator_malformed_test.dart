import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';

void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');
  final Map<String, Object?> fixtures = jsonDecode(
    File('test/fixtures/llm/malformed_responses.json').readAsStringSync(),
  ) as Map<String, Object?>;

  String raw(String name) => fixtures[name]! as String;

  group('wrapping the model puts around the array', () {
    test('markdown fences', () {
      for (final String name in <String>['fenced', 'fencedNoLanguage']) {
        final ValidationResult result = validator.validate(raw(name), now: now);
        expect(result.tasks, hasLength(1), reason: name);
        expect(result.tasks.single.title, 'Call Mark', reason: name);
      }
    });

    test('prose before, after, and both', () {
      for (final String name in <String>['preamble', 'postamble', 'bothEnds']) {
        final ValidationResult result = validator.validate(raw(name), now: now);
        expect(result.tasks, hasLength(1), reason: name);
        expect(result.tasks.single.date?.toIso(), '2026-09-22', reason: name);
      }
    });

    test('a bracket in the prose does not swallow the real array', () {
      final ValidationResult result = validator.validate(
        raw('proseBracketFirst'),
        now: now,
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.title, 'Call Mark');
    });

    test('an empty array survives its fences', () {
      expect(
        validator.validate(raw('emptyArrayFenced'), now: now).isRejected,
        isFalse,
      );
      expect(
        validator.validate(raw('emptyArrayFenced'), now: now).tasks,
        isEmpty,
      );
    });
  });

  group('broken JSON', () {
    test('a trailing comma is repaired, because a cut-off model emits one', () {
      final ValidationResult result = validator.validate(
        raw('trailingComma'),
        now: now,
      );
      expect(result.tasks, hasLength(1));
    });

    test('single quotes are not JSON and are not guessed at', () {
      final ValidationResult result = validator.validate(
        raw('singleQuoted'),
        now: now,
      );
      expect(result.isRejected, isTrue);
      expect(result.tasks, isEmpty);
    });

    test('no JSON at all is rejected with a reason', () {
      for (final String name in <String>['noJson', 'empty', 'whitespace']) {
        final ValidationResult result = validator.validate(raw(name), now: now);
        expect(result.rejection, ValidationRejection.noJsonFound, reason: name);
        expect(result.reason, isNotNull, reason: name);
      }
    });

    test('the rejection reason never quotes the model back', () {
      // ⚠️ jsonDecode's own FormatException embeds the source. That source is
      // the user's transcript, and this string reaches the log.
      final ValidationResult result = validator.validate(
        '[{"title": "meet Dr Ahmedov about the biopsy"',
        now: now,
      );
      expect(result.reason, isNotNull);
      expect(result.reason, isNot(contains('biopsy')));
      expect(result.reason, isNot(contains('Ahmedov')));
    });
  });

  group('nothing throws, whatever arrives', () {
    test('every fixture', () {
      for (final MapEntry<String, Object?> entry in fixtures.entries) {
        if (entry.value is! String) continue;
        expect(
          () => validator.validate(entry.value! as String, now: now),
          returnsNormally,
          reason: entry.key,
        );
      }
    });

    test('hostile shapes', () {
      for (final String input in <String>[
        '[[[[[[[[[[',
        '{{{{{{{{{{',
        '[{"title": ',
        '"',
        '\\',
        '[,,,,]',
        '[null, null]',
        '[[]]',
        '[{}]',
        '\u0000\u0001\u0002',
        '[{"title": "\\u"}]',
        '[{"title": 3.14}]',
      ]) {
        expect(
          () => validator.validate(input, now: now),
          returnsNormally,
          reason: input,
        );
      }
    });

    test('a deeply nested payload does not blow the stack', () {
      final String deep = '${'[' * 2000}${']' * 2000}';
      expect(() => validator.validate(deep, now: now), returnsNormally);
    });
  });
}
