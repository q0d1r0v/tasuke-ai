import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/models/retired_model_sweep.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';

/// The launch sweep for the language model older builds downloaded.
///
/// ⚠️ The file name is spelled out here on purpose. It is what older builds
/// already wrote to people's phones, so the sweep's copy of it must never
/// drift, and this test is what notices if it does.
void main() {
  const String retired = 'LFM2-350M-Extract-Q4_K_M.gguf';

  late Directory support;
  late Directory models;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('tasuke_support_');
    models = await Directory('${support.path}/models').create();
  });

  tearDown(() async {
    if (support.existsSync()) await support.delete(recursive: true);
  });

  test('deletes the model and an unfinished download of it', () async {
    final File model = File('${models.path}/$retired')
      ..writeAsBytesSync(<int>[1]);
    final File part = File('${model.path}.part')..writeAsBytesSync(<int>[1]);

    await removeRetiredExtractorModel(() async => support.path);

    expect(model.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('leaves the whisper copy that shares the directory', () async {
    // On Android the whisper copy lives in the same models/ directory.
    const String whisper = TasukeModels.whisperFileName;
    final File copy = File('${models.path}/$whisper')
      ..writeAsBytesSync(<int>[1]);
    final File stamp = File('${copy.path}.size')..writeAsStringSync('1');
    File('${models.path}/$retired').writeAsBytesSync(<int>[1]);

    await removeRetiredExtractorModel(() async => support.path);

    expect(copy.existsSync(), isTrue);
    expect(stamp.existsSync(), isTrue);
  });

  test('a phone that never had the model is left as it is', () async {
    await models.delete();

    await removeRetiredExtractorModel(() async => support.path);

    expect(Directory('${support.path}/models').existsSync(), isFalse);
  });

  test('a failure is logged, not thrown into the launch', () async {
    await expectLater(
      removeRetiredExtractorModel(
        () async => throw const FileSystemException('no support directory'),
      ),
      completes,
    );
  });
}
