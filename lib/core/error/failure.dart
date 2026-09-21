/// Everything that can go wrong in Tasuke AI.
///
/// ⚠️ There is deliberately **no `NetworkFailure`**, no connectivity plugin and
/// no retry banner. The app makes exactly one network request in its lifetime —
/// downloading the AI model — and that has its own [ModelFailure] arm with its
/// own screen. Every other operation is local.
///
/// The next person to add a feature will reach for a generic network failure
/// out of habit, and half the app will grow an offline state it can never
/// enter. Do not add one.
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// The microphone, notifications or exact alarms were refused.
final class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {required this.permanentlyDenied});

  /// When true the OS will not prompt again and the only route is Settings.
  final bool permanentlyDenied;
}

/// Audio capture itself failed — the mic is busy, or the platform refused.
final class RecordingFailure extends Failure {
  const RecordingFailure(
    super.message, {
    this.kind = RecordingFailureKind.unknown,
  });

  final RecordingFailureKind kind;
}

enum RecordingFailureKind { busy, tooShort, noInput, unknown }

/// Speech-to-text failed, or produced nothing usable.
final class TranscriptionFailure extends Failure {
  const TranscriptionFailure(
    super.message, {
    this.kind = TranscriptionFailureKind.unknown,
  });

  final TranscriptionFailureKind kind;
}

enum TranscriptionFailureKind {
  /// The user said nothing, or only noise.
  noSpeech,

  /// The bundled whisper model is missing or corrupt on disk.
  modelUnavailable,
  unknown,
}

/// The extractor could not turn a transcript into tasks.
final class ExtractionFailure extends Failure {
  const ExtractionFailure(
    super.message, {
    this.kind = ExtractionFailureKind.unknown,
  });

  final ExtractionFailureKind kind;
}

enum ExtractionFailureKind {
  /// The model file has not been downloaded yet.
  modelNotInstalled,

  /// The model produced output that did not survive validation, twice.
  invalidOutput,

  /// Inference ran past its budget.
  timeout,
  unknown,
}

/// Downloading or verifying the language model failed. The one place the word
/// "network" legitimately appears.
final class ModelFailure extends Failure {
  const ModelFailure(super.message, {required this.kind});

  final ModelFailureKind kind;
}

enum ModelFailureKind {
  network,
  checksumMismatch,
  insufficientStorage,
  cancelled,
  unknown,
}

/// A database read or write failed.
final class StorageFailure extends Failure {
  const StorageFailure(super.message, {this.diskFull = false});

  final bool diskFull;
}

/// Scheduling a reminder with the OS failed.
final class SchedulingFailure extends Failure {
  const SchedulingFailure(super.message);
}

/// A store operation failed.
final class PurchaseFailure extends Failure {
  const PurchaseFailure(super.message, {required this.kind});

  final PurchaseFailureKind kind;
}

enum PurchaseFailureKind {
  storeUnavailable,
  productNotFound,
  cancelled,
  pending,
  unknown,
}

/// The free daily voice quota is exhausted.
final class QuotaFailure extends Failure {
  const QuotaFailure(super.message, {required this.used, required this.limit});

  final int used;
  final int limit;
}
