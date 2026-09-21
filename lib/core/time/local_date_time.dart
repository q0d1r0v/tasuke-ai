import 'local_date.dart';
import 'local_time_of_day.dart';

/// A civil date-time: the pair, with no offset and no zone.
///
/// This is what a reminder is stored as. It answers "when should this fire on
/// the user's clock", not "which instant on the world's timeline" — see the
/// schema notes on `tasks.reminder_at_local` for the two failure modes that
/// storing an instant produces (travel and daylight saving).
final class LocalDateTime implements Comparable<LocalDateTime> {
  const LocalDateTime(this.date, this.time);

  factory LocalDateTime.fromLocal(DateTime nowLocal) => LocalDateTime(
    LocalDate(nowLocal.year, nowLocal.month, nowLocal.day),
    LocalTimeOfDay.hm(nowLocal.hour, nowLocal.minute),
  );

  /// Parses `YYYY-MM-DDTHH:MM`.
  factory LocalDateTime.parseIso(String iso) {
    if (iso.length < 16 || iso[10] != 'T') {
      throw FormatException('Expected YYYY-MM-DDTHH:MM', iso);
    }
    final LocalTimeOfDay? time = LocalTimeOfDay.tryParse(iso.substring(11, 16));
    if (time == null) {
      throw FormatException('Expected YYYY-MM-DDTHH:MM', iso);
    }
    return LocalDateTime(LocalDate.parseIso(iso.substring(0, 10)), time);
  }

  static LocalDateTime? tryParseIso(String? iso) {
    if (iso == null) return null;
    try {
      return LocalDateTime.parseIso(iso);
    } on FormatException {
      return null;
    }
  }

  final LocalDate date;
  final LocalTimeOfDay time;

  String toIso() => '${date.toIso()}T${time.toIso()}';

  /// Calendar-field arithmetic across the day boundary.
  LocalDateTime addMinutes(int minutes) {
    final int total = time.minuteOfDay + minutes;
    // Floor division, so negative offsets roll back a day correctly.
    final int dayShift = (total / 1440).floor();
    final int minuteOfDay = total - (dayShift * 1440);
    return LocalDateTime(date.addDays(dayShift), LocalTimeOfDay(minuteOfDay));
  }

  LocalDateTime subtractMinutes(int minutes) => addMinutes(-minutes);

  bool isBefore(LocalDateTime other) => compareTo(other) < 0;

  bool isAfter(LocalDateTime other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDateTime other) {
    final int byDate = date.compareTo(other.date);
    return byDate != 0 ? byDate : time.compareTo(other.time);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDateTime && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => toIso();
}
