import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// Where one row of the Processing checklist is.
enum ProcessingStepState { pending, active, done }

/// A checklist row, as data.
///
/// Plain values rather than widgets so the Processing controller can build the
/// whole list in one expression and a test can assert on it without pumping.
@immutable
class ProcessingStepView {
  const ProcessingStepView({required this.label, required this.state});

  final String label;
  final ProcessingStepState state;

  @override
  bool operator ==(Object other) =>
      other is ProcessingStepView &&
      other.label == label &&
      other.state == state;

  @override
  int get hashCode => Object.hash(label, state);
}

/// The four-row "Transcribing → Understanding → Finding → Almost done" list.
class ProcessingChecklist extends StatelessWidget {
  const ProcessingChecklist({required this.steps, super.key});

  final List<ProcessingStepView> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final ProcessingStepView step in steps)
          _StepRow(key: ValueKey<String>(step.label), step: step),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, super.key});

  final ProcessingStepView step;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = switch (step.state) {
      ProcessingStepState.pending => TasukeColors.inkFaint,
      ProcessingStepState.active => TasukeColors.ink,
      ProcessingStepState.done => TasukeColors.inkBody,
    };

    return Semantics(
      // Announced as it becomes current, so the screen is not silence for the
      // several seconds extraction takes.
      liveRegion: step.state == ProcessingStepState.active,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TasukeSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox.square(
              dimension: TasukeMetrics.checkCircle,
              child: AnimatedSwitcher(
                duration: TasukeDurations.normal,
                child: _Indicator(
                  key: ValueKey<ProcessingStepState>(step.state),
                  state: step.state,
                ),
              ),
            ),
            const SizedBox(width: TasukeSpacing.md),
            Expanded(
              child: Text(
                step.label,
                style: TasukeTypography.bodyMd.copyWith(color: labelColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.state, super.key});

  final ProcessingStepState state;

  @override
  Widget build(BuildContext context) {
    // The size is restated here because AnimatedSwitcher lays its children out
    // inside a Stack, which loosens the constraints the row's SizedBox handed
    // down — without this the "done" dot shrinks to its tick.
    return SizedBox.square(
      dimension: TasukeMetrics.checkCircle,
      child: switch (state) {
        ProcessingStepState.done => const DecoratedBox(
          decoration: BoxDecoration(
            color: TasukeColors.success,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.check_rounded,
              size: TasukeSpacing.lg,
              color: TasukeColors.onPrimary,
            ),
          ),
        ),
        ProcessingStepState.active => const Padding(
          padding: EdgeInsets.all(TasukeSpacing.xs / 2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        ProcessingStepState.pending => const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: TasukeColors.outlineSoft, width: 1.5),
            ),
          ),
        ),
      },
    );
  }
}
