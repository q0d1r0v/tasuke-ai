/// A calendar date with no time and no zone.
///
/// `2026-09-22` is the same date in Tashkent and in Tokyo; a [DateTime] is not,
/// which is the entire reason this type exists. Tasks are stored against a
/// local calendar date so that "tomorrow" means tomorrow on the user's own
/// calendar, wherever they happen to be.
final class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// Today, on the device's local calendar.
  factory LocalDate.today(DateTime nowLocal) =>
      LocalDate(nowLocal.year, nowLocal.month, nowLocal.day);

  /// Parses `YYYY-MM-DD`. Throws [FormatException] on anything else — this is
  /// the database's storage format, so a failure here is corruption, not input.
  factory LocalDate.parseIso(String iso) {
    if (iso.length != 10 || iso[4] != '-' || iso[7] != '-') {
      throw FormatException('Expected YYYY-MM-DD', iso);
    }
    final int? y = int.tryParse(iso.substring(0, 4));
    final int? m = int.tryParse(iso.substring(5, 7));
    final int? d = int.tryParse(iso.substring(8, 10));
    if (y == null || m == null || d == null) {
      throw FormatException('Expected YYYY-MM-DD', iso);
    }
    if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) {
      throw FormatException('Not a real calendar date', iso);
    }
    return LocalDate(y, m, d);
  }

  /// Returns null instead of throwing. For model output and user input, where
  /// an unparseable value is expected and must not crash.
  static LocalDate? tryParseIso(String? iso) {
    if (iso == null) return null;
    try {
      return LocalDate.parseIso(iso);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;
  final int day;

  static const List<int> _daysPerMonth = <int>[
    31,
    28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  static int daysInMonth(int year, int month) =>
      month == 2 && isLeapYear(year) ? 29 : _daysPerMonth[month - 1];

  /// `YYYY-MM-DD`. Sorts lexicographically in true chronological order, which
  /// is why the database stores this as TEXT rather than an epoch day.
  String toIso() {
    final String m = month.toString().padLeft(2, '0');
    final String d = day.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}-$m-$d';
  }

  /// Calendar-field arithmetic, deliberately not `DateTime.add(Duration)`.
  ///
  /// A [Duration] is absolute elapsed time: adding `Duration(days: 1)` across a
  /// daylight-saving boundary moves the wall clock by an hour. Dates have no
  /// wall clock to move, but the same habit in the reminder code is a real bug
  /// — see `TzService.shiftDays`.
  LocalDate addDays(int days) {
    final DateTime shifted = DateTime.utc(year, month, day + days);
    return LocalDate(shifted.year, shifted.month, shifted.day);
  }

  LocalDate addMonths(int months) {
    final int total = (year * 12) + (month - 1) + months;
    final int y = total ~/ 12;
    final int m = (total % 12) + 1;
    // Clamp rather than roll over: "in a month" from 31 January is 28 or 29
    // February, not 2 or 3 March.
    final int d = day > daysInMonth(y, m) ? daysInMonth(y, m) : day;
    return LocalDate(y, m, d);
  }

  /// `DateTime.monday` (1) … `DateTime.sunday` (7).
  int get weekday => DateTime.utc(year, month, day).weekday;

  LocalDate get lastDayOfMonth =>
      LocalDate(year, month, daysInMonth(year, month));

  int differenceInDays(LocalDate other) => DateTime.utc(
    year,
    month,
    day,
  ).difference(DateTime.utc(other.year, other.month, other.day)).inDays;

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  /// A midnight [DateTime] in the local zone. Only for formatting through
  /// `intl`, never for comparison.
  DateTime toDateTimeLocal() => DateTime(year, month, day);

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
