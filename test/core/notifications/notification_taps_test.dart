import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';

import '../../helpers/fakes.dart';

void main() {
  test('two taps with the same payload both reach a listener', () async {
    // ⚠️ riverpod notifies only when previous != next, and every tap on one
    // task carries the identical payload. As a bare String the second tap on
    // the same reminder was dropped, and the task did not open.
    final FakeLocalNotifier notifier = FakeLocalNotifier();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[localNotifierProvider.overrideWithValue(notifier)],
    );
    addTearDown(() {
      container.dispose();
      notifier.dispose();
    });

    final List<String> seen = <String>[];
    container.listen<AsyncValue<NotificationTap>>(notificationTapsProvider, (
      AsyncValue<NotificationTap>? _,
      AsyncValue<NotificationTap> next,
    ) {
      final String? payload = next.value?.payload;
      if (payload != null) seen.add(payload);
    });

    final String payload = encodeReminderPayload('t-1');
    notifier.emitTap(payload);
    await Future<void>.delayed(Duration.zero);
    notifier.emitTap(payload);
    await Future<void>.delayed(Duration.zero);

    expect(seen, <String>[payload, payload]);
  });
}
