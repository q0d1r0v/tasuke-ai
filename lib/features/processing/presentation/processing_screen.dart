import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';

/// The "Turning your thoughts into tasks…" screen.
///
/// Its four rows advance on a minimum dwell rather than purely on the
/// pipeline's real phase: on a fast device transcription and extraction can
/// both finish in well under a second, and four rows going green at once reads
/// as a glitch rather than as work being done.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dwell = AnimationController(
    vsync: this,
    duration: TasukeDurations.processingStepDwell * 4,
  )..forward();

  @override
  void dispose() {
    _dwell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CapturePhase phase = ref.watch(
      captureControllerProvider.select((CaptureState s) => s.phase),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        // Captured before the await: after it, `context` may be gone, and the
        // lint cannot prove the State's `mounted` refers to this one.
        final NavigatorState navigator = Navigator.of(context);
        await ref.read(captureControllerProvider.notifier).cancel();
        if (navigator.mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: TasukeColors.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TasukeSpacing.gutter,
            ),
            child: Column(
              children: <Widget>[
                const Spacer(),
                Text(
                  context.l10n.processingTitle,
                  style: TasukeTypography.displayMd,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TasukeSpacing.huge),
                const GradientOrb(size: 180),
                const SizedBox(height: TasukeSpacing.huge),
                AnimatedBuilder(
                  animation: _dwell,
                  builder: (BuildContext context, _) => ProcessingChecklist(
                    steps: _steps(context, phase, _dwell.value),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ProcessingStepView> _steps(
    BuildContext context,
    CapturePhase phase,
    double dwell,
  ) {
    // How far the pipeline really is, as a 0..1 position across the four rows.
    final double real = switch (phase) {
      CapturePhase.transcribing => 0.25,
      CapturePhase.extracting => 0.75,
      CapturePhase.confirming || CapturePhase.saving => 1,
      _ => 0,
    };
    // The slower of the two, so the rows never run ahead of the real work and
    // never finish instantly either.
    final double progress = real < dwell ? real : dwell;

    final List<String> labels = <String>[
      context.l10n.processingStepTranscribe,
      context.l10n.processingStepUnderstand,
      context.l10n.processingStepFind,
      context.l10n.processingStepFinish,
    ];

    return <ProcessingStepView>[
      for (int i = 0; i < labels.length; i++)
        ProcessingStepView(
          label: labels[i],
          state: progress >= (i + 1) / labels.length
              ? ProcessingStepState.done
              : progress >= i / labels.length
              ? ProcessingStepState.active
              : ProcessingStepState.pending,
        ),
    ];
  }
}
