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
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

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
              final PermissionFailure failure => _WithClose(
                child: _PermissionDenied(
                  permanentlyDenied: failure.permanentlyDenied,
                ),
              ),
              final Failure failure => _WithClose(
                child: _CaptureError(failure: failure),
              ),
              null => _Recording(state: state, controller: controller),
            },
          ),
        ),
      ),
    );
  }
}

/// A failure view with a way out that is not a retry.
///
/// ⚠️ The screen's only back control used to live in [_Recording], and
/// `PopScope(canPop: false)` turns off the iOS back swipe. A user who refused
/// the microphone once was left with "Open Settings" and no way back to their
/// tasks short of killing the app.
class _WithClose extends StatelessWidget {
  const _WithClose({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: context.l10n.actionClose,
            // Through the PopScope above, which cancels and goes Home.
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        Expanded(child: child),
      ],
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
    // ⚠️ Before the microphone opens, which is not "finishing". It can last
    // seconds while the last capture hands the mic back, and showing it as
    // finalising left the user under a spinner with no way out.
    final bool starting =
        state.phase == CapturePhase.checkingQuota ||
        state.phase == CapturePhase.requestingPermission;
    // ⚠️ "Speak naturally" only once the microphone is open. `starting` can
    // last a whole final pass of the last capture, and a user told to speak
    // into a microphone that was not recording lost every word of it. That
    // wait is named instead; the other waits here are too short to need a
    // line. `isTearingDown` is not watched, and need not be: the phase moves
    // on to the permission check as soon as the wait is over, and that
    // rebuilds.
    final String? hint = recording
        ? context.l10n.recordingHint
        : starting
        ? (controller.isTearingDown ? context.l10n.recordingWaitingHint : null)
        : context.l10n.recordingFinishingHint;

    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            // ⚠️ Nothing to go back to once Stop has been pressed: the audio
            // is already being turned into text and there is no microphone to
            // return to.
            onPressed: recording || starting
                ? () => Navigator.of(context).maybePop()
                : null,
            tooltip: context.l10n.actionCancel,
          ),
        ),
        const Spacer(),
        // ⚠️ The title changes the instant Stop is pressed. It used to read
        // "Recording..." over a timer that kept counting and a Stop button
        // that had gone grey — so the one moment the app most needs to look
        // busy was the one moment it looked broken.
        Text(
          recording
              ? context.l10n.recordingTitle
              : starting
              ? context.l10n.recordingStarting
              : context.l10n.recordingFinishing,
          style: TasukeTypography.titleMd,
        ),
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
        else if (hint != null)
          Text(
            hint,
            style: TasukeTypography.bodySm,
            textAlign: TextAlign.center,
          ),
        const Spacer(flex: 2),
        // ⚠️ The controls are replaced, not merely disabled. Two grey buttons
        // say "nothing is happening"; a spinner says "wait". Finalising is a
        // real wait — whisper decodes the whole recording once more after the
        // microphone closes — and it is the wait the user is most likely to
        // read as a hang.
        //
        // Before the mic opens, Cancel is live and Stop waits: there is
        // nothing to stop yet, and the row keeps its place for when there is.
        if (recording || starting)
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
          )
        else
          const _Finalising(),
        const SizedBox(height: TasukeSpacing.xxl),
      ],
    );
  }
}

/// What the Stop / Cancel row becomes while the transcript is being written.
///
/// ⚠️ Exactly [TasukeMetrics.controlHeight] tall, so swapping it in does not
/// move the waveform, the orb or the transcript up the page at the very moment
/// the user is reading them.
class _Finalising extends StatelessWidget {
  const _Finalising();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TasukeMetrics.controlHeight,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox.square(
              dimension: TasukeSpacing.xl,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: TasukeSpacing.md),
            Text(
              context.l10n.recordingFinishing,
              style: TasukeTypography.bodyMd,
            ),
          ],
        ),
      ),
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
        // Held before `reset`, for the reason on [_CaptureError]'s Try again.
        final GoRouter router = GoRouter.of(context);
        controller.reset();
        final String? destination = await controller.begin();
        if (destination != null) router.go(destination);
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
    // A typed task is a capture too (a product decision, 2026-09-23), so a
    // free user who has spent the day's capture is not offered one here: that
    // save would be a second. `begin` checks the quota before anything can
    // fail, so this is the backstop, not the gate.
    final bool quotaSpent =
        !ref.watch(isProProvider) &&
        (ref.watch(todayUsageProvider).value?.captureCount ?? 0) >=
            ExtractionDefaults.freeDailyCaptures;

    final (String title, String message) copy = switch (failure) {
      RecordingFailure(kind: RecordingFailureKind.busy) => (
        context.l10n.errorMicBusyTitle,
        context.l10n.errorMicBusyBody,
      ),
      // Our own last capture, not another app: the busy copy sent the user
      // looking for a call that did not exist.
      RecordingFailure(kind: RecordingFailureKind.stillClosing) => (
        context.l10n.errorStillClosingTitle,
        context.l10n.errorStillClosingBody,
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
      _ => (context.l10n.errorGenericTitle, context.l10n.errorGenericBody),
    };

    return ErrorState(
      title: copy.$1,
      message: copy.$2,
      actionLabel: context.l10n.actionRetry,
      onRetry: () async {
        // ⚠️ Held BEFORE `reset`, and used with no `mounted` check. `reset`
        // clears the failure, so the next frame puts the recording view where
        // this one was. A spent quota's paywall location then came back to a
        // context that was gone, the `go` was skipped, and the user watched
        // "Getting ready" give way to Home with no word of why. A capture
        // location is safe to `go` to as well: the router's redirect decides
        // which capture screen is really up.
        final GoRouter router = GoRouter.of(context);
        controller.reset();
        final String? destination = await controller.begin();
        if (destination != null) router.go(destination);
      },
      // ⚠️ Every capture failure offers this while the quota lasts. A user
      // who just spoke and was told "no" must never be left with nothing to
      // do but say it again. Out of quota, "Try again" leads to the paywall.
      secondaryLabel: quotaSpent ? null : context.l10n.errorTypeInstead,
      onSecondary: quotaSpent
          ? null
          : () {
              controller.startManualDraft();
              context.go('/capture/confirm');
            },
    );
  }
}
