import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/handler_permission_service.dart';

/// The plugin as it behaves on Android with permission_handler_android 14.x.
///
/// ⚠️ The shape that matters: `status` never says permanentlyDenied — only a
/// request's answer can. The shared FakePermissionService answers like iOS, so
/// UI tests alone could never catch an Android-only dead tap. This fake is the
/// one that can.
///
/// Extends rather than implements the platform class: its constructor carries
/// the token `instance =` verifies, so no mock mixin (and no extra dependency)
/// is needed.
final class AndroidLikePlatform extends PermissionHandlerPlatform {
  final Map<Permission, PermissionStatus> statuses =
      <Permission, PermissionStatus>{};
  final Map<Permission, PermissionStatus> answers =
      <Permission, PermissionStatus>{};
  final List<Permission> requested = <Permission>[];

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    final PermissionStatus status =
        statuses[permission] ?? PermissionStatus.denied;
    // What the plugin's status check can never report on Android.
    return status == PermissionStatus.permanentlyDenied
        ? PermissionStatus.denied
        : status;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requested.addAll(permissions);
    return <Permission, PermissionStatus>{
      for (final Permission p in permissions)
        p: answers[p] ?? statuses[p] ?? PermissionStatus.denied,
    };
  }
}

void main() {
  late AndroidLikePlatform platform;
  late SharedPreferences preferences;

  setUp(() async {
    platform = AndroidLikePlatform();
    PermissionHandlerPlatform.instance = platform;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  HandlerPermissionService android() =>
      HandlerPermissionService(preferences: preferences, isAndroid: true);

  group('a refusal the OS will not prompt for again', () {
    test('is remembered, so the next check says "go to Settings"', () async {
      final HandlerPermissionService service = android();
      platform.answers[Permission.microphone] =
          PermissionStatus.permanentlyDenied;

      expect(
        await service.status(AppPermission.microphone),
        PermissionState.denied,
      );
      expect(
        await service.request(AppPermission.microphone),
        PermissionState.permanentlyDenied,
      );

      // ⚠️ THE assertion. The plugin's status still says plain `denied`; this
      // is what turns the banner's and the card's next tap into Settings
      // instead of a request the OS silently refuses.
      final PermissionState after = await service.status(
        AppPermission.microphone,
      );
      expect(after, PermissionState.permanentlyDenied);
      expect(after.needsSettings, isTrue);
    });

    test('survives a restart of the app', () async {
      platform.answers[Permission.microphone] =
          PermissionStatus.permanentlyDenied;
      await android().request(AppPermission.microphone);

      expect(
        await android().status(AppPermission.microphone),
        PermissionState.permanentlyDenied,
      );
    });

    test('is forgotten once it is granted in Settings', () async {
      final HandlerPermissionService service = android();
      platform.answers[Permission.microphone] =
          PermissionStatus.permanentlyDenied;
      await service.request(AppPermission.microphone);

      platform.statuses[Permission.microphone] = PermissionStatus.granted;
      expect(
        await service.status(AppPermission.microphone),
        PermissionState.granted,
      );

      // Revoked again later: that is a fresh "denied", which the OS may well
      // prompt for, not the old refusal.
      platform.statuses[Permission.microphone] = PermissionStatus.denied;
      await pumpEventQueue();
      expect(
        await service.status(AppPermission.microphone),
        PermissionState.denied,
      );
    });
  });

  test(
    'a first "Don\'t allow" on the microphone is not a refusal for good',
    () async {
      // Android shows the dialog once more after a first denial.
      final HandlerPermissionService service = android();
      platform.answers[Permission.microphone] = PermissionStatus.denied;

      await service.request(AppPermission.microphone);

      expect(
        await service.status(AppPermission.microphone),
        PermissionState.denied,
      );
    },
  );

  test('notifications refused on Android go to Settings next time', () async {
    // Below Android 13 there is no notification prompt at all: the plugin
    // answers `denied` at once. A banner that re-requested would do nothing.
    final HandlerPermissionService service = android();
    platform.answers[Permission.notification] = PermissionStatus.denied;

    await service.request(AppPermission.notifications);

    expect(
      await service.status(AppPermission.notifications),
      PermissionState.permanentlyDenied,
    );
  });

  test('exact alarms are never remembered: their request IS the fix', () async {
    // Requesting SCHEDULE_EXACT_ALARM opens the "Alarms & reminders" page.
    // Remembering a refusal would send the user to the wrong page instead.
    final HandlerPermissionService service = android();
    platform.answers[Permission.scheduleExactAlarm] =
        PermissionStatus.permanentlyDenied;

    await service.request(AppPermission.exactAlarm);

    expect(
      await service.status(AppPermission.exactAlarm),
      PermissionState.denied,
    );
  });

  test('exact alarms do not exist off Android', () async {
    final HandlerPermissionService service = HandlerPermissionService(
      preferences: preferences,
      isAndroid: false,
    );

    expect(
      await service.status(AppPermission.exactAlarm),
      PermissionState.notApplicable,
    );
  });
}
