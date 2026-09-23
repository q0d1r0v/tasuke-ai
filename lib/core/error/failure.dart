/// Everything that can go wrong in Tasuke AI.
///
/// ⚠️ There is deliberately **no `NetworkFailure`**, no connectivity plugin and
/// no retry banner. Everything the app does is local: extraction is rule-based
/// and the speech model ships inside the binary, so nothing the app does needs
/// a network at all.
///
/// The next person to add a feature will reach for a generic network failure
/// out of habit, and half the app will grow an offline state it can never
/// enter. Do not add one.
///
/// There is no extraction failure either. `VoiceCapturePipeline.extract` falls
/// back to the second extractor when the first throws or times out, and turns
/// "no tasks at all" into one editable draft of the raw transcript, so
/// extraction can never end a capture.
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

enum RecordingFailureKind {
  /// Another app or a call holds the microphone.
  busy,

  /// The app's own last capture has not finished letting go of the speech
  /// model. Not [busy]: that copy blames another app, and the user, who had
  /// just backed out of a recording, went looking for one.
  stillClosing,
  tooShort,
  noInput,
  unknown,
}

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
