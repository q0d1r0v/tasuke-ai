import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library — only from
// `misc.dart`. Naming it without this import is a `non_type_as_type_argument`
// error that reads like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
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
      speechRecognizerProvider.overrideWithValue(recognizer),
      permissionServiceProvider.overrideWithValue(
        FakePermissionService(
          states: <AppPermission, PermissionState>{
            AppPermission.microphone: microphone,
          },
        ),
      ),
      primaryTaskExtractorProvider.overrideWithValue(
        FakeTaskExtractor(result: extracted),
      ),
      fallbackTaskExtractorProvider.overrideWithValue(
        FakeTaskExtractor(result: extracted),
      ),
      taskRepositoryProvider.overrideWithValue(
        taskStore == null ? tasks : taskStore(tasks),
      ),
      settingsRepositoryProvider.overrideWithValue(settings),
      usageRepositoryProvider.overrideWithValue(usage),
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

        expect(destination, AppRoute.paywall.path);
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

    test('a typed task does not spend a voice capture', () async {
      // ⚠️ The quota is on voice, which is the expensive part. Someone who
      // types a task has used none of it.
      final ControllerRig rig = buildRig();
      rig.controller.startManualDraft();
      rig.controller.updateDraft(
        rig.state.drafts.single.copyWith(title: 'Send the build to James'),
      );

      expect(await rig.controller.save(), isTrue);

      expect(rig.tasks.all, hasLength(1));
      expect((await rig.usage.read(rig.today)).captureCount, 0);
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
