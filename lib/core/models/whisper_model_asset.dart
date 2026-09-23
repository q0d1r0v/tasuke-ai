import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tasuke_ai/core/logging/log.dart';

/// The model files Tasuke AI ships.
abstract final class TasukeModels {
  /// Bundled in the app, copied out of assets on first launch because
  /// whisper.cpp needs a real file path and an asset has none.
  static const String whisperAsset = 'assets/models/ggml-base.en-q5_1.bin';
  static const String whisperFileName = 'ggml-base.en-q5_1.bin';
}

/// Gets the bundled whisper model out of the asset bundle and onto the
/// filesystem.
///
/// whisper.cpp takes a **path**, and an asset has none: it lives inside the APK
/// or the .app, where only `AssetBundle.load` can read it. So the file is
/// copied out on first launch, and again whenever it has gone missing.
///
/// The copy goes to [copyDirPath]: a 57 MB file that is already inside the
/// binary has no business in anyone's backup. The app points it at a directory
/// no backup includes (see `whisperModelAssetProvider`). A copy can still go
/// missing, which is why every path that needs the model re-copies it rather
/// than assuming it is there.
///
/// ⚠️ With no [copyDirPath], the copy goes to [supportDirPath], which is
/// backed up on both platforms. Only the device tests do that; the app passes
/// both, and then a copy an older build left in the support directory is
/// deleted after the next copy.
final class WhisperModelAsset {
  WhisperModelAsset({
    required this._supportDirPath,
    this._copyDirPath,
    AssetBundle? bundle,
    this._assetKey = TasukeModels.whisperAsset,
    this._fileName = TasukeModels.whisperFileName,
  }) : _bundle = bundle ?? rootBundle;

  final Future<String> Function() _supportDirPath;
  final Future<String> Function()? _copyDirPath;
  final AssetBundle _bundle;
  final String _assetKey;
  final String _fileName;

  Future<String> _dirPath() => (_copyDirPath ?? _supportDirPath)();

  /// The absolute path the model will live at, installed or not.
  Future<String> filePath() async => '${await _dirPath()}/$_fileName';

  /// The path, or null when the copy is missing or the wrong size.
  ///
  /// `SpeechRecognizer.availability()` is built on this, which is why it must
  /// not itself copy: reporting availability is a question, not a 57 MB side
  /// effect.
  Future<String?> pathIfInstalled() async {
    final File file = File(await filePath());
    if (!await file.exists()) return null;
    final int? expected = await _readStampedSize(file);
    final int actual = await file.length();
    if (expected == null || expected != actual) {
      Log.w('whisper model is $actual bytes, expected ${expected ?? '?'}');
      return null;
    }
    return file.path;
  }

  /// Copies the model out of the bundle if it is not already there, and returns
  /// its path.
  ///
  /// Two things make an interrupted first launch self-heal rather than leave a
  /// half-file that whisper loads and produces gibberish from:
  ///
  ///  1. the bytes are written to `<name>.part` and **renamed** afterwards, so a
  ///     process killed mid-write leaves no file at the real path at all;
  ///  2. the byte count is stamped into a `<name>.size` sidecar, so every later
  ///     launch can check the size in O(1). Re-reading the asset to compare
  ///     would materialise 57 MB on every cold start to learn a number we
  ///     already knew.
  /// ⚠️ 4 MiB at a time, not one 57 MB `writeAsBytes`.
  ///
  /// A single write makes dart:io serialise the whole buffer into one
  /// IO-service message — a second full-size copy of the model on top of the
  /// one the asset channel just delivered. In chunks, dart:io copies one 4 MiB
  /// view at a time, and on Android the asset itself is a read-only mapping of
  /// the APK, because `build.gradle.kts` stores `.bin` uncompressed. A deflated
  /// entry would be inflated whole, into native memory, on the UI thread.
  static const int _writeChunkBytes = 4 << 20;

  /// The copy currently running, if any.
  ///
  /// ⚠️ Load-bearing. `ensureInstalled` is called from the launch path and
  /// again from `VoiceCapturePipeline.startRecording`, and a user who taps the
  /// mic during first launch triggers both at once. Two concurrent copies both
  /// delete and rewrite the same `.part` file and then both rename it — which
  /// produces a model of exactly the right size and entirely the wrong bytes,
  /// and a `.size` stamp that confirms it. whisper.cpp does not reject such a
  /// file; it transcribes noise.
  Future<String>? _installing;

  Future<String> ensureInstalled() {
    final Future<String>? running = _installing;
    if (running != null) return running;

    final Future<String> next = _ensureInstalled();
    // ⚠️ A block body. `Map`/field clearing inside an arrow `whenComplete`
    // that returns a value makes the outer future wait on it.
    _installing = next;
    unawaited(
      next
          .whenComplete(() {
            _installing = null;
          })
          .catchError((Object _) => ''),
    );
    return next;
  }

  Future<String> _ensureInstalled() async {
    final String path = await filePath();
    final String? installed = await pathIfInstalled();
    if (installed != null) return installed;

    final File target = File(path);
    final File part = File('$path.part');
    Log.d('copying the whisper model out of the bundle');

    final ByteData data = await _bundle.load(_assetKey);
    final int expected = data.lengthInBytes;

    if (await part.exists()) await part.delete();
    // models/ does not exist on first launch, and iOS may have emptied its
    // cache directory since the path was resolved.
    await part.parent.create(recursive: true);
    final IOSink sink = part.openWrite(mode: FileMode.writeOnly);
    try {
      for (int offset = 0; offset < expected; offset += _writeChunkBytes) {
        final int end = offset + _writeChunkBytes > expected
            ? expected
            : offset + _writeChunkBytes;
        // A view over the ByteData the channel already delivered — no copy.
        sink.add(Uint8List.sublistView(data, offset, end));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    final int written = await part.length();
    if (written != expected) {
      await part.delete();
      throw FileSystemException(
        'Wrote $written of $expected bytes of the whisper model',
        part.path,
      );
    }

    if (await target.exists()) await target.delete();
    await part.rename(path);
    await _stampSize(target, expected);
    await _removeStaleSupportCopy();
    return path;
  }

  /// Deletes the copy and its stamp. For "delete all data".
  Future<void> remove() async {
    await _deleteCopyIn(await _dirPath());
    await _removeStaleSupportCopy();
  }

  /// Deletes the copy older builds kept at the root of the support directory,
  /// where it counted against every backup.
  ///
  /// A leftover is not worth failing an install over, so errors are logged.
  Future<void> _removeStaleSupportCopy() async {
    if (_copyDirPath == null) return;
    try {
      final String stale = await _supportDirPath();
      if (stale == await _dirPath()) return;
      await _deleteCopyIn(stale);
    } on Object catch (error, stack) {
      Log.e('removing the old whisper copy failed', error, stack);
    }
  }

  Future<void> _deleteCopyIn(String dir) async {
    final File model = File('$dir/$_fileName');
    for (final File file in <File>[
      model,
      File('${model.path}.part'),
      _stampFor(model),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  File _stampFor(File model) => File('${model.path}.size');

  Future<int?> _readStampedSize(File model) async {
    final File stamp = _stampFor(model);
    if (!await stamp.exists()) return null;
    return int.tryParse((await stamp.readAsString()).trim());
  }

  Future<void> _stampSize(File model, int bytes) =>
      _stampFor(model).writeAsString('$bytes', flush: true);
}
