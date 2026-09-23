import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/handler_permission_service.dart';
import 'package:tasuke_ai/core/permissions/required_permissions.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';

/// The permission port. Overridden in widget tests with a fake that answers
/// from a map, so every branch of the Permissions screen is one line to set up.
final Provider<PermissionService> permissionServiceProvider =
    Provider<PermissionService>(
      (Ref ref) => HandlerPermissionService(
        preferences: ref.watch(sharedPreferencesProvider),
      ),
    );

/// The current state of one permission, re-read on demand.
///
/// A `FutureProvider.family` rather than a cached snapshot: a user can leave for
/// the Settings app and come back with a different answer, and the only honest
/// way to know is to ask again. `ref.invalidate` on app resume is what does it.
// The family's own type is not exported by flutter_riverpod, so this one is
// inferred rather than written out.
final permissionStatusProvider =
    FutureProvider.family<PermissionState, AppPermission>(
      (Ref ref, AppPermission permission) =>
          ref.watch(permissionServiceProvider).status(permission),
    );

/// The [kRequiredPermissions] that are off and could be turned on, in order.
///
/// Empty means the app has everything it needs. Derived from
/// [permissionStatusProvider], so the resume-time invalidation that refreshes
/// those after a trip to the Settings app refreshes this too.
final FutureProvider<List<AppPermission>> missingPermissionsProvider =
    FutureProvider<List<AppPermission>>((Ref ref) async {
      final List<PermissionState> states = await Future.wait(
        <Future<PermissionState>>[
          for (final AppPermission permission in kRequiredPermissions)
            ref.watch(permissionStatusProvider(permission).future),
        ],
      );
      return <AppPermission>[
        for (int i = 0; i < kRequiredPermissions.length; i++)
          if (isFixableGap(states[i])) kRequiredPermissions[i],
      ];
    });
