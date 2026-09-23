import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';

/// A recording released before it could be speech.
///
/// ⚠️ This has its own file because the bug it pins was invisible everywhere
/// else. `stop()` used to settle on `CapturePhase.idle` for a too-short clip,
/// reasoning that the recorder was already torn down. But
/// `captureLocationFor(idle)` is null, and the router's guard turns a null
/// allowed-location on a `/capture` path into a bounce to Home — so a user who
/// released Stop half a second early was thrown out of the capture flow with
/// no message, while the Recording screen's own test for the too-short copy
/// kept passing because it was handed the state directly.
void main() {
  test('a clip under the minimum keeps the user in the capture flow', () async {
    final FakeAudioRecorder recorder = FakeAudioRecorder();
    final FakeSpeechRecognizer recognizer = FakeSpeechRecognizer();
    final FakeTaskRepository tasks = FakeTaskRepository();
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final FakeUsageRepository usage = FakeUsageRepository();

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        // The clock never advances, so every recording is zero-length — which
        // is exactly the case under test.
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 3, 11, 10))),
        audioRecorderProvider.overrideWithValue(recorder),
        speechRecognizerProvider.overrideWithValue(recognizer),
        permissionServiceProvider.overrideWithValue(FakePermissionService()),
        primaryTaskExtractorProvider.overrideWithValue(
          FakeTaskExtractor(ready: false),
        ),
        fallbackTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
        taskRepositoryProvider.overrideWithValue(tasks),
        usageRepositoryProvider.overrideWithValue(usage),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(() {
      container.dispose();
      tasks.dispose();
      settings.dispose();
      usage.dispose();
    });

    final CaptureController controller = container.read(
      captureControllerProvider.notifier,
    );

    await controller.begin();
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.recording,
    );

    await controller.stop();

    final CaptureState state = container.read(captureControllerProvider);

    expect(
      state.phase,
      CapturePhase.failed,
      reason: 'idle would bounce the user to Home through the router guard',
    );
    expect(state.failure, isA<RecordingFailure>());
    expect(
      (state.failure! as RecordingFailure).kind,
      RecordingFailureKind.tooShort,
    );

    // `failed` is the one phase the guard leaves alone, which is what keeps the
    // Recording screen on screen to show the hint.
    expect(captureLocationFor(CapturePhase.failed), isNull);

    // ⚠️ And nothing was charged against the daily quota: the user never got a
    // transcript, so they must not have paid a capture for it.
    expect((await usage.read(container.read(todayProvider))).captureCount, 0);
  });
}
