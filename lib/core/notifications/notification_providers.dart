import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/notifications/flutter_local_notifier.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/notifications/tz_service.dart';

/// The zone the device is in, and a stream of changes to it.
final Provider<TzService> tzServiceProvider = Provider<TzService>((Ref ref) {
  final TzService service = TzService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// The strings the OS itself renders. Overridden from `AppLocalizations`.
final Provider<NotificationStrings> notificationStringsProvider =
    Provider<NotificationStrings>((Ref ref) => const NotificationStrings());

/// The local-notification port.
///
/// ⚠️ `initialise()` is **not** called here. A provider's create function runs
/// on first read, which may be inside a widget build, and initialising the
/// plugin there would put a platform round-trip in a frame. The app bootstrap
/// awaits it once, before the first route is resolved.
final Provider<LocalNotifier> localNotifierProvider = Provider<LocalNotifier>((
  Ref ref,
) {
  final FlutterLocalNotifier notifier = FlutterLocalNotifier(
    tz: ref.watch(tzServiceProvider),
    strings: ref.watch(notificationStringsProvider),
  );
  ref.onDispose(() => unawaited(notifier.dispose()));
  return notifier;
});

/// One tap on a notification. [seq] is unique per tap within the process.
typedef NotificationTap = ({int seq, String payload});

/// Notification taps that arrive while the app is running.
///
/// ⚠️ `seq` is load-bearing, the same trap as `appResumedProvider`: riverpod
/// only notifies when previous != next, and every tap on one task carries the
/// identical payload. As a bare String stream, the second tap on the same
/// task's reminder never reached the listener and the task did not open.
final StreamProvider<NotificationTap> notificationTapsProvider =
    StreamProvider<NotificationTap>((Ref ref) {
      int seq = 0;
      return ref
          .watch(localNotifierProvider)
          .taps
          .map((String payload) => (seq: ++seq, payload: payload));
    });

/// Emits whenever the device's timezone changes. The rescheduler listens here:
/// every pending reminder is resolved against a zone, and a flight invalidates
/// all of them at once.
final StreamProvider<String> timezoneChangesProvider = StreamProvider<String>(
  (Ref ref) => ref.watch(tzServiceProvider).zoneChanges,
);
