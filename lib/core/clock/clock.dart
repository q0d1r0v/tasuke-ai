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
