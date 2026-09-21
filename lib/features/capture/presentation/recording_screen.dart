import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';

class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CaptureState state = ref.watch(captureControllerProvider);
    final CaptureController controller = ref.read(
      captureControllerProvider.notifier,
    );

    return PopScope(
      // Back means "cancel this session", not "pop a page the pipeline still
      // thinks is live".
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        await controller.cancel();
        if (context.mounted) context.go('/home');
      },
      child: Scaffold(
        backgroundColor: TasukeColors.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TasukeSpacing.gutter,
            ),
            child: switch (state.failure) {
              final PermissionFailure failure => _PermissionDenied(
                permanentlyDenied: failure.permanentlyDenied,
              ),
              final Failure failure => _CaptureError(failure: failure),
              null => _Recording(state: state, controller: controller),
            },
          ),
        ),
      ),
    );
  }
}

class _Recording extends StatelessWidget {
  const _Recording({required this.state, required this.controller});

  final CaptureState state;
  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final bool recording = state.phase == CapturePhase.recording;

    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: context.l10n.actionCancel,
          ),
        ),
        const Spacer(),
        Text(context.l10n.recordingTitle, style: TasukeTypography.titleMd),
        const SizedBox(height: TasukeSpacing.md),
        RecordingTimer(
          elapsed: controller.elapsed,
          valueOf: () => controller.elapsed.value,
        ),
        const SizedBox(height: TasukeSpacing.huge),
        MicOrb(
          amplitude: controller.amplitude,
          levelOf: () => controller.amplitude.level,
        ),
        const SizedBox(height: TasukeSpacing.huge),
        WaveformView(
          amplitude: controller.amplitude,
          samplesOf: () => controller.amplitude.samples,
        ),
        const SizedBox(height: TasukeSpacing.xl),
        if (state.transcript.isNotEmpty)
          Text(
            state.transcript,
            style: TasukeTypography.bodyMd,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          )
        else
          Text(
            context.l10n.recordingHint,
            style: TasukeTypography.bodySm,
            textAlign: TextAlign.center,
          ),
        const Spacer(flex: 2),
        Row(
          children: <Widget>[
            Expanded(
              child: SecondaryButton(
                label: context.l10n.actionCancel,
                onPressed: () async {
                  await controller.cancel();
                  if (context.mounted) context.go('/home');
                },
              ),
            ),
            const SizedBox(width: TasukeSpacing.md),
            Expanded(
              child: DangerButton(
                label: context.l10n.actionStop,
                filled: true,
                onPressed: recording ? () => controller.stop() : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: TasukeSpacing.xxl),
      ],
    );
  }
}

class _PermissionDenied extends ConsumerWidget {
  const _PermissionDenied({required this.permanentlyDenied});

  final bool permanentlyDenied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionDeniedState(
      title: context.l10n.errorMicDeniedTitle,
      message: permanentlyDenied
          ? context.l10n.errorMicPermanentBody
          : context.l10n.errorMicDeniedBody,
      // ⚠️ A permanently denied permission cannot be re-requested — the OS
      // silently no-ops, and a button that does nothing reads as a broken app.
      actionLabel: permanentlyDenied
          ? context.l10n.actionOpenSettings
          : context.l10n.actionAllow,
      onAction: () async {
        final CaptureController controller = ref.read(
          captureControllerProvider.notifier,
        );
        if (permanentlyDenied) {
          await ref.read(permissionServiceProvider).openSettings();
          return;
        }
        controller.reset();
        final String? destination = await controller.begin();
        if (destination != null && context.mounted) context.go(destination);
      },
    );
  }
}

class _CaptureError extends ConsumerWidget {
  const _CaptureError({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CaptureController controller = ref.read(
      captureControllerProvider.notifier,
    );

    final (String title, String message) copy = switch (failure) {
      RecordingFailure(kind: RecordingFailureKind.busy) => (
        context.l10n.errorMicBusyTitle,
        context.l10n.errorMicBusyBody,
      ),
      RecordingFailure(kind: RecordingFailureKind.tooShort) => (
        context.l10n.errorNoSpeechTitle,
        context.l10n.recordingTooShort,
      ),
      TranscriptionFailure(kind: TranscriptionFailureKind.modelUnavailable) => (
        context.l10n.errorModelMissingTitle,
        context.l10n.errorModelMissingBody,
      ),
      TranscriptionFailure(kind: TranscriptionFailureKind.noSpeech) => (
        context.l10n.errorNoSpeechTitle,
        context.l10n.errorNoSpeechBody,
      ),
      ExtractionFailure(kind: ExtractionFailureKind.modelNotInstalled) => (
        context.l10n.errorExtractorNotReadyTitle,
        context.l10n.errorExtractorNotReadyBody,
      ),
      _ => (context.l10n.errorGenericTitle, context.l10n.errorGenericBody),
    };

    return ErrorState(
      title: copy.$1,
      message: copy.$2,
      actionLabel: context.l10n.actionRetry,
      onRetry: () async {
        controller.reset();
        final String? destination = await controller.begin();
        if (destination != null && context.mounted) context.go(destination);
      },
      // ⚠️ Every capture failure offers this. A user who just spoke and was
      // told "no" must never be left with nothing to do but say it again.
      secondaryLabel: context.l10n.errorTypeInstead,
      onSecondary: () {
        controller.startManualDraft();
        context.go('/capture/confirm');
      },
    );
  }
}
