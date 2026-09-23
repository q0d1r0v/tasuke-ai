import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/notifications/flutter_local_notifier.dart';
import 'package:timezone/timezone.dart' as tz;

/// Captures what [PluginNotificationHost] hands the plugin. Everything else is
/// unreachable from these tests.
final class _CapturingPlugin implements FlutterLocalNotificationsPlugin {
  NotificationDetails? details;

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    details = notificationDetails;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('an Android reminder is in the reminder category', () async {
    // ⚠️ Do Not Disturb's "Allow reminders" exception matches on the category.
    // Without it a user who allowed reminders through DND still missed ours.
    final _CapturingPlugin plugin = _CapturingPlugin();

    await PluginNotificationHost(plugin: plugin).zonedSchedule(
      id: 1,
      title: 'Leave for the airport',
      body: 'Tap to open this task.',
      at: tz.TZDateTime.utc(2026, 9, 21, 7, 30),
      payload: '{"taskId":"t-1"}',
      exact: true,
      strings: const NotificationStrings(),
    );

    final AndroidNotificationDetails android = plugin.details!.android!;
    expect(android.category, AndroidNotificationCategory.reminder);
    // Per notification, not per channel: the channel the user may have
    // customised must stay the same one.
    expect(android.channelId, PluginNotificationHost.channelId);
  });
}
