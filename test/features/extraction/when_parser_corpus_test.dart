import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

/// The table every future date bug lands in as one line.
///
/// A fixture file rather than a Dart list on purpose: a failing phrase from a
/// real transcript can be pasted in by anyone, including by whoever is holding
/// the phone, without touching the parser or recompiling anything.
void main() {
  const WhenParser parser = WhenParser();
  final List<Object?> corpus = jsonDecode(
    File('test/fixtures/nl/datetime_corpus.json').readAsStringSync(),
  ) as List<Object?>;

  test('the corpus is big enough to be worth having', () {
    expect(corpus.length, greaterThanOrEqualTo(150));
  });

  group('datetime corpus', () {
    for (final Object? entry in corpus) {
      final Map<String, Object?> row = entry! as Map<String, Object?>;
      final String phrase = row['phrase']! as String;
      final String nowIso = row['now']! as String;
      final String? expectDate = row['expectDate'] as String?;
      final String? expectTime = row['expectTime'] as String?;
      final String note = row['note'] as String? ?? '';

      test('"$phrase" at $nowIso — $note', () {
        final ParsedWhen parsed = parser.parse(
          phrase,
          now: LocalDateTime.parseIso(nowIso),
        );
        expect(
          parsed.date?.toIso(),
          expectDate,
          reason: 'date of "$phrase" at $nowIso',
        );
        expect(
          parsed.time?.toIso(),
          expectTime,
          reason: 'time of "$phrase" at $nowIso',
        );
        if (expectDate == null && expectTime == null) {
          expect(
            parsed.isEmpty,
            isTrue,
            reason: '"$phrase" must parse to nothing at all',
          );
          expect(
            parsed.matchStart,
            parsed.matchEnd,
            reason: '"$phrase" must not eat any of the title',
          );
        }
      });
    }
  });
}
