/// Where the language model is in its lifecycle.
sealed class ModelState {
  const ModelState();
}

/// Never started.
final class ModelNotInstalled extends ModelState {
  const ModelNotInstalled();
}

/// Downloading. [progress] is 0..1, or null while the server has not reported
/// a content length.
final class ModelDownloading extends ModelState {
  const ModelDownloading({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get progress =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  int get percent => ((progress ?? 0) * 100).round();
}

/// On disk and checksum-verified.
final class ModelReady extends ModelState {
  const ModelReady(this.path);

  final String path;
}

/// The last attempt failed. [message] is already user-facing.
final class ModelFailed extends ModelState {
  const ModelFailed(this.message, {this.canRetry = true});

  final String message;
  final bool canRetry;
}

/// A model file the app needs on disk.
final class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  final String id;
  final String fileName;
  final String url;

  /// Lowercase hex. A download that does not match it is deleted rather than
  /// used: a truncated GGUF does not fail loudly, it produces garbage.
  final String sha256;

  final int sizeBytes;

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).round()} MB';
}

/// Downloads, verifies and locates the on-device model files.
abstract interface class ModelInstaller {
  /// The live state of [spec].
  Stream<ModelState> watch(ModelSpec spec);

  ModelState stateOf(ModelSpec spec);

  /// Whether the file is present and verified.
  Future<bool> isInstalled(ModelSpec spec);

  /// The absolute path, or null when not installed.
  Future<String?> pathOf(ModelSpec spec);

  /// Downloads with resume support. Safe to call when already installed.
  Future<void> install(ModelSpec spec);

  Future<void> cancel(ModelSpec spec);

  Future<void> remove(ModelSpec spec);
}

/// The model files Tasuke AI uses.
abstract final class TasukeModels {
  /// Bundled in the app, copied out of assets on first launch because
  /// whisper.cpp needs a real file path and an asset has none.
  static const String whisperAsset = 'assets/models/ggml-base.en-q5_1.bin';
  static const String whisperFileName = 'ggml-base.en-q5_1.bin';

  /// Downloaded on first launch.
  ///
  /// LFM2-350M-Extract is fine-tuned for exactly this job — pulling structured
  /// JSON out of unstructured text — which is why a 350M model is enough here
  /// when a general 350M model would not be.
  static const ModelSpec extractor = ModelSpec(
    id: 'lfm2-350m-extract-q4km',
    fileName: 'LFM2-350M-Extract-Q4_K_M.gguf',
    url:
        'https://huggingface.co/LiquidAI/LFM2-350M-Extract-GGUF/resolve/main/'
        'LFM2-350M-Extract-Q4_K_M.gguf',
    // Measured with tool/refresh_model_checksums.sh on 2026-09-21.
    //
    // ⚠️ Never guess or hand-edit this. ModelInstaller deletes any download
    // whose digest does not match, so a wrong constant is not a warning — it is
    // an app that fetches 219 MB, deletes it, and shows the checksum error
    // forever, on every device, with no way past it.
    //
    // ⚠️ HuggingFace `resolve/main` is a MOVING reference. Upstream
    // re-quantising the model changes the bytes under the same URL and every
    // install starts failing at once; re-run the script when that happens.
    sha256: '687a31c3e7864647aa181e1feb156e4e5da33978c174d7dbf0d289f6014a5621',
    sizeBytes: 229310080,
  );
}
