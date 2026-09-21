import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';

/// Gets the bundled whisper model out of the asset bundle and onto the
/// filesystem.
///
/// whisper.cpp takes a **path**, and an asset has none: it lives inside the APK
/// or the .app as a compressed blob that only `AssetBundle.load` can read. So
/// the file is copied once, on first launch, into the application-support
/// directory — chosen over the documents directory because iOS backs documents
/// up to iCloud and a 57 MB model that is already inside the binary has no
/// business in anyone's backup quota.
final class WhisperModelAsset {
  WhisperModelAsset({
    required this._supportDirPath,
    AssetBundle? bundle,
    this._assetKey = TasukeModels.whisperAsset,
    this._fileName = TasukeModels.whisperFileName,
  }) : _bundle = bundle ?? rootBundle;

  final Future<String> Function() _supportDirPath;
  final AssetBundle _bundle;
  final String _assetKey;
  final String _fileName;

  /// The absolute path the model will live at, installed or not.
  Future<String> filePath() async => '${await _supportDirPath()}/$_fileName';

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
  Future<String> ensureInstalled() async {
    final String path = await filePath();
    final String? installed = await pathIfInstalled();
    if (installed != null) return installed;

    final File target = File(path);
    final File part = File('$path.part');
    Log.d('copying the whisper model out of the bundle');

    final ByteData data = await _bundle.load(_assetKey);
    final int expected = data.lengthInBytes;

    if (await part.exists()) await part.delete();
    await part.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, expected),
      flush: true,
    );
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
    return path;
  }

  /// Deletes the copy and its stamp. For "delete all data".
  Future<void> remove() async {
    final String path = await filePath();
    for (final File file in <File>[
      File(path),
      File('$path.part'),
      _stampFor(File(path)),
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
