import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';

void main() {
  ProviderContainer containerWith(List<Override> overrides) {
    final ProviderContainer container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  group('the whisper copy', () {
    Future<String> whisperPathOn(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      return containerWith(<Override>[
        supportDirPathProvider.overrideWithValue(() async => '/support'),
        cacheDirPathProvider.overrideWithValue(() async => '/cache'),
      ]).read(whisperModelAssetProvider).filePath();
    }

    test('lives in files/models/ on Android, not in cacheDir', () async {
      // ⚠️ Android trims cacheDir on its own when storage runs low, and every
      // mic tap would copy 57 MB again. files/models/ is out of backups too.
      expect(
        await whisperPathOn(TargetPlatform.android),
        '/support/models/${TasukeModels.whisperFileName}',
      );
    });

    test('lives in Library/Caches on iOS, out of iCloud backup', () async {
      expect(
        await whisperPathOn(TargetPlatform.iOS),
        '/cache/${TasukeModels.whisperFileName}',
      );
    });
  });
}
