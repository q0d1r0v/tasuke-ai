import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library — only from
// `misc.dart`. Naming it without this import is a `non_type_as_type_argument`
// error that reads like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/capture/presentation/recording_screen.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

import '../../helpers/fakes.dart';

/// A task store whose write path fails, the way a full disk does.
///
/// Everything else is delegated, so the test exercises the real save path right
/// up to the one call that goes wrong.
final class UnwritableTaskRepository implements TaskRepository {
  UnwritableTaskRepository(this._inner, {this.message = 'write failed'});

  final FakeTaskRepository _inner;
  final String message;

  @override
  Future<List<Task>> saveDrafts(
    List<TaskDraft> drafts, {
    required String captureId,
    required int allDayReminderMinute,
  }) async => throw StateError(message);

  @override
  Stream<List<Task>> watchToday(LocalDate today) => _inner.watchToday(today);

  @override
  Stream<List<TaskGroup>> watchUpcoming(LocalDate today) =>
      _inner.watchUpcoming(today);

  @override
  Stream<List<TaskGroup>> watchCompleted(LocalDate today, {int limit = 200}) =>
      _inner.watchCompleted(today, limit: limit);

  @override
  Stream<List<Task>> watchSomeday() => _inner.watchSomeday();

  @override
  Stream<List<Task>> watchSearch(String query, {int limit = 100}) =>
      _inner.watchSearch(query, limit: limit);

  @override
  Stream<Task?> watchById(String id) => _inner.watchById(id);

  @override
  Future<Task?> findById(String id) => _inner.findById(id);

  @override
  Future<List<Task>> pendingReminders(LocalDateTime from, {int limit = 64}) =>
      _inner.pendingReminders(from, limit: limit);

  @override
  Future<List<Task>> allSchedulable(LocalDateTime from) =>
      _inner.allSchedulable(from);

  @override
  Future<Task> create(TaskDraft draft, {required int allDayReminderMinute}) =>
      _inner.create(draft, allDayReminderMinute: allDayReminderMinute);

  @override
  Future<Task> update(Task task) => _inner.update(task);

  @override
  Future<void> setCompleted(String id, {required bool completed}) =>
      _inner.setCompleted(id, completed: completed);

  @override
  Future<void> delete(String id) => _inner.delete(id);

  @override
  Future<void> deleteAll() => _inner.deleteAll();

  @override
  Stream<TaskStats> watchStats(LocalDate today) => _inner.watchStats(today);
}

/// A usage store that cannot write — the second write of a save, after the
/// tasks' own has already committed.
final class UnwritableUsageRepository implements UsageRepository {
  UnwritableUsageRepository(this._inner);

  final FakeUsageRepository _inner;

  @override
  Future<void> recordCapture(LocalDate day, {required int taskCount}) async =>
      throw StateError('database or disk is full');

  @override
  Future<DailyUsage> read(LocalDate day) => _inner.read(day);

  @override
  Stream<DailyUsage> watchToday(LocalDate today) => _inner.watchToday(today);

  @override
  Future<void> prune(LocalDate today, {int keepDays = 90}) =>
      _inner.prune(today, keepDays: keepDays);
}

/// [FakeSpeechRecognizer] with the four waits a real whisper session has,
/// each of which a test can hold: loading ([prepare]), finalising ([stop]),
/// handing the session back ([cancel]) and letting go of the model
/// ([release]), which is what a save leaves running behind it.
///
/// A held [stop] never finalises, and [cancel] never closes the stream — what a
/// whisper session cancelled mid-decode does — so nothing but the controller's
/// own guards can end a Stop the user cancelled out of.
final class HeldRecognizer implements SpeechRecognizer {
  HeldRecognizer(this.inner);

  final FakeSpeechRecognizer inner;
  Completer<void>? prepareGate;
  Completer<void>? stopGate;
  Completer<void>? cancelGate;
  Completer<void>? releaseGate;
  int cancels = 0;

  @override
  Future<void> prepare() async {
    await inner.prepare();
    final Completer<void>? gate = prepareGate;
    prepareGate = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<SpeechAvailability> availability() => inner.availability();

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) =>
      inner.transcribeStream(pcm16);

  @override
  Future<void> stop() async {
    final Completer<void>? gate = stopGate;
    if (gate == null) return inner.stop();
    stopGate = null;
    await gate.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final Completer<void>? gate = cancelGate;
    cancelGate = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> release() async {
    final Completer<void>? gate = releaseGate;
    releaseGate = null;
    if (gate != null) await gate.future;
    return inner.release();
  }
}

/// An extractor that holds every call until the test opens [gate].
final class GatedExtractor implements TaskExtractor {
  final Completer<void> gate = Completer<void>();

  @override
  Future<bool> isReady() async => true;

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) async {
    await gate.future;
    return const <ExtractedTask>[ExtractedTask(title: 'Call mum')];
  }
}

/// Counts the sweeps the controller asks for.
final class CountingScheduler implements ReminderScheduler {
  int syncs = 0;

  @override
  Future<SyncOutcome> sync() async {
    syncs++;
    return SyncOutcome.noop;
  }

  @override
  Future<void> cancelAll() async {}
}

/// The whole capture stack, over fakes.
final class ControllerRig {
  ControllerRig({
    required this.container,
    required this.clock,
    required this.recorder,
    required this.recognizer,
    required this.tasks,
    required this.usage,
    required this.purchases,
    required this.scheduler,
  });

  final ProviderContainer container;
  final MutableClock clock;
  final FakeAudioRecorder recorder;
  final FakeSpeechRecognizer recognizer;
  final FakeTaskRepository tasks;
  final FakeUsageRepository usage;
  final FakePurchaseGateway purchases;
  final CountingScheduler scheduler;

  CaptureController get controller =>
      container.read(captureControllerProvider.notifier);

  CaptureState get state => container.read(captureControllerProvider);

  LocalDate get today => LocalDate.today(clock.nowLocal());

  /// Speaks for [length] and comes back with drafts on the Confirm screen.
  Future<void> speak({Duration length = const Duration(seconds: 3)}) async {
    await controller.begin();
    clock.advance(length);
    await controller.stop();
  }

  /// Lets the pending microtasks run.
  ///
  /// The recogniser's events reach the controller through a stream, so a
  /// partial added while `startRecording` was still running has not been
  /// delivered by the time `begin()` returns.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Waits for the pipeline's own 200 ms ticker, which runs on real time even
  /// though the clock it reads does not.
  Future<void> waitFor(bool Function() done, {int attempts = 200}) async {
    for (int i = 0; i < attempts && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

/// Wednesday 11 March 2026, 10:00 local.
DateTime get testNow => DateTime(2026, 3, 11, 10);

ControllerRig buildRig({
  String transcript = 'call mum tomorrow',
  List<String> partials = const <String>[],
  List<ExtractedTask> extracted = const <ExtractedTask>[
    ExtractedTask(title: 'Call mum'),
  ],
  PermissionState microphone = PermissionState.granted,
  Entitlement entitlement = Entitlement.free,
  TaskRepository Function(FakeTaskRepository inner)? taskStore,
  UsageRepository Function(FakeUsageRepository inner)? usageStore,
  SpeechRecognizer Function(FakeSpeechRecognizer inner)? speech,
  TaskExtractor? extractor,
}) {
  final MutableClock clock = MutableClock(testNow);
  final FakeAudioRecorder recorder = FakeAudioRecorder();
  final FakeSpeechRecognizer recognizer = FakeSpeechRecognizer(
    transcript: transcript,
    partials: partials,
  );
  final FakeTaskRepository tasks = FakeTaskRepository();
  final FakeSettingsRepository settings = FakeSettingsRepository();
  final FakeUsageRepository usage = FakeUsageRepository();
  final FakePurchaseGateway purchases = FakePurchaseGateway(
    initial: entitlement,
  );
  final CountingScheduler scheduler = CountingScheduler();

  addTearDown(tasks.dispose);
  addTearDown(settings.dispose);
  addTearDown(usage.dispose);
  addTearDown(purchases.dispose);

  final ProviderContainer container = ProviderContainer.test(
    overrides: <Override>[
      clockProvider.overrideWithValue(clock),
      audioRecorderProvider.overrideWithValue(recorder),
      speechRecognizerProvider.overrideWithValue(
        speech == null ? recognizer : speech(recognizer),
      ),
      permissionServiceProvider.overrideWithValue(
        FakePermissionService(
          states: <AppPermission, PermissionState>{
            AppPermission.microphone: microphone,
          },
        ),
      ),
      primaryTaskExtractorProvider.overrideWithValue(
        extractor ?? FakeTaskExtractor(result: extracted),
      ),
      fallbackTaskExtractorProvider.overrideWithValue(
        extractor ?? FakeTaskExtractor(result: extracted),
      ),
      taskRepositoryProvider.overrideWithValue(
        taskStore == null ? tasks : taskStore(tasks),
      ),
      usageRepositoryProvider.overrideWithValue(
        usageStore == null ? usage : usageStore(usage),
      ),
      settingsRepositoryProvider.overrideWithValue(settings),
      purchaseGatewayProvider.overrideWithValue(purchases),
      reminderSchedulerProvider.overrideWithValue(scheduler),
    ],
  );

  return ControllerRig(
    container: container,
    clock: clock,
    recorder: recorder,
    recognizer: recognizer,
    tasks: tasks,
    usage: usage,
    purchases: purchases,
    scheduler: scheduler,
  );
}

void main() {
  group('beginning a capture', () {
    test(
      'an out-of-quota free user is sent to the paywall, mic untouched',
      () async {
        final ControllerRig rig = buildRig();
        for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
          await rig.usage.recordCapture(rig.today, taskCount: 1);
        }

        final String? destination = await rig.controller.begin();

        // With its reason, so the paywall says why it is up.
        expect(destination, PaywallReason.quota.location);
        expect(destination, '/paywall?reason=quota');
        expect(rig.recorder.started, isFalse);
        expect(
          rig.state.phase,
          CapturePhase.idle,
          reason: 'the flow must not be left half-open behind the paywall',
        );
      },
    );

    test('a Pro subscriber walks past the same allowance', () async {
      final ControllerRig rig = buildRig(
        entitlement: const Entitlement(status: EntitlementStatus.proActive),
      );
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        await rig.usage.recordCapture(rig.today, taskCount: 1);
      }

      final String? destination = await rig.controller.begin();

      expect(destination, AppRoute.capture.path);
      expect(rig.state.phase, CapturePhase.recording);
      await rig.controller.cancel();
    });

    test(
      'a permanently denied microphone fails on the capture screen',
      () async {
        // ⚠️ Not a bounce to Home: the Recording screen is where a denied
        // microphone is explained, because that is the moment the user has a
        // reason to care.
        final ControllerRig rig = buildRig(
          microphone: PermissionState.permanentlyDenied,
        );

        final String? destination = await rig.controller.begin();

        expect(destination, AppRoute.capture.path);
        expect(rig.state.phase, CapturePhase.failed);
        expect(rig.state.failure, isA<PermissionFailure>());
        expect(rig.recorder.started, isFalse);
      },
    );

    test(
      'a healthy start opens the microphone and shows the recorder',
      () async {
        final ControllerRig rig = buildRig();

        final String? destination = await rig.controller.begin();

        expect(destination, AppRoute.capture.path);
        expect(rig.state.phase, CapturePhase.recording);
        expect(rig.recorder.started, isTrue);
        expect(rig.state.failure, isNull);
        await rig.controller.cancel();
      },
    );

    test('revised words land in the transcript as they arrive', () async {
      final ControllerRig rig = buildRig(
        partials: const <String>['call', 'call mum'],
      );

      await rig.controller.begin();
      await rig.settle();

      expect(rig.state.transcript, 'call mum');
      await rig.controller.cancel();
    });

    test(
      'a second tap on the mic returns to where the flow already is',
      () async {
        // The mic button is reachable from Home while a capture is mid-flight;
        // starting a second one would orphan the first.
        final ControllerRig rig = buildRig();
        rig.controller.startManualDraft();

        expect(await rig.controller.begin(), AppRoute.captureConfirm.path);
        expect(rig.state.drafts, hasLength(1));
      },
    );

    test('a failure left behind does not disable the mic button', () async {
      // ⚠️ `failed` has no location, so returning it here made the mic tap a
      // no-op for as long as the stale failure stood.
      final ControllerRig rig = buildRig();
      await rig.speak(length: const Duration(milliseconds: 300));
      expect(rig.state.phase, CapturePhase.failed);

      expect(await rig.controller.begin(), AppRoute.capture.path);
      expect(rig.state.phase, CapturePhase.recording);
      expect(rig.state.failure, isNull);
      await rig.controller.cancel();
    });
  });

  group('stopping', () {
    test('carries the transcript and the drafts through to Confirm', () async {
      final ControllerRig rig = buildRig(
        transcript: 'call mum tomorrow',
        extracted: const <ExtractedTask>[
          ExtractedTask(title: 'Call mum', date: LocalDate(2026, 3, 12)),
        ],
      );

      await rig.speak();

      expect(rig.state.phase, CapturePhase.confirming);
      expect(rig.state.transcript, 'call mum tomorrow');
      expect(rig.state.drafts.single.title, 'Call mum');
      expect(rig.state.hasDrafts, isTrue);
    });

    test('a clip too short keeps the user in the flow, with the hint', () async {
      // ⚠️ `failed`, not `idle`. `captureLocationFor(idle)` is null and the
      // router's guard turns that into a bounce to Home, so settling on idle
      // threw a user who released Stop half a second early out of the capture
      // flow with no message at all. `failed` is the one phase the guard leaves
      // alone, which is what keeps the Recording screen up to show the hint.
      final ControllerRig rig = buildRig();

      await rig.speak(length: const Duration(milliseconds: 300));

      expect(rig.state.phase, CapturePhase.failed);
      expect(captureLocationFor(rig.state.phase), isNull);
      expect(rig.state.failure, isA<RecordingFailure>());
      expect(
        (rig.state.failure! as RecordingFailure).kind,
        RecordingFailureKind.tooShort,
      );
    });

    test(
      'silence fails the capture rather than opening an empty Confirm',
      () async {
        final ControllerRig rig = buildRig(transcript: '');

        await rig.speak();

        expect(rig.state.phase, CapturePhase.failed);
        expect(rig.state.failure, isA<TranscriptionFailure>());
        expect(rig.state.drafts, isEmpty);
      },
    );

    test('a capture cut off at the cap says so on the Confirm screen', () async {
      final ControllerRig rig = buildRig();
      await rig.controller.begin();

      // Nobody tapped Stop: the pipeline's ticker notices the cap and stops the
      // recording itself.
      rig.clock.advance(const Duration(seconds: 61));
      await rig.waitFor(() => rig.state.phase == CapturePhase.confirming);

      expect(rig.state.phase, CapturePhase.confirming);
      expect(rig.state.truncatedAtLimit, isTrue);
    });

    test('stopping when nothing is recording does nothing at all', () async {
      final ControllerRig rig = buildRig();

      await rig.controller.stop();

      expect(rig.state, CaptureState.idle);
    });
  });

  group('retrying extraction', () {
    test('re-runs on words already in hand rather than asking again', () async {
      // ⚠️ After an extraction failure the user must not have to say it all
      // again when the words were understood perfectly well.
      final ControllerRig rig = buildRig(
        extracted: const <ExtractedTask>[ExtractedTask(title: 'Call mum')],
      );
      await rig.speak();
      rig.controller.reset();
      expect(rig.state.transcript, isEmpty);

      // A fresh capture, then a retry over the transcript it produced.
      await rig.speak();
      await rig.controller.retryExtraction();

      expect(rig.state.phase, CapturePhase.confirming);
      expect(rig.state.drafts.single.title, 'Call mum');
    });

    test('does nothing when there is nothing to re-read', () async {
      final ControllerRig rig = buildRig();

      await rig.controller.retryExtraction();

      expect(rig.state, CaptureState.idle);
    });
  });

  group('editing the drafts', () {
    test('a manual draft is the escape from every capture failure', () async {
      final ControllerRig rig = buildRig();

      rig.controller.startManualDraft();

      expect(rig.state.phase, CapturePhase.confirming);
      expect(rig.state.drafts.single.source, TaskSource.manual);
      expect(rig.state.drafts.single.title, isEmpty);
      expect(
        rig.state.allDraftsValid,
        isFalse,
        reason: 'Save stays disabled until the card has a title',
      );
    });

    test('an edited card replaces only itself', () async {
      final ControllerRig rig = buildRig(
        extracted: const <ExtractedTask>[
          ExtractedTask(title: 'Call mum'),
          ExtractedTask(title: 'Buy milk'),
        ],
      );
      await rig.speak();
      final TaskDraft second = rig.state.drafts.last;

      rig.controller.updateDraft(second.copyWith(title: 'Buy oat milk'));

      expect(rig.state.drafts.map((TaskDraft d) => d.title), <String>[
        'Call mum',
        'Buy oat milk',
      ]);
    });

    test('a removed card is gone and the rest survive', () async {
      final ControllerRig rig = buildRig(
        extracted: const <ExtractedTask>[
          ExtractedTask(title: 'Call mum'),
          ExtractedTask(title: 'Buy milk'),
        ],
      );
      await rig.speak();

      rig.controller.removeDraft(rig.state.drafts.first.draftId);

      expect(rig.state.drafts.single.title, 'Buy milk');
    });

    test(
      'a card added by hand keeps the transcript it was added beside',
      () async {
        final ControllerRig rig = buildRig(transcript: 'call mum tomorrow');
        await rig.speak();

        rig.controller.addBlankDraft();

        expect(rig.state.drafts, hasLength(2));
        expect(rig.state.drafts.last.source, TaskSource.manual);
        expect(rig.state.drafts.last.sourceTranscript, 'call mum tomorrow');
      },
    );
  });

  group('saving', () {
    test('writes the tasks, spends one capture and clears the flow', () async {
      final ControllerRig rig = buildRig(
        extracted: const <ExtractedTask>[
          ExtractedTask(
            title: 'Call mum',
            date: LocalDate(2026, 3, 12),
            time: LocalTimeOfDay.hm(15, 0),
            hasReminder: true,
          ),
        ],
      );
      await rig.speak();

      expect(await rig.controller.save(), isTrue);

      expect(rig.tasks.all.single.title, 'Call mum');
      expect(rig.tasks.all.single.reminder.enabled, isTrue);
      expect((await rig.usage.read(rig.today)).captureCount, 1);
      expect(rig.state.phase, CapturePhase.idle);
      expect(rig.state.savedCount, 1);
      expect(rig.state.drafts, isEmpty);
    });

    test('hands the OS its new alarm by asking for a sweep', () async {
      final ControllerRig rig = buildRig();
      await rig.speak();

      await rig.controller.save();

      expect(rig.scheduler.syncs, 1);
    });

    test('frees the speech model once the capture is over', () async {
      // Reloading a 57 MB model per capture is several seconds the user
      // watches, so it is released at the end of the flow, not between phases.
      final ControllerRig rig = buildRig();
      await rig.speak();

      await rig.controller.save();

      expect(rig.recognizer.released, isTrue);
    });

    test('a typed task spends the day\'s capture too', () async {
      // ⚠️ The free allowance is one capture a day, spoken OR typed (a product
      // decision, 2026-09-23). Counting only voice left "Type a task instead"
      // as an unlimited way round it.
      final ControllerRig rig = buildRig();
      rig.controller.startManualDraft();
      rig.controller.updateDraft(
        rig.state.drafts.single.copyWith(title: 'Send the build to James'),
      );

      expect(await rig.controller.save(), isTrue);

      expect(rig.tasks.all, hasLength(1));
      expect((await rig.usage.read(rig.today)).captureCount, 1);
    });

    test('refuses while a card still has no title', () async {
      final ControllerRig rig = buildRig();
      rig.controller.startManualDraft();

      expect(await rig.controller.save(), isFalse);
      expect(rig.tasks.all, isEmpty);
      expect(rig.state.phase, CapturePhase.confirming);
    });

    test('a failed write keeps every edit the user made', () async {
      // ⚠️ A failed save that also ate the user's edits is the worst possible
      // outcome: they cannot retry and they cannot see what they lost.
      final ControllerRig rig = buildRig(
        taskStore: (FakeTaskRepository inner) =>
            UnwritableTaskRepository(inner),
      );
      rig.controller.startManualDraft();
      rig.controller.updateDraft(
        rig.state.drafts.single.copyWith(title: 'Send the build to James'),
      );

      expect(await rig.controller.save(), isFalse);

      expect(rig.state.phase, CapturePhase.confirming);
      expect(rig.state.drafts.single.title, 'Send the build to James');
      expect(rig.state.failure, isA<StorageFailure>());
      expect((rig.state.failure! as StorageFailure).diskFull, isFalse);
    });

    test('a full disk is called out, because the user can act on it', () async {
      final ControllerRig rig = buildRig(
        taskStore: (FakeTaskRepository inner) => UnwritableTaskRepository(
          inner,
          message: 'database or disk is full',
        ),
      );
      rig.controller.startManualDraft();
      rig.controller.updateDraft(
        rig.state.drafts.single.copyWith(title: 'Send the build to James'),
      );

      await rig.controller.save();

      expect((rig.state.failure! as StorageFailure).diskFull, isTrue);
    });

    test('a saved capture does not spend a second one on a retry', () async {
      final ControllerRig rig = buildRig();
      await rig.speak();
      await rig.controller.save();

      // The Confirm screen is gone; a stray second tap on Save must do nothing.
      expect(await rig.controller.save(), isFalse);
      expect((await rig.usage.read(rig.today)).captureCount, 1);
    });

    test(
      'a usage write that fails after the tasks landed is still a save',
      () async {
        // ⚠️ Two writes, two commits. When the second failed, the screen said
        // "Could not save" over tasks that were saved, kept the drafts, and the
        // retry saved every one of them twice — reminders and all.
        final ControllerRig rig = buildRig(
          extracted: const <ExtractedTask>[
            ExtractedTask(title: 'Call mum'),
            ExtractedTask(title: 'Buy milk'),
          ],
          usageStore: UnwritableUsageRepository.new,
        );
        await rig.speak();

        expect(await rig.controller.save(), isTrue);

        expect(rig.tasks.all, hasLength(2));
        expect(rig.state.phase, CapturePhase.idle);
        expect(rig.state.savedCount, 2);
        expect(rig.state.failure, isNull);
        expect(rig.scheduler.syncs, 1, reason: 'the reminders still go out');

        expect(await rig.controller.save(), isFalse);
        expect(rig.tasks.all, hasLength(2));
      },
    );
  });

  group('cancelling', () {
    test('tears the session down and leaves nothing behind', () async {
      final ControllerRig rig = buildRig();
      await rig.controller.begin();

      await rig.controller.cancel();

      expect(rig.state, CaptureState.idle);
      expect(rig.recorder.cancelled, isTrue);
      expect(rig.recognizer.cancelled, isTrue);
      expect(rig.recognizer.released, isTrue);
      expect(rig.tasks.all, isEmpty);
    });

    test('reset clears a failure without tearing anything down', () async {
      final ControllerRig rig = buildRig(
        microphone: PermissionState.permanentlyDenied,
      );
      await rig.controller.begin();

      rig.controller.reset();

      expect(rig.state, CaptureState.idle);
      expect(rig.state.failure, isNull);
    });

    test(
      'goes idle at once, so a Stop tapped behind it does nothing',
      () async {
        // ⚠️ The teardown can take seconds on a phone. The phase used to stay
        // `recording` all that time, with Stop and Cancel both still live.
        late HeldRecognizer held;
        final ControllerRig rig = buildRig(
          speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
        );
        await rig.controller.begin();
        rig.clock.advance(const Duration(seconds: 3));

        final Completer<void> handingBack = Completer<void>();
        held.cancelGate = handingBack;
        final Future<void> cancelling = rig.controller.cancel();

        expect(rig.state, CaptureState.idle);
        await rig.controller.stop();
        expect(rig.state, CaptureState.idle);
        expect(
          rig.controller.cancel(),
          same(cancelling),
          reason: 'a second Cancel is the same teardown, not another one',
        );

        handingBack.complete();
        await cancelling;
        expect(held.cancels, 1);
        expect(rig.state, CaptureState.idle);
      },
    );

    test('a Stop still finalising never brings the capture back', () async {
      // ⚠️ The stale result used to land on `idle`: the next mic tap opened
      // Confirm with the discarded tasks, or found `failed` and did nothing.
      late HeldRecognizer held;
      final ControllerRig rig = buildRig(
        speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
      );
      await rig.controller.begin();
      rig.clock.advance(const Duration(seconds: 3));

      final Completer<void> finalising = Completer<void>();
      held.stopGate = finalising;
      final Future<void> stopping = rig.controller.stop();
      expect(rig.state.phase, CapturePhase.transcribing);

      await rig.controller.cancel();
      finalising.complete();
      await stopping.timeout(const Duration(seconds: 5));

      expect(rig.state, CaptureState.idle);
      expect(await rig.controller.begin(), AppRoute.capture.path);
      expect(rig.state.phase, CapturePhase.recording);
      await rig.controller.cancel();
    });

    test('a slow extraction never reopens Confirm after a cancel', () async {
      final GatedExtractor extractor = GatedExtractor();
      final ControllerRig rig = buildRig(extractor: extractor);
      await rig.controller.begin();
      rig.clock.advance(const Duration(seconds: 3));

      final Future<void> stopping = rig.controller.stop();
      await rig.waitFor(() => rig.state.phase == CapturePhase.extracting);
      await rig.controller.cancel();
      extractor.gate.complete();
      await stopping;

      expect(rig.state, CaptureState.idle);
      expect(await rig.controller.begin(), AppRoute.capture.path);
      await rig.controller.cancel();
    });

    test('the next capture waits for the last to hand the mic back', () async {
      late HeldRecognizer held;
      final ControllerRig rig = buildRig(
        speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
      );
      await rig.controller.begin();

      final Completer<void> handingBack = Completer<void>();
      held.cancelGate = handingBack;
      final Future<void> cancelling = rig.controller.cancel();
      final Future<String?> next = rig.controller.begin();
      await rig.settle();

      expect(
        rig.state.phase,
        CapturePhase.checkingQuota,
        reason: 'no microphone may open while the last one is still closing',
      );

      handingBack.complete();
      expect(await next, AppRoute.capture.path);
      expect(rig.state.phase, CapturePhase.recording);
      await cancelling;
      await rig.controller.cancel();
    });

    test('a new capture starts its meters at zero', () async {
      // The ticker and the audio stop at cancel, but nothing zeroed what they
      // had drawn until the next microphone opened, and the wait before that
      // put the dead capture's length and waveform back on screen.
      late HeldRecognizer held;
      final ControllerRig rig = buildRig(
        speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
      );
      await rig.controller.begin();
      rig.clock.advance(const Duration(seconds: 42));
      await rig.waitFor(
        () => rig.controller.elapsed.value >= const Duration(seconds: 42),
      );
      // The recorder's last chunk, as the pipeline's audio listener draws it.
      rig.controller.amplitude.addLevel(0.8);

      final Completer<void> handingBack = Completer<void>();
      held.cancelGate = handingBack;
      final Future<void> cancelling = rig.controller.cancel();
      final Future<String?> next = rig.controller.begin();

      final CapturePhase phase = rig.state.phase;
      final Duration elapsed = rig.controller.elapsed.value;
      final double level = rig.controller.amplitude.level;
      final List<double> samples = rig.controller.amplitude.samples;

      handingBack.complete();
      expect(await next, AppRoute.capture.path);
      await cancelling;
      await rig.controller.cancel();

      expect(phase, CapturePhase.checkingQuota);
      expect(elapsed, Duration.zero);
      expect(level, 0);
      expect(samples.every((double sample) => sample == 0), isTrue);
    });

    test('a Cancel while the next capture waits opens nothing', () async {
      // The Recording screen offers Cancel during that wait, which can last
      // seconds; it must not leave a microphone opening behind it.
      late HeldRecognizer held;
      final ControllerRig rig = buildRig(
        speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
      );
      await rig.controller.begin();

      final Completer<void> handingBack = Completer<void>();
      held.cancelGate = handingBack;
      final Future<void> cancelling = rig.controller.cancel();
      final Future<String?> next = rig.controller.begin();
      await rig.settle();
      expect(rig.state.phase, CapturePhase.checkingQuota);

      final Future<void> cancellingAgain = rig.controller.cancel();
      expect(rig.state, CaptureState.idle);

      handingBack.complete();
      expect(await next, isNull);
      await cancelling;
      await cancellingAgain;
      expect(rig.state, CaptureState.idle);
      expect(rig.recorder.started, isFalse);
    });

    // ⚠️ A capture cancelled after Stop cannot be interrupted: whisper runs
    // its full-context final pass, bounded only by the pipeline's own
    // transcription deadline, and only then hands the model back. The next
    // `begin` used to give up after 10 s, and on a slow phone "Stop, back out
    // of Processing, tap the mic" read "Your microphone is in use" while
    // nothing but the app's own decode was running.
    //
    // `testWidgets` only for its virtual clock. Each `begin` below ends before
    // a microphone opens — at a refused microphone past the wait, or at the
    // paywall ahead of it — so no recording is opened under FakeAsync.
    group('the wait for the last capture', () {
      /// Today's capture still free, so `begin` waits; the microphone refused,
      /// so what comes after the wait is a failure, not a recording.
      ControllerRig waitRig(void Function(HeldRecognizer) held) => buildRig(
        microphone: PermissionState.permanentlyDenied,
        speech: (FakeSpeechRecognizer inner) {
          final HeldRecognizer recognizer = HeldRecognizer(inner);
          held(recognizer);
          return recognizer;
        },
      );

      /// Today's capture already spent.
      Future<ControllerRig> spentRig(void Function(HeldRecognizer) held) async {
        final ControllerRig rig = waitRig(held);
        for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
          await rig.usage.recordCapture(rig.today, taskCount: 1);
        }
        return rig;
      }

      testWidgets('outlasts a whole final pass, not just one decode', (
        WidgetTester tester,
      ) async {
        late HeldRecognizer held;
        final ControllerRig rig = waitRig((HeldRecognizer r) => held = r);
        final Completer<void> finalPass = Completer<void>();
        held.cancelGate = finalPass;
        final Future<void> cancelling = rig.controller.cancel();
        expect(rig.controller.isTearingDown, isTrue);

        final Future<String?> next = rig.controller.begin();
        await tester.pump(ExtractionDefaults.transcriptionTimeout);

        expect(rig.state.phase, CapturePhase.checkingQuota);
        expect(rig.state.failure, isNull);

        finalPass.complete();
        await tester.pump();
        expect(await next, AppRoute.capture.path);
        expect(
          rig.state.failure,
          isA<PermissionFailure>(),
          reason: 'past the wait and on to the microphone',
        );
        await cancelling;
        expect(rig.controller.isTearingDown, isFalse);
      });

      testWidgets('a wedged teardown says so, and does not blame another app', (
        WidgetTester tester,
      ) async {
        late HeldRecognizer held;
        final ControllerRig rig = waitRig((HeldRecognizer r) => held = r);
        final Completer<void> wedged = Completer<void>();
        held.cancelGate = wedged;
        final Future<void> cancelling = rig.controller.cancel();

        final Future<String?> next = rig.controller.begin();
        await tester.pump(const Duration(minutes: 1));

        expect(await next, AppRoute.capture.path);
        expect(rig.state.phase, CapturePhase.failed);
        expect(
          (rig.state.failure! as RecordingFailure).kind,
          RecordingFailureKind.stillClosing,
        );
        expect(rig.recorder.started, isFalse);

        wedged.complete();
        await tester.pump();
        await cancelling;
      });

      // ⚠️ The mic button puts /capture on screen for this whole wait (see
      // `isTearingDown`). Nothing cleared the meters between captures, so
      // "Getting ready" sat over the discarded capture's frozen timer and
      // waveform, and over "Speak naturally" with no microphone open: every
      // word said during the wait was lost.
      testWidgets('shows none of the last capture, and asks for no words', (
        WidgetTester tester,
      ) async {
        late HeldRecognizer held;
        final ControllerRig rig = waitRig((HeldRecognizer r) => held = r);
        // What a capture cancelled 42 s in leaves on the meters. Set by hand:
        // a real recording's teardown awaits subscription cancels, which
        // complete on the real event loop and never under FakeAsync. The
        // `test` "a new capture starts its meters at zero" drives a real one.
        rig.controller.elapsed.value = const Duration(seconds: 42);
        rig.controller.amplitude.addLevel(0.8);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: rig.container,
            child: MaterialApp(
              theme: TasukeTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const RecordingScreen(),
            ),
          ),
        );
        final Completer<void> finalPass = Completer<void>();
        held.cancelGate = finalPass;
        final Future<void> cancelling = rig.controller.cancel();

        final Future<String?> next = rig.controller.begin();
        await tester.pump();

        final CapturePhase waiting = rig.state.phase;
        final int oldLength = find.text('00:42').evaluate().length;
        final int zeroed = find.text('00:00').evaluate().length;
        final double level = rig.controller.amplitude.level;
        final List<double> samples = rig.controller.amplitude.samples;
        final int speakHints = find
            .text('Speak naturally.\nYou can say multiple tasks at once.')
            .evaluate()
            .length;
        final int waitLines = find
            .text('Finishing your last recording first.')
            .evaluate()
            .length;

        finalPass.complete();
        await tester.pump();
        final String? destination = await next;
        await cancelling;
        // Unmounted inside the body: the orb animates for as long as it is up.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(waiting, CapturePhase.checkingQuota);
        expect(oldLength, 0, reason: 'the discarded capture is not running');
        expect(zeroed, 1);
        expect(level, 0);
        expect(samples.every((double sample) => sample == 0), isTrue);
        expect(speakHints, 0, reason: 'no microphone is open to hear it');
        expect(waitLines, 1, reason: 'the wait says what it is waiting for');
        expect(destination, AppRoute.capture.path);
      });

      // ⚠️ The quota used to be checked only AFTER this wait. A wait that ran
      // out ended in "still closing", whose "Type a task instead" let a user
      // who had spent the day's capture save a second one: 2 of 1 on the
      // Usage screen. A user out of quota also sat through the whole final
      // pass only to be shown the paywall at the end of it.
      testWidgets('a spent quota is answered before the wait, with the '
          'paywall', (WidgetTester tester) async {
        late HeldRecognizer held;
        final ControllerRig rig = await spentRig(
          (HeldRecognizer r) => held = r,
        );
        final Completer<void> wedged = Completer<void>();
        held.cancelGate = wedged;
        final Future<void> cancelling = rig.controller.cancel();

        bool waited = false;
        final Future<String?> next = rig.controller.begin(
          onWait: () => waited = true,
        );
        await tester.pump();

        expect(await next, PaywallReason.quota.location);
        expect(waited, isFalse, reason: 'no "Getting ready" for a paywall');
        expect(
          rig.controller.isTearingDown,
          isTrue,
          reason: 'answered while the last capture was still closing',
        );
        expect(rig.state, CaptureState.idle);
        expect(rig.recorder.started, isFalse);

        wedged.complete();
        await tester.pump();
        await cancelling;
      });

      testWidgets('a typed save whose model release wedges cannot be followed '
          'by a second', (WidgetTester tester) async {
        // The reviewer's reproduction: the day's one capture typed and saved,
        // the model release after it held past the whole budget, the mic
        // tapped again.
        late HeldRecognizer held;
        final ControllerRig rig = waitRig((HeldRecognizer r) => held = r);
        final Completer<void> releasing = Completer<void>();
        held.releaseGate = releasing;

        rig.controller.startManualDraft();
        rig.controller.updateDraft(
          rig.state.drafts.single.copyWith(title: 'Call the bank'),
        );
        expect(await rig.controller.save(), isTrue);
        expect(
          (await rig.usage.read(rig.today)).captureCount,
          ExtractionDefaults.freeDailyCaptures,
        );
        expect(rig.controller.isTearingDown, isTrue);

        final Future<String?> next = rig.controller.begin();
        await tester.pump(const Duration(minutes: 1));

        expect(await next, PaywallReason.quota.location);
        expect(
          rig.state.failure,
          isNull,
          reason: 'not "still closing", which offers a typed task',
        );
        expect(rig.state, CaptureState.idle);
        expect(rig.tasks.all, hasLength(1));
        expect(
          (await rig.usage.read(rig.today)).captureCount,
          ExtractionDefaults.freeDailyCaptures,
        );

        releasing.complete();
        await tester.pump();
        expect(rig.controller.isTearingDown, isFalse);
      });

      testWidgets('with a capture left, "Getting ready" is asked for only '
          'once the quota has passed', (WidgetTester tester) async {
        late HeldRecognizer held;
        final ControllerRig rig = waitRig((HeldRecognizer r) => held = r);
        final Completer<void> finalPass = Completer<void>();
        held.cancelGate = finalPass;
        final Future<void> cancelling = rig.controller.cancel();

        int waits = 0;
        final Future<String?> next = rig.controller.begin(
          onWait: () => waits++,
        );
        await tester.pump();
        expect(waits, 1);
        expect(rig.state.phase, CapturePhase.checkingQuota);

        finalPass.complete();
        await tester.pump();
        expect(await next, AppRoute.capture.path);
        expect(waits, 1);
        await cancelling;
      });
    });

    test('a cancel while the mic is opening releases what opened', () async {
      late HeldRecognizer held;
      final ControllerRig rig = buildRig(
        speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
      );
      final Completer<void> loading = Completer<void>();
      held.prepareGate = loading;

      final Future<String?> beginning = rig.controller.begin();
      await rig.waitFor(() => rig.state.phase == CapturePhase.recording);

      // Nothing is recording yet: the Stop is held for when there is, and the
      // Cancel below must still win over it.
      await rig.controller.stop();
      expect(rig.state.phase, CapturePhase.recording);

      final Future<void> cancelling = rig.controller.cancel();
      loading.complete();

      expect(await beginning, isNull);
      await cancelling;
      expect(rig.state, CaptureState.idle);
      expect(
        rig.recorder.started,
        isFalse,
        reason: 'a microphone opened after Cancel is handed straight back',
      );
    });

    test(
      'a Stop tapped while the mic is opening lands once it is open',
      () async {
        // ⚠️ The phase is already `recording`, so Stop is on screen and enabled
        // (Try again re-opens the mic under it). The tap used to be dropped.
        late HeldRecognizer held;
        final ControllerRig rig = buildRig(
          speech: (FakeSpeechRecognizer inner) => held = HeldRecognizer(inner),
        );
        final Completer<void> loading = Completer<void>();
        held.prepareGate = loading;

        final Future<String?> beginning = rig.controller.begin();
        await rig.waitFor(() => rig.state.phase == CapturePhase.recording);
        await rig.controller.stop();
        expect(rig.state.phase, CapturePhase.recording);

        loading.complete();
        expect(await beginning, AppRoute.capture.path);
        expect(rig.state.phase, CapturePhase.transcribing);

        // Stopped the instant it opened, so nothing was said.
        await rig.waitFor(() => rig.state.phase == CapturePhase.failed);
        expect(
          (rig.state.failure! as RecordingFailure).kind,
          RecordingFailureKind.tooShort,
        );
        expect(rig.recorder.started, isFalse);
      },
    );
  });

  group('the waveform and the timer', () {
    test('are the pipeline\'s own, not a rebuild of the screen', () async {
      // ⚠️ Routing twenty samples a second through Riverpod would rebuild the
      // whole subtree at the same rate; the painter listens to these directly.
      final ControllerRig rig = buildRig();

      expect(rig.controller.amplitude, isNotNull);
      expect(rig.controller.elapsed.value, Duration.zero);
    });
  });
}
