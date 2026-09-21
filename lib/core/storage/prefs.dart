import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';

/// The `SharedPreferences` instance, loaded in `main()` before `runApp`.
///
/// ⚠️ Throws until overridden. That is the point: a `FutureProvider` here would
/// make every reader of a router flag asynchronous, and `GoRouter.redirect` is
/// synchronous. `main()` does
///
/// ```dart
/// // `Override` comes from `package:flutter_riverpod/misc.dart` in 3.x.
/// final SharedPreferences prefs = await SharedPreferences.getInstance();
/// runApp(ProviderScope(
///   overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
///   child: const TasukeApp(),
/// ));
/// ```
///
/// and a missing override then fails loudly on the first frame in debug rather
/// than quietly returning a default in production.
final Provider<SharedPreferences>
sharedPreferencesProvider = Provider<SharedPreferences>(
  (Ref ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() with the instance '
    'loaded before runApp.',
  ),
);

/// A boolean latch stored in `SharedPreferences`.
///
/// ⚠️ **Why these two flags are not in Drift, when everything else is.**
///
/// `GoRouter.redirect` is synchronous and cannot await. A Drift-backed
/// onboarding flag therefore has to be read through an `AsyncValue`, and on the
/// one frame that decides where the app opens that value is still `loading` —
/// so the guard reads a stale default, sends a configured user back to
/// onboarding, and then corrects itself a frame later. The user sees a flash of
/// the wrong screen on every cold start.
///
/// `SharedPreferences` is loaded once in `main()` before `runApp`, so by the
/// time any redirect runs the answer is already in memory and the read is a
/// synchronous map lookup.
///
/// The cost is that these two flags are not covered by "Delete all data" the
/// way the database is — which is why nothing else is allowed in here.
abstract class _PrefFlagController extends Notifier<bool> {
  _PrefFlagController(this._key);

  final String _key;

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  /// Latches the flag on.
  ///
  /// ⚠️ `state` is set **before** the disk write is awaited, and the order
  /// matters: the caller's very next act is a `context.go(...)`, and the
  /// redirect that runs on that frame must already see `true`. Awaiting first
  /// puts a platform-channel round trip between the tap and the navigation,
  /// which on a cold Android start is long enough for the guard to bounce the
  /// user straight back to the screen they just finished.
  Future<void> complete() async {
    if (!state) state = true;
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
  }
}

/// Whether onboarding has been completed.
final class OnboardingSeenController extends _PrefFlagController {
  OnboardingSeenController() : super(PrefKeys.onboardingSeen);
}

/// Whether the permissions primer has been shown.
final class PermissionsPrimerSeenController extends _PrefFlagController {
  PermissionsPrimerSeenController() : super(PrefKeys.permissionsPrimerSeen);
}

final NotifierProvider<OnboardingSeenController, bool> onboardingSeenProvider =
    NotifierProvider<OnboardingSeenController, bool>(
      OnboardingSeenController.new,
    );

final NotifierProvider<PermissionsPrimerSeenController, bool>
permissionsPrimerSeenProvider =
    NotifierProvider<PermissionsPrimerSeenController, bool>(
      PermissionsPrimerSeenController.new,
    );
