/// Where the voice pipeline is.
///
/// The **router** owns which capture screen is on screen; this enum only says
/// what the pipeline is doing. That inversion is what makes every capture
/// screen independently pumpable in a test, and what makes a cold-start deep
/// link into `/capture/confirm` land on Home instead of on a confirm screen
/// with nothing to confirm.
enum CapturePhase {
  idle,
  checkingQuota,
  requestingPermission,
  recording,
  transcribing,
  extracting,
  confirming,
  saving,
  failed;

  bool get isBusy =>
      this == CapturePhase.transcribing ||
      this == CapturePhase.extracting ||
      this == CapturePhase.saving;

  bool get isActive => this != CapturePhase.idle;
}

/// The phase → location table, stated once.
///
/// Returns null when no capture screen should be showing, which the guard
/// turns into a bounce to Home.
String? captureLocationFor(CapturePhase phase) => switch (phase) {
  CapturePhase.idle => null,
  CapturePhase.checkingQuota ||
  CapturePhase.requestingPermission ||
  CapturePhase.recording => '/capture',
  CapturePhase.transcribing || CapturePhase.extracting => '/capture/processing',
  CapturePhase.confirming || CapturePhase.saving => '/capture/confirm',
  // A failure stays wherever it happened; the screen renders ErrorState. The
  // guard's one exception is Processing, which it sends back to Recording.
  CapturePhase.failed => null,
};
