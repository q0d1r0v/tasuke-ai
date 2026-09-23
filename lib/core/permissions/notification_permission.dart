import 'package:tasuke_ai/core/permissions/app_permission.dart';

/// Asks for the notification permission if it can still be asked for, and
/// returns where it ended up.
///
/// ⚠️ Called at the moment a reminder is created — not only from onboarding.
///
/// The permissions primer in onboarding was the ONLY place this was ever
/// requested, and the primer is deliberately skippable ("a primer, not a
/// gate"). A user who tapped Continue without tapping the Notifications card
/// therefore never saw the OS dialog, Android left the app at
/// `POST_NOTIFICATION: ignore`, and every reminder they set was silently
/// dropped by the scheduler. On a real phone: a task for 6:11 PM with its
/// Reminder switch ON, and at 6:11 PM nothing.
///
/// Asking at the moment the user turns a reminder on is also simply the right
/// time to ask — the reason for the permission is on screen.
///
/// Never re-asks a permanent denial: the OS will not show the dialog again,
/// and the Home banner offers the Settings route instead.
Future<PermissionState> ensureNotificationPermission(
  PermissionService permissions,
) async {
  PermissionState state = await permissions.status(AppPermission.notifications);
  if (state == PermissionState.notDetermined ||
      state == PermissionState.denied) {
    state = await permissions.request(AppPermission.notifications);
  }
  return state;
}

/// Everything a reminder needs to actually ring, on time.
///
/// Notifications first — without them nothing rings at all. Then, only if
/// those were granted and only the first time, exact alarms: on Android 14+
/// `SCHEDULE_EXACT_ALARM` is off by default, the scheduler then falls back to
/// an inexact alarm, and a reminder for 6:11 PM can arrive ten or fifteen
/// minutes late. There is no dialog for it; requesting it opens the system
/// "Alarms & reminders" page, which is why [alreadyPrompted] limits the
/// app to doing that once on its own.
///
/// ⚠️ [alreadyPrompted] is a function, read only after the notification
/// request has happened. As a plain `bool` it was evaluated at the call site,
/// before this function ran — so anything that made reading the flag throw
/// also stopped the notification permission from ever being asked for, which
/// is the one part of this that decides whether a reminder rings at all.
Future<void> ensureReminderPermissions(
  PermissionService permissions, {
  required bool Function() alreadyPrompted,
  required Future<void> Function() markPrompted,
}) async {
  final PermissionState notifications = await ensureNotificationPermission(
    permissions,
  );
  if (!notifications.isGranted) return;

  final PermissionState exact = await permissions.status(
    AppPermission.exactAlarm,
  );
  if (exact.isGranted || alreadyPrompted()) return;

  await markPrompted();
  await permissions.request(AppPermission.exactAlarm);
}
