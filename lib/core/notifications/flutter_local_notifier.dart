import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/notifications/tz_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Stable OS alarm slots.
abstract final class NotificationIds {
  /// A notification id derived from a task id.
  ///
  /// ⚠️ Deliberately **not** `taskId.hashCode`. Dart's String hash is seeded per
  /// isolate group and is not promised to be stable across SDK versions, so a
  /// reminder scheduled by v1.0 could not be cancelled by v1.1 — the old alarm
  /// fires forever and a second one is added beside it. FNV-1a is arithmetic,
  /// not a policy, and will give the same answer in ten years.
  ///
  /// Masked to 31 bits because Android's notification id is a Java `int`.
  static int forTask(String taskId) {
    int hash = 0x811c9dc5;
    for (final int unit in taskId.codeUnits) {
      hash ^= unit & 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
      hash ^= (unit >> 8) & 0xFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}

/// The user-visible strings the OS itself renders.
///
/// ⚠️ These are the one set of strings in the app that cannot come from
/// `context.l10n`: Android reads the channel name out of the notification it is
/// handed, from a layer with no `BuildContext`, and shows it in the system
/// Settings app. The defaults are copies of `notificationChannelName` and
/// `notificationChannelDescription` in `app_en.arb`; the app overrides this
/// object from `AppLocalizations` once it has one.
final class NotificationStrings {
  const NotificationStrings({
    this.channelName = 'Task reminders',
    this.channelDescription = 'Reminders for the tasks you create.',
  });

  final String channelName;
  final String channelDescription;
}

/// Everything [FlutterLocalNotifier] needs from the plugin.
///
/// This seam is what makes `test/core/notifications/scheduler_test.dart`
/// possible: the interesting logic is the civil-to-absolute resolution and the
/// exact/inexact decision, and neither can be asserted through a MethodChannel
/// that does not exist under `flutter test`.
abstract interface class NotificationHost {
  Future<void> initialise({required void Function(String payload) onTap});

  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required String payload,
    required bool exact,
    required NotificationStrings strings,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();

  Future<List<int>> pendingIds();

  Future<bool> areNotificationsEnabled();

  Future<bool> requestNotificationPermission();

  Future<bool> canScheduleExact();

  Future<bool> requestExactAlarmPermission();

  /// Read once by the notifier; null when the app was not launched from a tap.
  Future<String?> launchPayload();
}

/// One reminder exactly as it was last handed to the OS.
typedef _Armed = ({
  int instant,
  String zone,
  bool exact,
  String title,
  String body,
  String payload,
  String channelName,
  String channelDescription,
});

/// The local-notification port.
final class FlutterLocalNotifier implements LocalNotifier {
  FlutterLocalNotifier({
    NotificationHost? host,
    TzService? tz,
    this._strings = const NotificationStrings(),
  }) : _host = host ?? PluginNotificationHost(),
       _tz = tz ?? TzService();

  final NotificationHost _host;
  final TzService _tz;
  final NotificationStrings _strings;

  final StreamController<String> _taps = StreamController<String>.broadcast();

  /// What this process has armed, by id, so a sweep can leave an unchanged
  /// alarm alone instead of cancelling and re-creating it.
  ///
  /// ⚠️ In memory only, and never filled from [pendingIds]: the plugin's list
  /// is its own SharedPreferences cache, not AlarmManager. An entry is written
  /// only after `zonedSchedule` succeeds, and dropped on cancel, cancelAll, any
  /// failure, and as soon as the plugin stops listing the id (it fired). Every
  /// way Android drops alarms wholesale — force stop, reboot, app update, a
  /// permission or exact-alarm revocation — also ends the process, and with it
  /// this map.
  final Map<int, _Armed> _armed = <int, _Armed>{};

  bool _initialised = false;
  bool _launchPayloadConsumed = false;

  TzService get timezones => _tz;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;
    await _tz.initialise();
    await _host.initialise(
      onTap: (String payload) {
        if (!_taps.isClosed) _taps.add(payload);
      },
    );
  }

  @override
  Future<bool> hasPermission() => _host.areNotificationsEnabled();

  @override
  Future<bool> requestPermission() => _host.requestNotificationPermission();

  @override
  Future<bool> canScheduleExact() => _host.canScheduleExact();

  @override
  Future<bool> requestExactAlarmPermission() =>
      _host.requestExactAlarmPermission();

  @override
  Future<ScheduleResult> schedule(ScheduledReminder reminder) async {
    // The civil time becomes an instant here and nowhere else. Resolving it when
    // the task was saved would freeze the offset that applied that day, and the
    // reminder would then be an hour out for every task that crosses a
    // daylight-saving boundary — the single most common reminder bug there is.
    final tz.TZDateTime at = _tz.resolveLocal(reminder.atLocal);

    final bool exact = await _host.canScheduleExact();
    final ScheduleResult result = ScheduleResult(
      exact ? SchedulePrecision.exact : SchedulePrecision.inexact,
    );

    final _Armed armed = (
      instant: at.millisecondsSinceEpoch,
      zone: at.location.name,
      exact: exact,
      title: reminder.title,
      body: reminder.body,
      payload: reminder.payload,
      channelName: _strings.channelName,
      channelDescription: _strings.channelDescription,
    );
    // Every sweep re-arms the whole window, and on Android each re-arm is a
    // cancel plus a schedule that each rewrite the plugin's whole JSON cache on
    // the UI thread. An alarm this process already set identically is skipped.
    if (_armed[reminder.id] == armed) return result;

    // Dropped before the OS is touched, so a cancel or a schedule that throws
    // leaves nothing claimed and the next sweep tries again.
    _armed.remove(reminder.id);

    // ⚠️ Cancel first, always, even though both platforms document "replace by
    // id". Android's AlarmManager does not replace an *exact* alarm with an
    // inexact one — the old PendingIntent survives and the user gets two
    // notifications, one at the old time. Editing a task is the common case, so
    // the ordering matters more often than it looks.
    await _host.cancel(reminder.id);
    try {
      await _host.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        at: at,
        payload: reminder.payload,
        exact: exact,
        strings: _strings,
      );
    } on Object catch (error, stack) {
      Log.e('scheduling reminder ${reminder.id} failed', error, stack);
      throw SchedulingFailure('Could not schedule reminder ${reminder.id}');
    }

    _armed[reminder.id] = armed;
    return result;
  }

  @override
  Future<void> cancel(int id) {
    _armed.remove(id);
    return _host.cancel(id);
  }

  @override
  Future<void> cancelAll() {
    _armed.clear();
    return _host.cancelAll();
  }

  @override
  Future<List<int>> pendingIds() async {
    final List<int> ids = await _host.pendingIds();
    // Only ever narrows [_armed]: an id the plugin stopped listing has fired or
    // been lost, and has to be re-armed rather than skipped.
    final Set<int> listed = ids.toSet();
    _armed.removeWhere((int id, _Armed _) => !listed.contains(id));
    return ids;
  }

  /// Consumed on read.
  ///
  /// ⚠️ `getNotificationAppLaunchDetails()` keeps returning the same payload for
  /// the whole process lifetime, so a second reader — a route guard re-running
  /// after a rebuild, say — reopens a task the user already dealt with. The
  /// latch, not the plugin, is what makes "consumed" true.
  @override
  Future<String?> consumeLaunchPayload() async {
    if (_launchPayloadConsumed) return null;
    _launchPayloadConsumed = true;
    return _host.launchPayload();
  }

  Future<void> dispose() async {
    await _taps.close();
    await _tz.dispose();
  }
}

/// The one importer of `package:flutter_local_notifications`.
final class PluginNotificationHost implements NotificationHost {
  PluginNotificationHost({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// The Android notification channel. Changing this string strands every
  /// channel setting the user already customised, because Android keys those by
  /// id and cannot migrate them.
  static const String channelId = 'tasuke_task_reminders';

  /// The status-bar icon: `android/app/src/main/res/drawable/ic_notification.xml`.
  ///
  /// ⚠️ Looked up by name when a reminder fires, and the release resource
  /// shrinker cannot see a name that lives in Dart — `res/raw/keep.xml` is what
  /// keeps the drawable in the APK. This used to be `@mipmap/ic_launcher`, which
  /// the shrinker deleted: the plugin never stored a default icon, and its
  /// receiver crashed in `setSmallIcon` at the minute of every reminder, so the
  /// release build never showed one. `notification_icon_test.dart` pins all
  /// three pieces together.
  static const String smallIcon = 'ic_notification';

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialise({
    required void Function(String payload) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(smallIcon),
        iOS: DarwinInitializationSettings(
          // Permission is asked for on the Permissions screen, where the user
          // can see why. A prompt on first launch has no context and is the
          // single easiest way to lose the notification permission for good.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          // Foreground presentation: a reminder that fires while the app is open
          // still has to appear. Without these, iOS silently swallows it and the
          // only symptom is "reminders work unless I am using the app".
          defaultPresentAlert: true,
          defaultPresentSound: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap(payload);
      },
      // No background handler on purpose: it only runs for action buttons, and
      // these notifications have none. A tap always brings the app up, and the
      // payload arrives either through the callback above or, on a cold start,
      // through [launchPayload].
    );
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required String payload,
    required bool exact,
    required NotificationStrings strings,
  }) {
    // ⚠️ Named parameters. flutter_local_notifications 22.x made every argument
    // named; the 17.x positional form that every tutorial online still shows
    // does not compile here.
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: at,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          strings.channelName,
          channelDescription: strings.channelDescription,
          // Also set per notification, not only as the plugin default: the
          // default lives in the plugin's own preferences, written by
          // `initialize`, and a notification that carries its icon does not
          // depend on that write having happened in some earlier process.
          icon: smallIcon,
          // A reminder the user asked for at a specific minute earns a heads-up
          // notification; anything quieter and it is indistinguishable from not
          // having fired.
          importance: Importance.high,
          priority: Priority.high,
          // What Do Not Disturb's "Allow reminders" exception matches on;
          // without it a reminder is silenced like any other notification.
          // Per notification, so the channel and its settings are untouched.
          // Not `alarm`: that breaks through DND for users who never allowed it.
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<List<int>> pendingIds() async {
    final List<PendingNotificationRequest> pending = await _plugin
        .pendingNotificationRequests();
    return pending
        .map((PendingNotificationRequest request) => request.id)
        .toList();
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      return await _android?.areNotificationsEnabled() ?? false;
    }
    final NotificationsEnabledOptions? options = await _ios?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      return await _android?.requestNotificationsPermission() ?? false;
    }
    return await _ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  /// Always true off Android: iOS has no exact-alarm concept, so pretending it
  /// needs permission would put a permanent "reminders may be late" banner on
  /// every iPhone.
  @override
  Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    return await _android?.requestExactAlarmsPermission() ?? false;
  }

  @override
  Future<String?> launchPayload() async {
    final NotificationAppLaunchDetails? details = await _plugin
        .getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
}
