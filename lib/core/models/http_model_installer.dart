import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';

/// One HTTP response, reduced to the three things a download needs.
final class ModelDownloadResponse {
  const ModelDownloadResponse({
    required this.statusCode,
    required this.contentLength,
    required this.body,
  });

  final int statusCode;

  /// Bytes in **this** response, which for a range request is the remainder and
  /// not the size of the file.
  final int? contentLength;

  final Stream<List<int>> body;
}

/// The only network call Tasuke AI ever makes, as a seam.
///
/// Injectable so `test/core/models/` can prove resume, a checksum mismatch and
/// cancellation without a server — all three are error paths that are otherwise
/// reachable only by pulling a cable at the right moment.
abstract interface class ModelDownloadClient {
  Future<ModelDownloadResponse> get(Uri url, {int? rangeStart});

  void close();
}

/// The user-facing text for a failed install.
///
/// ⚠️ Duplicated from `app_en.arb` (`modelSetupFailed`, `modelSetupNoSpace`,
/// `modelSetupChecksumFailed`) because [ModelFailed] carries a ready-to-render
/// message and this layer has no `BuildContext` to reach `context.l10n` with.
/// The app overrides this object from `AppLocalizations`; the defaults exist so
/// that a state emitted before the first frame is never blank.
final class ModelInstallerMessages {
  const ModelInstallerMessages({
    this.failed = "The download didn't finish",
    this.checksumFailed =
        'The downloaded file was incomplete and has been removed.',
    this.noSpace = "There isn't enough free space for the model.",
  });

  final String failed;
  final String checksumFailed;
  final String noSpace;
}

/// Downloads, verifies and locates the on-device model files.
final class HttpModelInstaller implements ModelInstaller {
  HttpModelInstaller({
    required this._supportDirPath,
    ModelDownloadClient? client,
    this._messages = const ModelInstallerMessages(),
  }) : _client = client ?? HttpModelDownloadClient();

  /// How many bytes between progress events.
  ///
  /// A byte threshold rather than a timer because `DateTime.now()` is banned
  /// outside `core/clock` and taking a [Clock] here to throttle a progress bar
  /// would be ceremony. 512 KiB is roughly 450 events across the extractor
  /// model — smooth, and nowhere near enough to matter.
  static const int progressEveryBytes = 512 * 1024;

  final Future<String> Function() _supportDirPath;
  final ModelDownloadClient _client;
  final ModelInstallerMessages _messages;

  final Map<String, StreamController<ModelState>> _controllers =
      <String, StreamController<ModelState>>{};
  final Map<String, ModelState> _states = <String, ModelState>{};
  final Set<String> _cancelled = <String>{};

  @override
  Stream<ModelState> watch(ModelSpec spec) async* {
    // The current state first: a screen that subscribes after the download
    // finished would otherwise sit on a spinner until something changed.
    yield stateOf(spec);
    yield* _controllerFor(spec).stream;
  }

  @override
  ModelState stateOf(ModelSpec spec) =>
      _states[spec.id] ?? const ModelNotInstalled();

  @override
  Future<bool> isInstalled(ModelSpec spec) async => await pathOf(spec) != null;

  @override
  Future<String?> pathOf(ModelSpec spec) async {
    final File file = File(await _finalPath(spec));
    if (!await file.exists()) return null;
    // ⚠️ Existence, not a size comparison. A file only reaches this path
    // through the atomic rename in [install], and the rename only happens after
    // [_verify] passed — so the size was already checked against the *real*
    // download. Re-checking it against [ModelSpec.sizeBytes] here would turn a
    // stale constant into an infinite re-download loop: verify, rename, reject,
    // download again, forever, on the user's mobile data.
    if (await file.length() == 0) {
      Log.w('${spec.fileName} is empty on disk');
      return null;
    }
    return file.path;
  }

  @override
  Future<void> install(ModelSpec spec) async {
    _cancelled.remove(spec.id);

    final String? already = await pathOf(spec);
    if (already != null) {
      _publish(spec, ModelReady(already));
      return;
    }

    final File part = File('${await _finalPath(spec)}.part');
    await part.parent.create(recursive: true);

    try {
      final int resumeFrom = await part.exists() ? await part.length() : 0;
      if (resumeFrom > 0) {
        Log.d('resuming ${spec.fileName} at $resumeFrom bytes');
      }

      final ModelDownloadResponse response = await _client.get(
        Uri.parse(spec.url),
        rangeStart: resumeFrom > 0 ? resumeFrom : null,
      );

      // ⚠️ A server that does not honour Range answers 200 with the **whole**
      // file. Appending that to what is already on disk produces a file of
      // plausible length and total garbage, which a GGUF loader does not reject
      // — it just generates nonsense. Start over instead.
      final bool append = response.statusCode == 206 && resumeFrom > 0;
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException(
          'The server answered ${response.statusCode}',
          uri: Uri.parse(spec.url),
        );
      }
      if (!append && resumeFrom > 0) {
        Log.w('server ignored the Range header, restarting the download');
        await part.delete();
      }

      final int startedAt = append ? resumeFrom : 0;
      final int total = response.contentLength == null
          ? spec.sizeBytes
          : startedAt + response.contentLength!;

      await _writeBody(
        spec: spec,
        part: part,
        body: response.body,
        startedAt: startedAt,
        total: total,
        append: append,
      );

      if (_cancelled.contains(spec.id)) {
        // The .part file stays on disk. That is the whole point of resume: a
        // user who cancels a 219 MB download on mobile data and restarts it on
        // Wi-Fi should not pay for it twice.
        _publish(spec, const ModelNotInstalled());
        return;
      }

      if (!await _verify(spec, part)) {
        await part.delete();
        _publish(spec, ModelFailed(_messages.checksumFailed));
        return;
      }

      final String finalPath = await _finalPath(spec);
      final File target = File(finalPath);
      if (await target.exists()) await target.delete();
      await part.rename(finalPath);
      _publish(spec, ModelReady(finalPath));
      Log.d('${spec.fileName} installed');
    } on FileSystemException catch (error, stack) {
      Log.e('writing ${spec.fileName} failed', error, stack);
      // ⚠️ `dart:io` exposes no free-space API and this app will not add a
      // plugin to ask one question. The check therefore happens where the truth
      // is — at the write — and ENOSPC (errno 28) is the answer.
      final bool outOfSpace = error.osError?.errorCode == 28;
      _publish(
        spec,
        ModelFailed(outOfSpace ? _messages.noSpace : _messages.failed),
      );
    } on Object catch (error, stack) {
      Log.e('downloading ${spec.fileName} failed', error, stack);
      _publish(spec, ModelFailed(_messages.failed));
    }
  }

  Future<void> _writeBody({
    required ModelSpec spec,
    required File part,
    required Stream<List<int>> body,
    required int startedAt,
    required int total,
    required bool append,
  }) async {
    final IOSink sink = part.openWrite(
      mode: append ? FileMode.writeOnlyAppend : FileMode.writeOnly,
    );
    int received = startedAt;
    int sinceLastEvent = 0;
    _publish(
      spec,
      ModelDownloading(receivedBytes: received, totalBytes: total),
    );

    try {
      await for (final List<int> chunk in body) {
        if (_cancelled.contains(spec.id)) break;
        sink.add(chunk);
        received += chunk.length;
        sinceLastEvent += chunk.length;
        if (sinceLastEvent >= progressEveryBytes) {
          sinceLastEvent = 0;
          _publish(
            spec,
            ModelDownloading(receivedBytes: received, totalBytes: total),
          );
        }
      }
    } finally {
      // flush before close so a cancelled download's .part length is the number
      // the next Range request must ask from.
      await sink.flush();
      await sink.close();
    }
  }

  /// True when the file may be renamed into place.
  ///
  /// ⚠️ [TasukeModels.extractor] currently carries an **empty** `sha256`. An
  /// empty expected digest means "verify the size and log what the digest
  /// actually was, so it can be pinned" — never "skip verification". Silently
  /// accepting anything is how a mirrored or intercepted GGUF gets loaded, and
  /// a wrong constant invented to fill the gap would delete every successful
  /// download instead.
  Future<bool> _verify(ModelSpec spec, File part) async {
    final int length = await part.length();
    final Digest digest = await sha256.bind(part.openRead()).first;

    if (spec.sha256.isEmpty) {
      Log.w(
        'no pinned digest for ${spec.fileName}; '
        'computed sha256=$digest over $length bytes — pin this value',
      );
      return spec.sizeBytes <= 0 || length == spec.sizeBytes;
    }

    if (digest.toString() != spec.sha256.toLowerCase()) {
      Log.e('checksum mismatch for ${spec.fileName}: got $digest');
      return false;
    }
    return true;
  }

  @override
  Future<void> cancel(ModelSpec spec) async {
    _cancelled.add(spec.id);
  }

  @override
  Future<void> remove(ModelSpec spec) async {
    _cancelled.add(spec.id);
    final String path = await _finalPath(spec);
    for (final File file in <File>[File(path), File('$path.part')]) {
      if (await file.exists()) await file.delete();
    }
    _publish(spec, const ModelNotInstalled());
  }

  Future<void> dispose() async {
    _client.close();
    for (final StreamController<ModelState> controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }

  Future<String> _finalPath(ModelSpec spec) async =>
      '${await _supportDirPath()}/models/${spec.fileName}';

  StreamController<ModelState> _controllerFor(ModelSpec spec) => _controllers
      .putIfAbsent(spec.id, () => StreamController<ModelState>.broadcast());

  void _publish(ModelSpec spec, ModelState state) {
    _states[spec.id] = state;
    final StreamController<ModelState> controller = _controllerFor(spec);
    if (!controller.isClosed) controller.add(state);
  }
}

/// The one importer of `package:http`.
final class HttpModelDownloadClient implements ModelDownloadClient {
  HttpModelDownloadClient({http.Client? inner})
    : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<ModelDownloadResponse> get(Uri url, {int? rangeStart}) async {
    final http.Request request = http.Request('GET', url);
    if (rangeStart != null && rangeStart > 0) {
      // Open-ended on purpose: "give me everything from here", so the request
      // does not have to know the total size to resume.
      request.headers['Range'] = 'bytes=$rangeStart-';
    }
    final http.StreamedResponse response = await _inner.send(request);
    return ModelDownloadResponse(
      statusCode: response.statusCode,
      contentLength: response.contentLength,
      body: response.stream,
    );
  }

  @override
  void close() => _inner.close();
}
