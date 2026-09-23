import 'dart:async';
import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';

/// The one importer of `package:permission_handler`.
///
/// Everything above it works in terms of [AppPermission] and [PermissionState],
/// which is why the Permissions screen can be driven through every state in a
/// widget test — including `permanentlyDenied`, which is otherwise reachable
/// only by denying a real dialog twice on a real phone.
final class HandlerPermissionService implements PermissionService {
  HandlerPermissionService({this._preferences, bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  /// Where a refusal the OS will not re-prompt for is remembered. Null only in
  /// code paths that never reach a real device.
  final SharedPreferences? _preferences;

  final bool _isAndroid;

  @override
  Future<PermissionState> status(AppPermission permission) async {
    final ph.Permission? native = _nativeOf(permission);
    if (native == null) return PermissionState.notApplicable;
    try {
      return _recall(permission, _map(await native.status));
    } on Object catch (error, stack) {
      Log.e('reading ${permission.name} permission failed', error, stack);
      return PermissionState.denied;
    }
  }

  @override
  Future<PermissionState> request(AppPermission permission) async {
    final ph.Permission? native = _nativeOf(permission);
    if (native == null) return PermissionState.notApplicable;
    try {
      final PermissionState answer = _map(await native.request());
      await _remember(permission, answer);
      return answer;
    } on Object catch (error, stack) {
      Log.e('requesting ${permission.name} permission failed', error, stack);
      return PermissionState.denied;
    }
  }

  // ── Remembered refusals ────────────────────────────────────────────────────
  //
  // ⚠️ On Android a status check never says `permanentlyDenied`: it reports
  // `denied` for "never asked", "asked once" and "never ask again" alike (see
  // [_map]). Only a request's answer tells them apart, and a request for a
  // permission the OS will not prompt for again returns at once, with no
  // dialog. So without remembering that answer every later tap — the Home
  // banner, a permissions card, "Allow all" — re-requested, the OS silently
  // refused, and the tap did nothing at all, for ever.
  //
  // With the answer remembered, status() reports `permanentlyDenied`, and the
  // callers' existing `needsSettings` branches send the user to the Settings
  // app — the only place the answer can still change. It is not used to jump
  // to Settings in the same tap: a user who has just pressed "Don't allow" in a
  // dialog is not thrown out of the app for it. The card turns into "Open
  // Settings", and the next tap goes there.

  /// Whether a refusal of [permission] can outlive its dialog.
  ///
  /// Not exact alarms: requesting one always opens the "Alarms & reminders"
  /// page, which is exactly where it is fixed. Remembering a refusal there
  /// would send the user to the app's general Settings page instead.
  static bool _remembers(AppPermission permission) =>
      permission != AppPermission.exactAlarm;

  String _refusedKey(AppPermission permission) =>
      '${PrefKeys.permissionRefusedPrefix}${permission.name}';

  PermissionState _recall(AppPermission permission, PermissionState state) {
    final SharedPreferences? preferences = _preferences;
    if (preferences == null || !_remembers(permission)) return state;
    final bool refused = preferences.getBool(_refusedKey(permission)) ?? false;
    if (state.isGranted) {
      // Granted from the Settings app since: the memory is stale.
      if (refused) unawaited(preferences.remove(_refusedKey(permission)));
      return state;
    }
    return refused && state == PermissionState.denied
        ? PermissionState.permanentlyDenied
        : state;
  }

  Future<void> _remember(
    AppPermission permission,
    PermissionState answer,
  ) async {
    final SharedPreferences? preferences = _preferences;
    if (preferences == null || !_remembers(permission)) return;
    if (answer.isGranted) {
      await preferences.remove(_refusedKey(permission));
    } else if (_refusedForGood(permission, answer)) {
      await preferences.setBool(_refusedKey(permission), true);
    }
  }

  /// Whether this answer means another request will not show a dialog.
  ///
  /// Notifications on Android count on any refusal. Below Android 13 there is
  /// no notification prompt at all — the plugin answers `denied` at once — so
  /// a user who switched notifications off can only switch them back on in
  /// Settings. On 13+ this costs at most the second dialog, and Settings works
  /// there too.
  bool _refusedForGood(AppPermission permission, PermissionState answer) =>
      answer == PermissionState.permanentlyDenied ||
      (_isAndroid &&
          permission == AppPermission.notifications &&
          answer == PermissionState.denied);

  @override
  Future<bool> openSettings() async {
    try {
      return await ph.openAppSettings();
    } on Object catch (error) {
      Log.w('could not open app settings — $error');
      return false;
    }
  }

  /// Null means "this platform has no such permission".
  ///
  /// Exact alarms are an Android 12+ special access screen. On iOS the concept
  /// does not exist at all, and reporting anything but [notApplicable] would put
  /// a permanent "reminders may be late" row on the Permissions screen of every
  /// iPhone.
  ph.Permission? _nativeOf(AppPermission permission) => switch (permission) {
    AppPermission.microphone => ph.Permission.microphone,
    AppPermission.notifications => ph.Permission.notification,
    AppPermission.exactAlarm =>
      _isAndroid ? ph.Permission.scheduleExactAlarm : null,
  };

  /// ⚠️ [PermissionState.notDetermined] is never produced, and that is the
  /// platform's doing rather than an omission. Android cannot tell "never asked"
  /// from "denied" from "reset to ask every time" — `status` reports `denied`
  /// for all three — and iOS reports `permanentlyDenied` the moment the user
  /// refuses, because iOS only ever asks once. Code that branches on
  /// `notDetermined` will therefore never run; branch on
  /// [PermissionState.needsSettings] instead, which is the distinction that
  /// actually changes what the button does.
  static PermissionState _map(ph.PermissionStatus status) => switch (status) {
    // `limited` and `provisional` are both "yes, with conditions" — a
    // provisionally authorised app really does deliver notifications, just
    // quietly, so treating them as denied would show a permission prompt to
    // someone already receiving reminders.
    ph.PermissionStatus.granted ||
    ph.PermissionStatus.limited ||
    ph.PermissionStatus.provisional => PermissionState.granted,
    ph.PermissionStatus.denied => PermissionState.denied,
    ph.PermissionStatus.permanentlyDenied => PermissionState.permanentlyDenied,
    ph.PermissionStatus.restricted => PermissionState.restricted,
  };
}
