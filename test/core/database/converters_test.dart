import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';

void main() {
  group('LocalDateConverter', () {
    const LocalDateConverter converter = LocalDateConverter();

    test('round-trips through the stored representation', () {
      const LocalDate date = LocalDate(2026, 3, 11);
      expect(converter.toSql(date), '2026-03-11');
      expect(converter.fromSql('2026-03-11'), date);
    });

    test('pads single-digit months and days', () {
      expect(converter.toSql(const LocalDate(2026, 1, 5)), '2026-01-05');
    });

    test('stored dates sort lexicographically in calendar order', () {
      final List<String> stored = <String>[
        converter.toSql(const LocalDate(2026, 12, 1)),
        converter.toSql(const LocalDate(2026, 2, 28)),
        converter.toSql(const LocalDate(2027, 1, 1)),
        converter.toSql(const LocalDate(2026, 3, 9)),
      ]..sort();

      // This is the property the whole `ORDER BY due_date` design rests on.
      expect(stored, <String>[
        '2026-02-28',
        '2026-03-09',
        '2026-12-01',
        '2027-01-01',
      ]);
    });

    test('throws on a malformed stored value rather than losing the date', () {
      expect(() => converter.fromSql('11/03/2026'), throwsFormatException);
      expect(() => converter.fromSql('2026-02-30'), throwsFormatException);
    });
  });

  group('LocalDateTimeConverter', () {
    const LocalDateTimeConverter converter = LocalDateTimeConverter();

    test('round-trips, with no offset and no seconds', () {
      final LocalDateTime at = LocalDateTime.parseIso('2026-03-11T15:00');
      expect(converter.toSql(at), '2026-03-11T15:00');
      expect(converter.toSql(at).length, 16);
      expect(converter.fromSql('2026-03-11T15:00'), at);
    });

    test('carries no zone information at all', () {
      final String stored = converter.toSql(
        LocalDateTime.parseIso('2026-03-11T15:00'),
      );
      expect(stored.endsWith('Z'), isFalse);
      expect(stored.contains('+'), isFalse);
    });
  });

  group('UtcInstantConverter', () {
    const UtcInstantConverter converter = UtcInstantConverter();

    test('stores milliseconds, not seconds', () {
      final DateTime at = DateTime.utc(2026, 3, 11, 10, 0, 0, 123);
      expect(converter.toSql(at), at.millisecondsSinceEpoch);
      expect(converter.toSql(at) % 1000, 123);
    });

    test('normalises a local instant to UTC on the way in', () {
      final DateTime local = DateTime(2026, 3, 11, 10);
      expect(converter.toSql(local), local.toUtc().millisecondsSinceEpoch);
    });

    test('always reads back as UTC, so callers must opt into wall clock', () {
      final DateTime read = converter.fromSql(1773223200000);
      expect(read.isUtc, isTrue);
    });

    test('round-trips', () {
      final DateTime at = DateTime.utc(2026, 3, 11, 10, 30, 15, 500);
      expect(converter.fromSql(converter.toSql(at)), at);
    });
  });

  group('foldForSearch', () {
    test('lowercases', () {
      expect(foldForSearch('Buy MILK'), 'buy milk');
    });

    test('strips precomposed diacritics', () {
      expect(foldForSearch('Café'), 'cafe');
      expect(foldForSearch('Ünal Öztürk'), 'unal ozturk');
    });

    test('folds decomposed input to the same string as precomposed', () {
      // 'e' + U+0301 COMBINING ACUTE ACCENT, which is what some keyboards and
      // some transcriptions emit instead of U+00E9.
      const String decomposed = 'Café';
      expect(foldForSearch(decomposed), foldForSearch('Café'));
    });

    test('expands the two-letter cases a searcher would type', () {
      expect(foldForSearch('Straße'), 'strasse');
      expect(foldForSearch('Œuvre'), 'oeuvre');
    });

    test('removes LIKE metacharacters from both sides symmetrically', () {
      // The stored fold and the needle go through the same function, so a
      // pattern built from the result can contain no wildcard at all.
      expect(foldForSearch('100% done'), '100 done');
      expect(foldForSearch('snake_case'), 'snakecase');
      expect(foldForSearch(r'back\slash'), 'backslash');
      expect(foldForSearch('100%').isEmpty, isFalse);
    });

    test('collapses whitespace so a stripped character leaves no gap', () {
      expect(foldForSearch('  Buy \n  milk  '), 'buy milk');
      expect(foldForSearch('a % b'), 'a b');
    });

    test('leaves digits, punctuation and non-Latin scripts alone', () {
      expect(foldForSearch('Call +44 7700 900123'), 'call +44 7700 900123');
      expect(foldForSearch('Позвонить'), 'позвонить');
    });

    test('is idempotent — folding a folded string changes nothing', () {
      const String raw = 'Café  100% Straße_x';
      expect(foldForSearch(foldForSearch(raw)), foldForSearch(raw));
    });
  });
}
