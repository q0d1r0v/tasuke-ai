import 'dart:io';

import 'package:tasuke_ai/core/logging/log.dart';

/// The file older builds downloaded the extractor model to, under
/// `<support>/models/`. Frozen: it names what is already on people's phones,
/// not anything this build ships.
const String _retiredModelFileName = 'LFM2-350M-Extract-Q4_K_M.gguf';

/// Deletes the language model an older build downloaded, and any unfinished
/// download of it.
///
/// Task extraction used to run through an on-device model (219 MB) until the
/// rules beat it and it was removed (see `primaryTaskExtractorProvider`). A
/// phone that ran such a build still has the file, and nothing else will ever
/// delete it: an app update keeps the app's files, "Delete all data" clears the
/// database only, and `WhisperModelAsset` deletes only its own copy. On iOS the
/// support directory is also in the iCloud backup.
///
/// ⚠️ Every launch, not once behind a flag. Two `stat` calls cost less than a
/// preference kept forever, and a flag written before a failed delete would
/// leave the file for good.
///
/// A leftover is not worth failing a launch over, so errors are logged, never
/// thrown.
Future<void> removeRetiredExtractorModel(
  Future<String> Function() supportDirPath,
) async {
  try {
    final File model = File(
      '${await supportDirPath()}/models/$_retiredModelFileName',
    );
    for (final File file in <File>[model, File('${model.path}.part')]) {
      if (await file.exists()) {
        await file.delete();
        Log.d('deleted the retired extractor model: ${file.path}');
      }
    }
  } on Object catch (error, stack) {
    Log.e('removing the retired extractor model failed', error, stack);
  }
}
