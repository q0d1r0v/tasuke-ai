/// The permissions Tasuke AI asks for. Pure Dart, so the domain and the
/// widget tests can talk about them without importing permission_handler.
enum AppPermission {
  microphone,
  notifications,

  /// Android 12+ only. Not a runtime permission in the usual sense: it is a
  /// special access screen, and on iOS it does not exist at all.
  exactAlarm,
}

enum PermissionState {
  /// Never asked.
  notDetermined,
  granted,
  denied,

  /// The OS will not prompt again. The only route is the Settings app —
  /// which is why the UI must swap its button rather than offer a retry that
  /// silently does nothing.
  permanentlyDenied,

  /// iOS parental controls, or an Android device policy.
  restricted,

  /// Not applicable on this platform or OS version (e.g. exactAlarm on iOS).
  notApplicable;

  bool get isGranted =>
      this == PermissionState.granted || this == PermissionState.notApplicable;

  bool get needsSettings =>
      this == PermissionState.permanentlyDenied ||
      this == PermissionState.restricted;
}

abstract interface class PermissionService {
  Future<PermissionState> status(AppPermission permission);

  Future<PermissionState> request(AppPermission permission);

  /// Opens the OS settings page for this app. Returns false if it could not
  /// be opened.
  Future<bool> openSettings();
}
