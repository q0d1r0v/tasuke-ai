import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/router/app_navigator.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';

/// Turns a tapped reminder into a task screen.
///
/// ⚠️ This whole path was built and then never connected. Every scheduled
/// alarm already carried `encodeReminderPayload(taskId)`, the plugin already
/// forwarded taps, `/task/:id` was already routed, and `BootstrapResult
/// .launchTaskId` was already decoded — and nothing read any of it. A reminder
/// fired, the user tapped it, and the app opened on Home with no hint which
/// task it was about. For a reminders app that is the primary way back in.
///
/// ⚠️ It lives at the app root and not on the splash. The redirect does a
/// synchronous `ref.read(appBootstrapProvider)` on the very first route
/// resolution, so the bootstrap future can already be `AsyncData` before
/// `SplashScreen` ever builds — a listener there would never fire — and the
/// splash is unmounted the moment the redirect moves on.
class ReminderRouting extends ConsumerStatefulWidget {
  const ReminderRouting({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReminderRouting> createState() => _ReminderRoutingState();
}

class _ReminderRoutingState extends ConsumerState<ReminderRouting> {
  /// The cold-start payload is acted on once per process.
  ///
  /// The splash's retry button and the reset flow both invalidate
  /// [appBootstrapProvider], which re-delivers the same `launchTaskId`.
  bool _launchHandled = false;

  @override
  void initState() {
    super.initState();
    // ⚠️ Read once here as well as listening below, and NOT with
    // `fireImmediately` — `WidgetRef.listen` in riverpod 3 has no such
    // parameter. It matters because the redirect does a synchronous
    // `ref.read(appBootstrapProvider)` on the first route resolution, so the
    // future can already be `AsyncData` by the time this widget mounts and the
    // listener would then never fire at all.
    _handleLaunch(ref.read(appBootstrapProvider));
  }

  void _handleLaunch(AsyncValue<BootstrapResult> boot) {
    final String? taskId = boot.value?.launchTaskId;
    if (taskId == null || _launchHandled) return;
    _launchHandled = true;
    _open(taskId);
  }

  @override
  Widget build(BuildContext context) {
    // Cold start, when the bootstrap resolves after this widget mounted.
    ref.listen<AsyncValue<BootstrapResult>>(
      appBootstrapProvider,
      (AsyncValue<BootstrapResult>? _, AsyncValue<BootstrapResult> next) =>
          _handleLaunch(next),
    );

    // Warm start: the app was already running when the reminder was tapped.
    ref.listen<AsyncValue<NotificationTap>>(notificationTapsProvider, (
      AsyncValue<NotificationTap>? _,
      AsyncValue<NotificationTap> next,
    ) {
      final String? payload = next.value?.payload;
      if (payload == null) return;
      final String? taskId = decodeReminderPayload(payload);
      if (taskId != null) _open(taskId);
    });

    return widget.child;
  }

  void _open(String taskId) {
    // ⚠️ Post-frame, for two reasons. A provider listener can fire during a
    // build, and `go`/`push` mark the Router dirty — "setState() called during
    // build". And on a cold start this runs before the Router below has
    // mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNow(taskId));
    // ⚠️ A post-frame callback does not ask for a frame. A banner tapped while
    // the app is already in front (iOS) changes no lifecycle state, so nothing
    // else draws one: the task opened only on the user's next touch, and then
    // hijacked it. Mid-frame (the cold-start path) this is a no-op. Release
    // only, so no host test sees it: in debug, flutter_riverpod setStates its
    // ProviderScope on every provider change, which draws a frame anyway.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _openNow(String taskId) {
    if (!mounted) return;
    // ⚠️ Respect the first-run gates. Without this the detail page is pushed
    // on top of onboarding, over a user who has not finished setting up.
    if (!ref.read(onboardingSeenProvider) ||
        !ref.read(permissionsPrimerSeenProvider)) {
      return;
    }
    _leaveCapture();
    ref.read(reminderOpenerProvider)(taskId);
  }

  /// Ends a capture the opener's `go('/home')` is about to take off screen.
  ///
  /// ⚠️ `go` replaces the capture pages without popping them, so their
  /// PopScope — the thing that calls `cancel()` — never runs. A tap during a
  /// recording left the microphone open, off screen, until the 60 s auto-stop.
  void _leaveCapture() {
    switch (ref.read(captureControllerProvider).phase) {
      case CapturePhase.checkingQuota ||
          CapturePhase.requestingPermission ||
          CapturePhase.recording ||
          CapturePhase.failed:
        // What the capture screens' back does, which also hands the speech
        // model back after a failure. `begin()` re-checks for a cancel after
        // every await, so one still opening the mic gives up.
        //
        // ⚠️ Not awaited. `cancel()` goes idle at once, but the teardown it
        // returns can take seconds, or never end behind a wedged one: the task
        // opened late over whatever the user had moved on to, or not at all.
        unawaited(ref.read(captureControllerProvider.notifier).cancel());
      case CapturePhase.idle ||
          CapturePhase.transcribing ||
          CapturePhase.extracting ||
          CapturePhase.confirming ||
          CapturePhase.saving:
        // Nothing is recording, and the mic button leads back to the capture.
        break;
    }
  }
}
