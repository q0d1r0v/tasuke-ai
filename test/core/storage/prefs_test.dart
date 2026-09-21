import 'package:flutter_riverpod/flutter_riverpod.dart';
// riverpod 3.x exports `Override` only from `misc.dart`; naming it without this
// reads as a missing dependency rather than a missing import.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';

/// These two flags are the router's, and the router reads them synchronously —
/// so the properties worth pinning are "the value is there before the first
/// frame" and "it is true the instant `complete()` returns control", not
/// eventually.
void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  test('sharedPreferencesProvider throws until main() overrides it', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    // riverpod 3 wraps a provider's build error, so the assertion is on the
    // message: what matters is that the failure names the missing override
    // rather than surfacing as a null or a default somewhere downstream.
    expect(
      () => container.read(sharedPreferencesProvider),
      throwsA(
        predicate<Object>(
          (Object error) => error.toString().contains('overridden in main()'),
        ),
      ),
    );
  });

  test('both flags start false on a fresh install', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});

    expect(container.read(onboardingSeenProvider), isFalse);
    expect(container.read(permissionsPrimerSeenProvider), isFalse);
  });

  test('a stored flag is readable synchronously on the first read', () async {
    final ProviderContainer container = await containerWith(<String, Object>{
      PrefKeys.onboardingSeen: true,
    });

    // No await between the container and the answer — this is the whole reason
    // these two live outside Drift.
    expect(container.read(onboardingSeenProvider), isTrue);
    expect(container.read(permissionsPrimerSeenProvider), isFalse);
  });

  test('complete() flips the state before the disk write is awaited', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});

    final Future<void> write = container
        .read(onboardingSeenProvider.notifier)
        .complete();

    // The redirect that runs on this frame must already see `true`.
    expect(container.read(onboardingSeenProvider), isTrue);
    await write;
  });

  test('complete() persists, so the next launch skips onboarding', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});
    await container.read(onboardingSeenProvider.notifier).complete();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefKeys.onboardingSeen), isTrue);
  });

  test('the two flags are independent', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});

    await container.read(permissionsPrimerSeenProvider.notifier).complete();

    expect(container.read(permissionsPrimerSeenProvider), isTrue);
    expect(container.read(onboardingSeenProvider), isFalse);
  });

  test('complete() twice is harmless', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});

    await container.read(onboardingSeenProvider.notifier).complete();
    await container.read(onboardingSeenProvider.notifier).complete();

    expect(container.read(onboardingSeenProvider), isTrue);
  });
}
