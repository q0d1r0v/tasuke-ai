import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasuke_ai/core/models/http_model_installer.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';

/// Where the app's private files live, resolved once.
///
/// Exposed as a **resolver** rather than as a `FutureProvider<Directory>` so the
/// things that need it — the installer and the whisper asset — stay synchronous
/// to construct. A provider that must be awaited before anything can be built
/// turns every consumer into an `AsyncValue`, all the way up to the router.
///
/// Application support, not documents: iOS backs documents up to iCloud, and a
/// 219 MB model that can be re-downloaded has no business in anyone's backup.
final Provider<Future<String> Function()> supportDirPathProvider =
    Provider<Future<String> Function()>((Ref ref) {
      Future<String>? resolved;
      return () => resolved ??= getApplicationSupportDirectory().then(
        (Directory directory) => directory.path,
      );
    });

/// The user-facing strings a failed install renders with. Overridden from
/// `AppLocalizations` once the app has one — see [ModelInstallerMessages].
final Provider<ModelInstallerMessages> modelInstallerMessagesProvider =
    Provider<ModelInstallerMessages>(
      (Ref ref) => const ModelInstallerMessages(),
    );

/// The download port. Tests override this with a fake that reports states.
final Provider<ModelInstaller> modelInstallerProvider =
    Provider<ModelInstaller>((Ref ref) {
      final HttpModelInstaller installer = HttpModelInstaller(
        supportDirPath: ref.watch(supportDirPathProvider),
        messages: ref.watch(modelInstallerMessagesProvider),
      );
      ref.onDispose(() => unawaited(installer.dispose()));
      return installer;
    });

/// The bundled whisper model, copied out of assets on first use.
final Provider<WhisperModelAsset> whisperModelAssetProvider =
    Provider<WhisperModelAsset>(
      (Ref ref) =>
          WhisperModelAsset(supportDirPath: ref.watch(supportDirPathProvider)),
    );

/// The extractor model's live state, for the Model Setup screen and for the
/// capture pipeline's "is the AI ready" check.
final StreamProvider<ModelState> extractorModelStateProvider =
    StreamProvider<ModelState>(
      (Ref ref) =>
          ref.watch(modelInstallerProvider).watch(TasukeModels.extractor),
    );

/// The extractor model's path, or null while it is still downloading.
final FutureProvider<String?>
extractorModelPathProvider = FutureProvider<String?>((Ref ref) {
  // Re-resolved whenever the state changes, so the extractor picks the file up
  // the moment the download finishes rather than at the next cold start.
  ref.watch(extractorModelStateProvider);
  return ref.watch(modelInstallerProvider).pathOf(TasukeModels.extractor);
});
