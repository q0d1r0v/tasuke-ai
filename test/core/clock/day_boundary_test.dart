import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';

/// How long until the local day rolls over.
///
/// ⚠️ It takes `now` as a parameter rather than reading a clock, and that is
/// the whole point: it keeps `DateTime.now()` inside `core/clock` where the
/// layering guard expects it, and it makes 23:59:59 and a DST date something a
/// test can state rather than something you have to wait for.
void main() {
  test('an ordinary afternoon counts to the next midnight', () {
    expect(
      untilNextLocalMidnight(DateTime(2026, 9, 21, 14, 30)),
      const Duration(hours: 9, minutes: 30),
    );
  });

  test('one second before midnight is one second, not a day', () {
    expect(
      untilNextLocalMidnight(DateTime(2026, 9, 21, 23, 59, 59)),
      const Duration(seconds: 1),
    );
  });

  test('exactly midnight waits a whole day, not zero', () {
    // ⚠️ Zero would arm a timer that fires immediately and re-arms at zero —
    // a spin that pins a core and drains the battery.
    expect(
      untilNextLocalMidnight(DateTime(2026, 9, 21)),
      const Duration(hours: 24),
    );
  });

  test('never returns zero or negative, whatever the input', () {
    for (final DateTime now in <DateTime>[
      DateTime(2026, 9, 21, 23, 59, 59, 999),
      DateTime(2026, 12, 31, 23, 59, 59),
      DateTime(2026, 2, 28, 23, 59, 59),
    ]) {
      expect(untilNextLocalMidnight(now), greaterThan(Duration.zero));
    }
  });

  test('the last day of a month rolls into the first of the next', () {
    expect(
      untilNextLocalMidnight(DateTime(2026, 1, 31, 22)),
      const Duration(hours: 2),
    );
    // February in a leap year: DateTime(2028, 2, 29 + 1) is 1 March.
    expect(
      untilNextLocalMidnight(DateTime(2028, 2, 29, 22)),
      const Duration(hours: 2),
    );
  });

  test('it is calendar arithmetic, not a 24-hour Duration', () {
    // ⚠️ THE assertion. On a DST date `now.add(const Duration(days: 1))` lands
    // an hour either side of midnight, so a timer built that way fires on the
    // wrong day twice a year — in the direction that leaves "Today" meaning
    // yesterday. `DateTime(y, m, d + 1)` is midnight whatever the offset did.
    //
    // Stated without a timezone dependency: whatever `now` is, adding the
    // result must land exactly on a local midnight.
    for (final DateTime now in <DateTime>[
      DateTime(2026, 3, 29, 1, 30),
      DateTime(2026, 10, 25, 1, 30),
      DateTime(2026, 11, 1, 1, 30),
    ]) {
      final DateTime landed = now.add(untilNextLocalMidnight(now));
      expect(landed.hour, 0, reason: 'landed at $landed from $now');
      expect(landed.minute, 0);
      expect(landed.second, 0);
    }
  });
}
