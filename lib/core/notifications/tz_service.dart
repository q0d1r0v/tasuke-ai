import 'dart:async';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Where the device's IANA zone name comes from. Swapped in tests so the whole
/// scheduler can be exercised in `Asia/Kathmandu` on a machine in UTC.
typedef ZoneNameLookup = Future<String> Function();

/// The bridge between a civil [LocalDateTime] and an absolute instant.
///
/// Reminders are stored as wall-clock appointments and resolved here, at
/// scheduling time, against whatever zone the device is in *now*. That is what
/// keeps "tomorrow at 3 PM" firing at 3 PM after a flight and on both sides of
/// a daylight-saving transition.
final class TzService {
  TzService({ZoneNameLookup? lookup}) : _lookup = lookup ?? _platformZoneName;

  final ZoneNameLookup _lookup;
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// UTC until [initialise] has run.
  ///
  /// ⚠️ Not `null`. A nullable current zone grows a `!` at every call site, and
  /// the one place it is null is the cold-start race where a reminder is being
  /// rescheduled — exactly where a crash is least recoverable.
  String _zoneName = 'UTC';
  bool _databaseReady = false;

  /// Whether a device zone has been read successfully yet.
  bool _resolved = false;

  String get zoneName => _zoneName;

  /// Emits the new zone name whenever [refresh] finds a different one.
  ///
  /// A user who flies from Tashkent to Tokyo has every pending reminder off by
  /// four hours until something reschedules them; the rescheduler listens here
  /// and the app-resume provider is what makes it fire.
  ///
  /// ⚠️ The first successful read is not a change, so it does not emit. It
  /// used to: the placeholder UTC "changed" to the device zone on every cold
  /// start, and the zone listener ran a second full sweep on top of the
  /// bootstrap's, while the splash was up. Every caller of [refresh] after
  /// startup re-syncs on its own.
  Stream<String> get zoneChanges => _changes.stream;

  /// Loads the tz database and reads the device zone. Idempotent.
  ///
  /// ⚠️ Never throws. An odd or unreported device zone leaves the service on
  /// UTC with a warning: reminders an hour out are a bug, and a blank screen on
  /// first launch is an uninstall.
  Future<void> initialise() async {
    if (!_databaseReady) {
      try {
        tz_data.initializeTimeZones();
        _databaseReady = true;
      } on Object catch (error, stack) {
        Log.e('the timezone database would not load', error, stack);
        return;
      }
    }
    await refresh();
  }

  /// Re-reads the device zone. Returns true when it changed.
  Future<bool> refresh() async {
    String name;
    try {
      name = await _lookup();
    } on Object catch (error) {
      Log.w(
        'could not read the device timezone, staying on $_zoneName — $error',
      );
      return false;
    }
    if (name.isEmpty) return false;
    if (name == _zoneName) {
      _resolved = true;
      return false;
    }

    final tz.Location? location = _locationOrNull(name);
    if (location == null) {
      // A zone name the tz database does not carry (some OEM ROMs report
      // obsolete aliases). Keeping the previous zone beats resolving everything
      // against UTC.
      Log.w('unknown timezone "$name", staying on $_zoneName');
      return false;
    }

    final bool isChange = _resolved;
    _zoneName = name;
    _resolved = true;
    tz.setLocalLocation(location);
    if (isChange && !_changes.isClosed) _changes.add(name);
    Log.d('timezone is now $name');
    return true;
  }

  /// Resolves a civil date-time to the instant the OS should fire it at.
  ///
  /// ⚠️ A 02:30 reminder on a spring-forward night **does not exist**.
  /// [tz.TZDateTime] normalises it to 03:30, and that is the right answer: the
  /// user asked for "half past two", the clock skipped it, and firing at the
  /// next real moment is what every calendar app does. Do not write the shifted
  /// value back into the task — the stored civil time stays 02:30, so next year,
  /// when 02:30 exists again, the reminder is at 02:30 again.
  tz.TZDateTime resolve(LocalDateTime at, {required String zoneName}) {
    final tz.Location location = _locationOrNull(zoneName) ?? tz.UTC;
    return tz.TZDateTime(
      location,
      at.date.year,
      at.date.month,
      at.date.day,
      at.time.hour,
      at.time.minute,
    );
  }

  /// Resolves against the zone the device is in right now.
  tz.TZDateTime resolveLocal(LocalDateTime at) =>
      resolve(at, zoneName: _zoneName);

  /// Adds [days] by **calendar field**, not by elapsed time.
  ///
  /// ⚠️ `add(Duration(days: 1))` is absolute elapsed time: across a
  /// daylight-saving boundary it moves the wall clock by an hour, so a 09:00
  /// daily reminder becomes 08:00 or 10:00 and stays there. The sibling app
  /// `era_play` has exactly that bug at `lib/services/reminders.dart:146`, where
  /// it is survivable because the reminder is one nudge a day; here every task
  /// carries its own time and the drift is per-task and permanent.
  static tz.TZDateTime shiftDays(tz.TZDateTime from, int days) => tz.TZDateTime(
    from.location,
    from.year,
    from.month,
    from.day + days,
    from.hour,
    from.minute,
    from.second,
  );

  Future<void> dispose() => _changes.close();

  tz.Location? _locationOrNull(String name) {
    try {
      return tz.getLocation(name);
    } on Object {
      return null;
    }
  }

  static Future<String> _platformZoneName() =>
      FlutterTimezone.getLocalTimezone();
}
