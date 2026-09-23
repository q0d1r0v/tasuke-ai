import 'package:tasuke_ai/core/permissions/app_permission.dart';

/// The permissions Tasuke AI cannot do its job without, in the order to ask.
///
/// The order is the dependency order. Without the microphone there is no
/// voice capture at all; without notifications nothing rings; exact alarms
/// only decide whether it rings on the minute, which matters only once
/// notifications are on.
const List<AppPermission> kRequiredPermissions = <AppPermission>[
  AppPermission.microphone,
  AppPermission.notifications,
  AppPermission.exactAlarm,
];

/// Whether [state] is a gap worth warning about.
///
/// `restricted` is left out on purpose: that is parental controls or a device
/// policy, which nobody can lift from inside this app. A warning the user
/// cannot act on only teaches them to stop reading warnings.
bool isFixableGap(PermissionState state) =>
    !state.isGranted && state != PermissionState.restricted;
