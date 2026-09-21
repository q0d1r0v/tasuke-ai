import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/when_parser.dart';

/// Month arithmetic, which is where every date library eventually breaks.
void main() {
  const WhenParser parser = WhenParser();

  String? dateOf(String phrase, String nowIso) =>
      parser.parse(phrase, now: LocalDateTime.parseIso(nowIso)).date?.toIso();

  group('month ends', () {
    test('"in a month" from 31 January clamps, it does not roll over', () {
      // 2 or 3 March would be a month of elapsed days. Nobody means that.
      expect(dateOf('in a month', '2026-01-31T09:00'), '2026-02-28');
      expect(dateOf('in a month', '2028-01-31T09:00'), '2028-02-29');
    });

    test('clamping from the other long months', () {
      expect(dateOf('in a month', '2026-03-31T09:00'), '2026-04-30');
      expect(dateOf('in a month', '2026-05-31T09:00'), '2026-06-30');
      expect(dateOf('in a month', '2026-08-31T09:00'), '2026-09-30');
    });

    test('several months at once still clamps', () {
      expect(dateOf('in 2 months', '2025-12-31T09:00'), '2026-02-28');
      expect(dateOf('in 12 months', '2028-02-29T09:00'), '2029-02-28');
    });

    test('end of the month', () {
      expect(dateOf('end of the month', '2026-09-21T10:00'), '2026-09-30');
      expect(dateOf('end of month', '2026-02-10T10:00'), '2026-02-28');
      expect(dateOf('end of the month', '2028-02-10T10:00'), '2028-02-29');
      expect(
        dateOf('end of the month', '2026-01-31T09:00'),
        '2026-01-31',
        reason: 'said on the last day, it is today',
      );
    });

    test('end of next month', () {
      expect(dateOf('end of next month', '2026-09-21T10:00'), '2026-10-31');
      expect(dateOf('end of next month', '2026-01-15T10:00'), '2026-02-28');
      expect(dateOf('end of next month', '2026-12-15T10:00'), '2027-01-31');
      expect(
        dateOf('end of next month', '2026-01-31T09:00'),
        '2026-02-28',
        reason: 'the 31st of a month that has no 31st',
      );
    });

    test('last day of the month is the same thing said longhand', () {
      expect(dateOf('last day of the month', '2026-09-21T10:00'), '2026-09-30');
      expect(
        dateOf('the last day of the month', '2026-02-01T10:00'),
        '2026-02-28',
      );
    });

    test('next month is the first of it, across a year boundary', () {
      expect(dateOf('next month', '2026-12-15T10:00'), '2027-01-01');
      expect(dateOf('next month', '2026-01-31T10:00'), '2026-02-01');
    });
  });
}
