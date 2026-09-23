/// The one seam around "what time is it".
///
/// Nothing in `lib/` outside this file and `core/time/` may call
/// `DateTime.now()`, `DateTime.timestamp()` or `tz.TZDateTime.now()` — a guard
/// test enforces it. That single rule is what makes the date grammar, the
/// quota reset and the reminder scheduler testable at all: every one of them
/// takes `now` rather than reading it, so a hundred fixture cases are each one
/// line instead of a mock.
abstract interface class Clock {
  /// The current instant in the device's local zone.
  DateTime nowLocal();

  /// The current instant in UTC. Used for the "when did this happen" columns.
  DateTime nowUtc();
}

/// The production clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowLocal() => DateTime.now();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A clock frozen at one instant. The default in tests.
final class FixedClock implements Clock {
  const FixedClock(this._instant);

  final DateTime _instant;

  @override
  DateTime nowLocal() => _instant.isUtc ? _instant.toLocal() : _instant;

  @override
  DateTime nowUtc() => _instant.toUtc();
}

/// A clock a test can move. Useful for "cross midnight" and "quota resets"
/// cases, where two reads must differ.
final class MutableClock implements Clock {
  MutableClock(this._instant);

  DateTime _instant;

  set instant(DateTime value) => _instant = value;

  void advance(Duration by) => _instant = _instant.add(by);

  @override
  DateTime nowLocal() => _instant.isUtc ? _instant.toLocal() : _instant;

  @override
  DateTime nowUtc() => _instant.toUtc();
}

/// How long until the next local midnight, measured from [nowLocal].
///
/// ⚠️ `DateTime(y, m, d + 1)` and NOT `nowLocal.add(const Duration(days: 1))`.
/// A Duration is 24 absolute hours; across a DST transition that lands an hour
/// either side of midnight, and the day-rollover timer then fires on the wrong
/// day twice a year — in the direction that leaves "Today" showing yesterday.
///
/// Takes `now` as a parameter rather than reading a clock, so it is pure, is
/// testable at 23:59:59 and on a spring-forward date, and keeps
/// `DateTime.now()` inside this file where the layering guard expects it.
///
/// Never returns zero or a negative: a timer armed with those fires
/// immediately and spins.
Duration untilNextLocalMidnight(DateTime nowLocal) {
  final DateTime next = DateTime(
    nowLocal.year,
    nowLocal.month,
    nowLocal.day + 1,
  );
  final Duration remaining = next.difference(nowLocal);
  return remaining.inSeconds < 1 ? const Duration(seconds: 1) : remaining;
}
