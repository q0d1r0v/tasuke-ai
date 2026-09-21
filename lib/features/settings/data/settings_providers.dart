import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
import 'package:tasuke_ai/features/settings/data/drift_settings_repository.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (Ref ref) => DriftSettingsRepository(
        dao: ref.watch(settingsDaoProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// The concrete repository, for the one caller that needs
/// [DriftSettingsRepository.resetToDefaults].
///
/// ⚠️ Kept off [settingsRepositoryProvider] on purpose: "Delete all data" is
/// the only legitimate caller, and a settings screen that can reach a factory
/// reset through the same object it uses to toggle haptics will eventually do
/// so by accident.
final Provider<DriftSettingsRepository> settingsResetProvider =
    Provider<DriftSettingsRepository>(
      (Ref ref) => DriftSettingsRepository(
        dao: ref.watch(settingsDaoProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// The live settings snapshot.
///
/// A [StreamProvider] rather than a future: settings are written from the
/// Settings screen and read by the notifier scheduler, the capture flow and the
/// theme at the same time, and none of them should have to know when to re-read.
final StreamProvider<AppSettings> appSettingsProvider =
    StreamProvider<AppSettings>(
      (Ref ref) => ref.watch(settingsRepositoryProvider).watch(),
    );
