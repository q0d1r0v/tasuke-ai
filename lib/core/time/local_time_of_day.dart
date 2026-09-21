/// A wall-clock time of day, stored as minutes since local midnight.
///
/// Deliberately not Flutter's `TimeOfDay`: this type lives in the domain layer,
/// which may not import `package:flutter`.
final class LocalTimeOfDay implements Comparable<LocalTimeOfDay> {
  const LocalTimeOfDay(this.minuteOfDay)
    : assert(
        minuteOfDay >= 0 && minuteOfDay < 1440,
        'minuteOfDay must be in [0, 1440)',
      );

  const LocalTimeOfDay.hm(int hour, int minute)
    : minuteOfDay = hour * 60 + minute;

  /// Returns null for values outside `[0, 1440)`, rather than asserting. For
  /// database rows and model output.
  static LocalTimeOfDay? tryFromMinutes(int? minuteOfDay) {
    if (minuteOfDay == null || minuteOfDay < 0 || minuteOfDay >= 1440) {
      return null;
    }
    return LocalTimeOfDay(minuteOfDay);
  }

  /// Parses `HH:MM` (24-hour). Null on anything else.
  static LocalTimeOfDay? tryParse(String? text) {
    if (text == null || text.length != 5 || text[2] != ':') return null;
    final int? h = int.tryParse(text.substring(0, 2));
    final int? m = int.tryParse(text.substring(3, 5));
    if (h == null || m == null || h > 23 || m > 59) return null;
    return LocalTimeOfDay.hm(h, m);
  }

  final int minuteOfDay;

  int get hour => minuteOfDay ~/ 60;

  int get minute => minuteOfDay % 60;

  String toIso() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalTimeOfDay other) =>
      minuteOfDay.compareTo(other.minuteOfDay);

  @override
  bool operator ==(Object other) =>
      other is LocalTimeOfDay && other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => minuteOfDay.hashCode;

  @override
  String toString() => toIso();
}
