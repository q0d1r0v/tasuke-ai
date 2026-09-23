import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';

import '../../app/platform/native_source.dart';

/// An asset bundle that serves one model from memory and counts the reads.
final class _ModelBundle extends CachingAssetBundle {
  _ModelBundle(this.bytes);

  final List<int> bytes;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// Where the whisper copy lives, and that it survives being deleted.
///
/// ⚠️ It lives where no backup reaches: files/models/ on Android and
/// Library/Caches on iOS (`whisperModelAssetProvider` picks). At the root of
/// the support directory, 57 MB went into every iCloud backup, and on Android
/// it put the app over the 25 MB cloud-backup quota, so the task database was
/// never backed up at all. iOS may empty its cache, which is only safe because
/// a missing copy is made again.
void main() {
  const String name = TasukeModels.whisperFileName;

  late Directory support;
  late Directory cache;
  late List<int> model;
  late _ModelBundle bundle;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('tasuke_support_');
    cache = await Directory.systemTemp.createTemp('tasuke_cache_');
    model = List<int>.generate(10000, (int i) => i % 253);
    bundle = _ModelBundle(model);
  });

  tearDown(() async {
    for (final Directory dir in <Directory>[support, cache]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  WhisperModelAsset asset({bool withCache = true}) => WhisperModelAsset(
    supportDirPath: () async => support.path,
    copyDirPath: withCache ? () async => cache.path : null,
    bundle: bundle,
  );

  test('copies into its own directory, not the backed-up one', () async {
    final String path = await asset().ensureInstalled();

    expect(path, '${cache.path}/$name');
    expect(File(path).readAsBytesSync(), model);
    expect(File('${support.path}/$name').existsSync(), isFalse);
  });

  test('deletes the copy an older build left in the support dir', () async {
    for (final String file in <String>[name, '$name.size', '$name.part']) {
      File('${support.path}/$file').writeAsStringSync('stale');
    }

    await asset().ensureInstalled();

    expect(support.listSync(), isEmpty);
    expect(File('${cache.path}/$name').existsSync(), isTrue);
  });

  test('copies again after the directory was emptied', () async {
    final WhisperModelAsset whisper = asset();
    final String path = await whisper.ensureInstalled();

    // What iOS may do to Library/Caches under storage pressure.
    await cache.delete(recursive: true);
    expect(
      await whisper.pathIfInstalled(),
      isNull,
      reason: 'availability must report the model missing, not a dead path',
    );

    expect(await whisper.ensureInstalled(), path);
    expect(await whisper.pathIfInstalled(), path);
    expect(File(path).readAsBytesSync(), model);
    expect(bundle.loads, 2);
  });

  test('copies again when only the size stamp was lost', () async {
    final WhisperModelAsset whisper = asset();
    final String path = await whisper.ensureInstalled();
    File('$path.size').deleteSync();

    expect(await whisper.pathIfInstalled(), isNull);
    expect(await whisper.ensureInstalled(), path);
    expect(bundle.loads, 2);
  });

  test('in files/models/, keeps the copy and drops the root one', () async {
    // Android's layout: the copy directory sits inside the support directory,
    // so the cleanup of the old root copy must not reach into it.
    File('${support.path}/$name').writeAsStringSync('stale');
    final WhisperModelAsset whisper = WhisperModelAsset(
      supportDirPath: () async => support.path,
      copyDirPath: () async => '${support.path}/models',
      bundle: bundle,
    );

    final String path = await whisper.ensureInstalled();

    expect(path, '${support.path}/models/$name');
    expect(File('${support.path}/$name').existsSync(), isFalse);
    expect(await whisper.pathIfInstalled(), path);
    expect(File(path).readAsBytesSync(), model);
  });

  test('without a copy dir, the support copy is not "stale"', () async {
    // The device tests build it this way. The cleanup must never delete the
    // copy it has just made.
    final WhisperModelAsset whisper = asset(withCache: false);
    final String path = await whisper.ensureInstalled();

    expect(path, '${support.path}/$name');
    expect(await whisper.pathIfInstalled(), path);
  });

  test('the APK stores the model uncompressed', () {
    // ⚠️ A deflated asset is inflated whole, into native memory, on the UI
    // thread, when it is first loaded. Stored, it is mapped from the APK.
    expect(
      readProjectFile('android/app/build.gradle.kts'),
      contains('noCompress(".bin")'),
    );
    expect(TasukeModels.whisperAsset, endsWith('.bin'));
  });
}
