import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';

/// Where the app's private files live, resolved once.
///
/// Exposed as a **resolver** rather than as a `FutureProvider<Directory>` so the
/// whisper asset stays synchronous to construct. A provider that must be
/// awaited before anything can be built turns every consumer into an
/// `AsyncValue`, all the way up to the router.
///
/// ⚠️ This directory IS backed up: iCloud on iOS, Auto Backup (`files/`) on
/// Android. On Android the whisper copy lives in its `models/` subdirectory,
/// which `res/xml/backup_rules.xml` and `data_extraction_rules.xml` exclude.
/// iOS has no such exclusion (that needs native code), which is why the iOS
/// copy goes to [cacheDirPathProvider] instead and nothing large is left here.
final Provider<Future<String> Function()> supportDirPathProvider =
    Provider<Future<String> Function()>((Ref ref) {
      Future<String>? resolved;
      return () => resolved ??= getApplicationSupportDirectory().then(
        (Directory directory) => directory.path,
      );
    });

/// The platform cache directory, resolved once. Home of the whisper copy on
/// iOS, where Library/Caches is left out of iCloud backup.
///
/// ⚠️ The OS may empty it under storage pressure. That is safe only because
/// `VoiceCapturePipeline.startRecording` calls `prepare()`, which re-copies a
/// missing model, before it asks for availability.
final Provider<Future<String> Function()> cacheDirPathProvider =
    Provider<Future<String> Function()>((Ref ref) {
      Future<String>? resolved;
      return () => resolved ??= getApplicationCacheDirectory().then(
        (Directory directory) => directory.path,
      );
    });

/// The bundled whisper model, copied out of assets on first use.
///
/// Into a directory no backup includes: 57 MB the app can re-create from its
/// own bundle pushed Android's Auto Backup past its 25 MB quota, so the task
/// database was never backed up at all. The support directory root is passed
/// only so that a copy an older build left there gets deleted.
///
/// ⚠️ On Android that is `files/models/`, which the backup rules exclude, and
/// not `cacheDir`. Android trims caches on its own once free space drops below
/// about 750 MB, apps over their cache quota first, which one 57 MB file puts
/// the app over. Every mic tap would then copy 57 MB again before recording,
/// or fail for lack of space. iOS empties Library/Caches only when very low on
/// space, and never while the app runs.
final Provider<WhisperModelAsset> whisperModelAssetProvider =
    Provider<WhisperModelAsset>((Ref ref) {
      final Future<String> Function() support = ref.watch(
        supportDirPathProvider,
      );
      return WhisperModelAsset(
        supportDirPath: support,
        copyDirPath: defaultTargetPlatform == TargetPlatform.android
            ? () async => '${await support()}/models'
            : ref.watch(cacheDirPathProvider),
      );
    });
