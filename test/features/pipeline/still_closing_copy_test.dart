import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/capture/presentation/recording_screen.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// What the Recording screen says when the next capture gave up waiting for
/// the last one to let go of the speech model.
///
/// ⚠️ It used to share the busy-microphone copy, "Your microphone is in use:
/// Another app or a call is using it". Nothing else held the microphone; the
/// app's own last decode was still running, and the user went looking for a
/// call that did not exist.
void main() {
  testWidgets('a capture still closing is named as ours, not another app', (
    WidgetTester tester,
  ) async {
    final FakeUsageRepository usage = FakeUsageRepository();
    addTearDown(usage.dispose);

    await pumpScreen(
      tester,
      const RecordingScreen(),
      overrides: <Override>[
        ...defaultOverrides(),
        // The real ones open a database or a model, which deadlocks inside
        // `testWidgets`' FakeAsync.
        usageRepositoryProvider.overrideWithValue(usage),
        primaryTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
        fallbackTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
        captureControllerProvider.overrideWithBuild(
          (Ref ref, CaptureController notifier) => const CaptureState(
            phase: CapturePhase.failed,
            failure: RecordingFailure(
              'The last capture is still closing',
              kind: RecordingFailureKind.stillClosing,
            ),
          ),
        ),
      ],
    );

    final int titles = find
        .text('Finishing your last recording')
        .evaluate()
        .length;
    final int bodies = find.text('Try again in a moment.').evaluate().length;
    final int busy = find.text('Your microphone is in use').evaluate().length;
    final int escapes = find.text('Type a task instead').evaluate().length;

    // Unmounted inside the body: the pipeline's ticker and the orb would
    // otherwise be reported as pending timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(titles, 1);
    expect(bodies, 1);
    expect(busy, 0);
    expect(escapes, 1, reason: 'every capture failure offers a way to type');
  });

  // ⚠️ "Speak naturally" was shown from the first moment of a capture, before
  // any microphone was open to hear it. With no last capture to wait for, the
  // wait line is not shown either: there is nothing to name.
  for (final CapturePhase phase in <CapturePhase>[
    CapturePhase.checkingQuota,
    CapturePhase.requestingPermission,
  ]) {
    testWidgets(
      'before the mic opens (${phase.name}) no one is asked to speak',
      (WidgetTester tester) async {
        final FakeUsageRepository usage = FakeUsageRepository();
        addTearDown(usage.dispose);

        await pumpScreen(
          tester,
          const RecordingScreen(),
          overrides: <Override>[
            ...defaultOverrides(),
            usageRepositoryProvider.overrideWithValue(usage),
            primaryTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
            fallbackTaskExtractorProvider.overrideWithValue(
              FakeTaskExtractor(),
            ),
            captureControllerProvider.overrideWithBuild(
              (Ref ref, CaptureController notifier) =>
                  CaptureState(phase: phase),
            ),
          ],
        );

        final int starting = find.text('Getting ready...').evaluate().length;
        final int speakHints = find
            .text('Speak naturally.\nYou can say multiple tasks at once.')
            .evaluate()
            .length;
        final int waitLines = find
            .text('Finishing your last recording first.')
            .evaluate()
            .length;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(starting, 1);
        expect(speakHints, 0);
        expect(waitLines, 0);
      },
    );
  }
}
