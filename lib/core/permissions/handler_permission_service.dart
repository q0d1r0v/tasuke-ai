import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';

/// The one importer of `package:permission_handler`.
///
/// Everything above it works in terms of [AppPermission] and [PermissionState],
/// which is why the Permissions screen can be driven through every state in a
/// widget test — including `permanentlyDenied`, which is otherwise reachable
/// only by denying a real dialog twice on a real phone.
final class HandlerPermissionService implements PermissionService {
  const HandlerPermissionService();

  @override
  Future<PermissionState> status(AppPermission permission) async {
    final ph.Permission? native = _nativeOf(permission);
    if (native == null) return PermissionState.notApplicable;
    try {
      return _map(await native.status);
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
      return _map(await native.request());
    } on Object catch (error, stack) {
      Log.e('requesting ${permission.name} permission failed', error, stack);
      return PermissionState.denied;
    }
  }

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
  static ph.Permission? _nativeOf(AppPermission permission) =>
      switch (permission) {
        AppPermission.microphone => ph.Permission.microphone,
        AppPermission.notifications => ph.Permission.notification,
        AppPermission.exactAlarm =>
          Platform.isAndroid ? ph.Permission.scheduleExactAlarm : null,
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
