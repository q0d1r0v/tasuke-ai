import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/models/http_model_installer.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';

/// A download server that answers from memory.
final class FakeDownloadClient implements ModelDownloadClient {
  FakeDownloadClient(this.body);

  List<int> body;

  /// Range starts the installer asked for, in order.
  final List<int?> requestedFrom = <int?>[];

  /// Set to false to imitate a server that ignores `Range` and re-sends the
  /// whole file with a 200.
  bool honoursRange = true;

  int statusOverride = 0;
  int chunkSize = 1024;
  void Function(int index)? onChunk;
  bool closed = false;

  @override
  Future<ModelDownloadResponse> get(Uri url, {int? rangeStart}) async {
    requestedFrom.add(rangeStart);
    if (statusOverride != 0) {
      return ModelDownloadResponse(
        statusCode: statusOverride,
        contentLength: 0,
        body: const Stream<List<int>>.empty(),
      );
    }
    final bool partial = honoursRange && rangeStart != null && rangeStart > 0;
    final List<int> payload = partial ? body.sublist(rangeStart) : body;
    return ModelDownloadResponse(
      statusCode: partial ? 206 : 200,
      contentLength: payload.length,
      body: _chunks(payload),
    );
  }

  Stream<List<int>> _chunks(List<int> payload) async* {
    int index = 0;
    for (int offset = 0; offset < payload.length; offset += chunkSize) {
      onChunk?.call(index++);
      yield payload.sublist(
        offset,
        math.min(offset + chunkSize, payload.length),
      );
      // A real socket never delivers a whole file in one microtask, and
      // cancellation is only observable between chunks.
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void close() => closed = true;
}

void main() {
  late Directory root;
  late List<int> payload;
  late String digest;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tasuke_models_');
    payload = List<int>.generate(8192, (int i) => i % 251);
    digest = sha256.convert(payload).toString();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  ModelSpec specFor({String? sha, int? size}) => ModelSpec(
    id: 'test-model',
    fileName: 'test.gguf',
    url: 'https://example.invalid/test.gguf',
    sha256: sha ?? digest,
    sizeBytes: size ?? payload.length,
  );

  HttpModelInstaller installerWith(FakeDownloadClient client) =>
      HttpModelInstaller(supportDirPath: () async => root.path, client: client);

  File partFile() => File('${root.path}/models/test.gguf.part');

  File finalFile() => File('${root.path}/models/test.gguf');

  test('a clean download verifies and lands at the final path', () async {
    final FakeDownloadClient client = FakeDownloadClient(payload);
    final HttpModelInstaller installer = installerWith(client);
    final ModelSpec spec = specFor();

    final List<ModelState> states = <ModelState>[];
    final StreamSubscription<ModelState> sub = installer
        .watch(spec)
        .listen(states.add);

    await installer.install(spec);
    await Future<void>.delayed(Duration.zero);

    expect(finalFile().existsSync(), isTrue);
    expect(finalFile().readAsBytesSync(), payload);
    expect(partFile().existsSync(), isFalse);
    expect(states.last, isA<ModelReady>());
    expect(states.whereType<ModelDownloading>(), isNotEmpty);
    expect(await installer.pathOf(spec), finalFile().path);

    await sub.cancel();
    await installer.dispose();
  });

  group('resume', () {
    test('asks for the remainder and joins it to what is on disk', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      await partFile().parent.create(recursive: true);
      await partFile().writeAsBytes(payload.sublist(0, 3000));

      await installer.install(spec);

      expect(client.requestedFrom, <int?>[3000]);
      expect(finalFile().readAsBytesSync(), payload);
      expect(installer.stateOf(spec), isA<ModelReady>());
      await installer.dispose();
    });

    test('starts over when the server ignores the Range header', () async {
      // ⚠️ The dangerous case. A 200 carries the WHOLE file; appending it to
      // what is already on disk produces a file of plausible length and total
      // garbage, and a GGUF loader does not reject garbage — it generates it.
      final FakeDownloadClient client = FakeDownloadClient(payload)
        ..honoursRange = false;
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      await partFile().parent.create(recursive: true);
      await partFile().writeAsBytes(payload.sublist(0, 3000));

      await installer.install(spec);

      expect(client.requestedFrom, <int?>[3000]);
      expect(
        finalFile().readAsBytesSync().length,
        payload.length,
        reason: 'not payload.length + 3000',
      );
      expect(finalFile().readAsBytesSync(), payload);
      await installer.dispose();
    });
  });

  group('verification', () {
    test('a checksum mismatch deletes the download', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor(sha: 'a' * 64);

      await installer.install(spec);

      expect(finalFile().existsSync(), isFalse);
      expect(partFile().existsSync(), isFalse);
      expect(installer.stateOf(spec), isA<ModelFailed>());
      await installer.dispose();
    });

    test('an empty expected digest falls back to a size check', () async {
      // TasukeModels.extractor ships with sha256 == '' until the digest is
      // pinned. Empty means "verify the size and log what the digest was", not
      // "accept anything".
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor(sha: '');

      await installer.install(spec);

      expect(installer.stateOf(spec), isA<ModelReady>());
      expect(finalFile().readAsBytesSync(), payload);
      await installer.dispose();
    });

    test('an empty digest still rejects a file of the wrong size', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor(sha: '', size: payload.length + 1);

      await installer.install(spec);

      expect(installer.stateOf(spec), isA<ModelFailed>());
      expect(finalFile().existsSync(), isFalse);
      await installer.dispose();
    });
  });

  group('cancellation', () {
    test('keeps the partial file so the next attempt resumes', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload)
        ..chunkSize = 1024;
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      client.onChunk = (int index) {
        if (index == 2) unawaited(installer.cancel(spec));
      };

      await installer.install(spec);

      expect(installer.stateOf(spec), isA<ModelNotInstalled>());
      expect(finalFile().existsSync(), isFalse);
      expect(partFile().existsSync(), isTrue);
      expect(partFile().lengthSync(), greaterThan(0));
      expect(partFile().lengthSync(), lessThan(payload.length));

      // And the retry picks up where it stopped.
      client.onChunk = null;
      final int stoppedAt = partFile().lengthSync();
      await installer.install(spec);

      expect(client.requestedFrom.last, stoppedAt);
      expect(finalFile().readAsBytesSync(), payload);
      await installer.dispose();
    });
  });

  group('failures', () {
    test('a non-2xx response is a failure, not a corrupt file', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload)
        ..statusOverride = 404;
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      await installer.install(spec);

      expect(installer.stateOf(spec), isA<ModelFailed>());
      expect(finalFile().existsSync(), isFalse);
      await installer.dispose();
    });
  });

  group('lifecycle', () {
    test('installing an already-installed model is a no-op', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      await installer.install(spec);
      await installer.install(spec);

      expect(client.requestedFrom, hasLength(1));
      expect(await installer.isInstalled(spec), isTrue);
      await installer.dispose();
    });

    test('remove deletes both the file and any partial', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      await installer.install(spec);
      await installer.remove(spec);

      expect(finalFile().existsSync(), isFalse);
      expect(partFile().existsSync(), isFalse);
      expect(await installer.pathOf(spec), isNull);
      expect(installer.stateOf(spec), isA<ModelNotInstalled>());
      await installer.dispose();
    });

    test('watch replays the current state to a late subscriber', () async {
      final FakeDownloadClient client = FakeDownloadClient(payload);
      final HttpModelInstaller installer = installerWith(client);
      final ModelSpec spec = specFor();

      await installer.install(spec);

      expect(await installer.watch(spec).first, isA<ModelReady>());
      await installer.dispose();
    });
  });
}
