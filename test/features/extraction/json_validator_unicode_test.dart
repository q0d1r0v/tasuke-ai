import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

/// Titles are whatever language the user speaks, plus whatever the keyboard
/// they retype them on produces.
void main() {
  const ExtractionJsonValidator validator = ExtractionJsonValidator();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-21T10:00');
  final String unicodePayload = File('test/fixtures/llm/unicode_titles.json')
      .readAsStringSync();

  /// A family: four people joined by three zero-width joiners. Eleven UTF-16
  /// code units that mean one character to the person reading them.
  const String family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';

  bool hasLoneSurrogate(String text) {
    for (int i = 0; i < text.length; i++) {
      final int unit = text.codeUnitAt(i);
      final bool isHigh = unit >= 0xD800 && unit <= 0xDBFF;
      final bool isLow = unit >= 0xDC00 && unit <= 0xDFFF;
      if (isHigh) {
        if (i + 1 >= text.length) return true;
        final int next = text.codeUnitAt(i + 1);
        if (next < 0xDC00 || next > 0xDFFF) return true;
        i++;
      } else if (isLow) {
        return true;
      }
    }
    return false;
  }

  test('the fixture comes back with every title intact', () {
    final ValidationResult result = validator.validate(
      unicodePayload,
      now: now,
    );
    expect(result.tasks, hasLength(5));
    expect(
      result.tasks[0].title,
      'Bugun kechqurun Zuhra’ga qo’ng’iroq qilish',
      reason: 'the Uzbek apostrophe is U+2019 and is part of the word',
    );
    expect(result.tasks[1].title, 'Позвонить Марку завтра');
    expect(result.tasks[2].title, 'اتصل بمارك غداً');
    expect(result.tasks[3].title, '明日の午後3時にビルドを送る');
    expect(result.tasks[4].title, contains(family));
  });

  test('a non-English title still gets its English when_text resolved', () {
    final ValidationResult result = validator.validate(
      unicodePayload,
      now: now,
    );
    expect(result.tasks[1].date?.toIso(), '2026-09-22');
    expect(result.tasks[3].time?.toIso(), '15:00');
    expect(result.tasks[0].time?.toIso(), '20:00');
  });

  test('U+2019 in a title is not confused with the one in a contraction', () {
    // ⚠️ The parser folds U+2019 to a straight quote so that "o’clock" matches,
    // and that fold must never reach the title.
    final ValidationResult result = validator.validate(
      '[{"title": "Qo’ng’iroq", "when_text": "at 3 o’clock"}]',
      now: now,
    );
    expect(result.tasks.single.title, 'Qo’ng’iroq');
    expect(result.tasks.single.time?.toIso(), '15:00');
  });

  test('right-to-left text is stored exactly as it arrived', () {
    final ValidationResult result = validator.validate(
      '[{"title": "اتصل بمارك ‏ غداً"}]',
      now: now,
    );
    expect(result.tasks.single.title, contains('‏'));
  });

  test('a ZWJ sequence inside the limit survives whole', () {
    final ValidationResult result = validator.validate(
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'title': 'Book the $family photo session'},
      ]),
      now: now,
    );
    expect(result.tasks.single.title, 'Book the $family photo session');
    expect(result.tasks.single.title, contains(family));
  });

  test('truncation never leaves half a character behind', () {
    // Walk the family across the truncation boundary one character at a time.
    // Whatever falls off the end, what is left must still be valid UTF-16 —
    // a lone surrogate renders as a replacement box, and the user typed none.
    for (int pad = 180; pad < 210; pad++) {
      final String title = '${'a' * pad}$family tail';
      final ValidationResult result = validator.validate(
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'title': title},
        ]),
        now: now,
      );
      final ExtractedTask task = result.tasks.single;
      expect(
        task.title.length,
        lessThanOrEqualTo(Task.maxTitleLength),
        reason: 'pad $pad',
      );
      expect(
        hasLoneSurrogate(task.title),
        isFalse,
        reason: 'pad $pad left half a surrogate pair',
      );
    }
  });

  test('exotic whitespace and control characters do not break the decode', () {
    for (final String title in <String>[
      'Call Mark',
      'Call Mark',
      'Call​Mark',
      'Call\tMark',
      'Call\u0000Mark',
    ]) {
      final String raw = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'title': title},
      ]);
      expect(() => validator.validate(raw, now: now), returnsNormally);
      expect(validator.validate(raw, now: now).tasks, hasLength(1));
    }
  });

  test('a title that is only emoji is still a title', () {
    final ValidationResult result = validator.validate(
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'title': family},
      ]),
      now: now,
    );
    expect(result.tasks.single.title, family);
  });
}
