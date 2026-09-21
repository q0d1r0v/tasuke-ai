import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/audio/audio_recorder.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';
import 'package:tasuke_ai/features/pipeline/domain/voice_capture_pipeline.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

import '../../helpers/fakes.dart';

/// A microphone that is already in use — a phone call, or another app.
final class BusyRecorder implements AudioRecorder {
  bool started = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isRecording() async => false;

  @override
  Future<Stream<Uint8List>> start() async => throw const RecordingFailure(
    'Could not start capture',
    kind: RecordingFailureKind.busy,
  );

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

/// A recogniser that dies while finalising, which is how a corrupt ggml file
/// presents: everything works until the last call.
final class DyingRecognizer implements SpeechRecognizer {
  DyingRecognizer(this.inner);

  final FakeSpeechRecognizer inner;

  @override
  Future<SpeechAvailability> availability() => inner.availability();

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) =>
      inner.transcribeStream(pcm16);

  @override
  Future<void> stop() async => throw StateError('whisper context is gone');

  @override
  Future<void> cancel() => inner.cancel();

  @override
  Future<void> release() => inner.release();
}

/// A recogniser that closes its event stream without ever finalising, after
/// having revised the transcript a few times. Whisper does this when inference
/// fails part-way through the utterance.
final class AbandoningRecognizer implements SpeechRecognizer {
  AbandoningRecognizer({this.partials = const <String>[]});

  final List<String> partials;
  StreamController<SpeechEvent>? _events;
  bool released = false;

  @override
  Future<SpeechAvailability> availability() async => SpeechAvailability.ready;

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) {
    final StreamController<SpeechEvent> controller =
        StreamController<SpeechEvent>();
    _events = controller;
    pcm16.listen((_) {});
    for (final String partial in partials) {
      controller.add(SpeechPartial(partial));
    }
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    _events?.add(const SpeechError('inference aborted'));
    await _events?.close();
    _events = null;
  }

  @override
  Future<void> cancel() async {
    await _events?.close();
    _events = null;
  }

  @override
  Future<void> release() async => released = true;
}

/// An extractor whose future never resolves, so the pipeline's own budget is
/// the only thing that can end the call.
final class HangingExtractor implements TaskExtractor {
  final Completer<List<ExtractedTask>> _never =
      Completer<List<ExtractedTask>>();

  @override
  Future<bool> isReady() async => true;

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) => _never.future;
}

/// An extractor that cannot even answer whether it is ready — a model file
/// deleted underneath a running app.
final class UnaskableExtractor implements TaskExtractor {
  @override
  Future<bool> isReady() async => throw StateError('model handle is closed');

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) async => const <ExtractedTask>[];
}

DateTime get testNow => DateTime(2026, 3, 11, 10);

/// Builds a pipeline over whichever ports the case needs, filling the rest in
/// with the shared fakes.
VoiceCapturePipeline pipelineOver({
  AudioRecorder? recorder,
  SpeechRecognizer? recognizer,
  TaskExtractor? primary,
  TaskExtractor? fallback,
  FakePermissionService? permissions,
  MutableClock? clock,
}) {
  final FakeUsageRepository usage = FakeUsageRepository();
  addTearDown(usage.dispose);

  int nextDraft = 0;
  final VoiceCapturePipeline pipeline = VoiceCapturePipeline(
    recorder: recorder ?? FakeAudioRecorder(),
    recognizer: recognizer ?? FakeSpeechRecognizer(transcript: 'call mum'),
    primaryExtractor: primary ?? FakeTaskExtractor(),
    fallbackExtractor: fallback ?? FakeTaskExtractor(),
    permissions: permissions ?? FakePermissionService(),
    usage: usage,
    clock: clock ?? MutableClock(testNow),
    newDraftId: () => 'draft-${nextDraft++}',
  );
  addTearDown(pipeline.dispose);
  return pipeline;
}

void main() {
  group('the recording never starts', () {
    test(
      'a missing speech model is reported before the mic is opened',
      () async {
        final FakeAudioRecorder recorder = FakeAudioRecorder();
        final VoiceCapturePipeline pipeline = pipelineOver(
          recorder: recorder,
          recognizer: FakeSpeechRecognizer(
            available: SpeechAvailability.modelUnavailable,
          ),
        );

        final Failure? failure = await pipeline.startRecording(
          onPartial: (_) {},
          onAutoStop: () {},
        );

        expect(failure, isA<TranscriptionFailure>());
        expect(
          (failure! as TranscriptionFailure).kind,
          TranscriptionFailureKind.modelUnavailable,
        );
        expect(
          recorder.started,
          isFalse,
          reason: 'no audio may be captured that nothing can transcribe',
        );
      },
    );

    test(
      'an unusable microphone is reported as an unknown transcription problem',
      () async {
        final VoiceCapturePipeline pipeline = pipelineOver(
          recognizer: FakeSpeechRecognizer(
            available: SpeechAvailability.microphoneUnavailable,
          ),
        );

        final Failure? failure = await pipeline.startRecording(
          onPartial: (_) {},
          onAutoStop: () {},
        );

        expect(
          (failure! as TranscriptionFailure).kind,
          TranscriptionFailureKind.unknown,
        );
      },
    );

    test(
      'a microphone another app is holding becomes a busy failure',
      () async {
        // The recorder throws; the caller only needs to know which screen to
        // show, so the throw must not escape the pipeline.
        final VoiceCapturePipeline pipeline = pipelineOver(
          recorder: BusyRecorder(),
        );

        final Failure? failure = await pipeline.startRecording(
          onPartial: (_) {},
          onAutoStop: () {},
        );

        expect(failure, isA<RecordingFailure>());
        expect((failure! as RecordingFailure).kind, RecordingFailureKind.busy);
      },
    );
  });

  group('the microphone permission gate', () {
    test('passes straight through when it is already granted', () async {
      final VoiceCapturePipeline pipeline = pipelineOver();

      expect(await pipeline.ensureMicrophone(), isNull);
    });

    test('never prompts again once the microphone is granted', () async {
      final FakePermissionService permissions = FakePermissionService();
      final VoiceCapturePipeline pipeline = pipelineOver(
        permissions: permissions,
      );

      await pipeline.ensureMicrophone();

      expect(permissions.requested, isEmpty);
    });

    test('prompts exactly once when the user has never been asked', () async {
      final FakePermissionService permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.notDetermined,
        },
      );
      final VoiceCapturePipeline pipeline = pipelineOver(
        permissions: permissions,
      );

      await pipeline.ensureMicrophone();

      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);
    });

    test('a plain refusal leaves the retry button usable', () async {
      // Denied, not permanently denied: Android prompts again, so the screen
      // keeps "Allow microphone" rather than swapping in "Open Settings".
      final VoiceCapturePipeline pipeline = pipelineOver(
        permissions: FakePermissionService(
          states: <AppPermission, PermissionState>{
            AppPermission.microphone: PermissionState.denied,
          },
        ),
      );

      final Failure? failure = await pipeline.ensureMicrophone();

      expect(failure, isA<PermissionFailure>());
      expect((failure! as PermissionFailure).permanentlyDenied, isFalse);
    });

    test(
      'a permanently denied microphone routes the user to Settings',
      () async {
        // ⚠️ iOS never prompts twice. A retry button here does nothing at all,
        // which is why the failure carries the flag that swaps the button.
        final VoiceCapturePipeline pipeline = pipelineOver(
          permissions: FakePermissionService(
            states: <AppPermission, PermissionState>{
              AppPermission.microphone: PermissionState.permanentlyDenied,
            },
          ),
        );

        final Failure? failure = await pipeline.ensureMicrophone();

        expect(failure, isA<PermissionFailure>());
        expect((failure! as PermissionFailure).permanentlyDenied, isTrue);
      },
    );
  });

  group('transcription that fails', () {
    test(
      'a recogniser that dies while finalising is a transcription failure',
      () async {
        final MutableClock clock = MutableClock(testNow);
        final VoiceCapturePipeline pipeline = pipelineOver(
          recognizer: DyingRecognizer(FakeSpeechRecognizer()),
          clock: clock,
        );

        await pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});
        clock.advance(const Duration(seconds: 3));
        final Object result = await pipeline.stopRecording();

        expect(result, isA<TranscriptionFailure>());
      },
    );

    test(
      'words already heard survive a recogniser that gives up mid-utterance',
      () async {
        // ⚠️ The port's contract: "heard words the user has to say again are
        // worse than a slightly short transcript". A recogniser that closes
        // without finalising must not throw away what it already revised.
        final MutableClock clock = MutableClock(testNow);
        final VoiceCapturePipeline pipeline = pipelineOver(
          recognizer: AbandoningRecognizer(
            partials: const <String>['call', 'call mum tomorrow'],
          ),
          clock: clock,
        );

        await pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});
        clock.advance(const Duration(seconds: 3));

        expect(await pipeline.stopRecording(), 'call mum tomorrow');
      },
    );

    test('silence really is an empty transcript, not a hang', () async {
      // Whisper closes without a final event when the audio was nothing but
      // silence. Nothing was revised, so there is nothing to keep.
      final MutableClock clock = MutableClock(testNow);
      final VoiceCapturePipeline pipeline = pipelineOver(
        recognizer: AbandoningRecognizer(),
        clock: clock,
      );

      await pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});
      clock.advance(const Duration(seconds: 3));

      expect(await pipeline.stopRecording(), '');
    });
  });

  group('nothing was said', () {
    test('an empty transcript is rejected as silence', () async {
      final VoiceCapturePipeline pipeline = pipelineOver();

      final CaptureOutcome outcome = await pipeline.extract('');

      expect(outcome, isA<CaptureRejected>());
      final Failure failure = (outcome as CaptureRejected).failure;
      expect(
        (failure as TranscriptionFailure).kind,
        TranscriptionFailureKind.noSpeech,
      );
    });

    test('whitespace alone is silence too', () async {
      final VoiceCapturePipeline pipeline = pipelineOver();

      expect(await pipeline.extract('   \n  '), isA<CaptureRejected>());
    });
  });

  group('extraction that fails falls back rather than failing the capture', () {
    test(
      'an extractor that throws hands over to the deterministic one',
      () async {
        // ⚠️ The rule-based extractor is not a degraded mode: it is the only
        // extractor a user who declines the 219 MB download will ever have.
        final FakeTaskExtractor fallback = FakeTaskExtractor(
          result: const <ExtractedTask>[ExtractedTask(title: 'Call mum')],
        );
        final VoiceCapturePipeline pipeline = pipelineOver(
          primary: FakeTaskExtractor(throws: StateError('inference crashed')),
          fallback: fallback,
        );

        final CaptureOutcome outcome = await pipeline.extract('call mum');

        expect(fallback.lastTranscript, 'call mum');
        expect((outcome as CaptureDrafts).drafts.single.title, 'Call mum');
      },
    );

    test('an extractor that reports a timeout hands over too', () async {
      // The pipeline's real budget is 45 seconds of wall clock; a
      // TimeoutException raised by the model lands in exactly the same arm, so
      // this case pins the behaviour without the wait.
      final FakeTaskExtractor fallback = FakeTaskExtractor(
        result: const <ExtractedTask>[ExtractedTask(title: 'Call mum')],
      );
      final VoiceCapturePipeline pipeline = pipelineOver(
        primary: FakeTaskExtractor(
          throws: TimeoutException('inference ran long'),
        ),
        fallback: fallback,
      );

      final CaptureOutcome outcome = await pipeline.extract('call mum');

      expect(fallback.lastTranscript, 'call mum');
      expect(outcome, isA<CaptureDrafts>());
    });

    testWidgets(
      'inference past the 45-second budget is abandoned, not awaited',
      (WidgetTester tester) async {
        // ⚠️ `testWidgets` only for its virtual clock: pumping 46 seconds fires
        // the pipeline's own `.timeout()` without anyone waiting 46 real ones.
        // No database is constructed here — see the note in `fakes.dart`.
        final FakeTaskExtractor fallback = FakeTaskExtractor(
          result: const <ExtractedTask>[ExtractedTask(title: 'Call mum')],
        );
        final VoiceCapturePipeline pipeline = pipelineOver(
          primary: HangingExtractor(),
          fallback: fallback,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        final Future<CaptureOutcome> pending = pipeline.extract('call mum');
        await tester.pump();
        await tester.pump(const Duration(seconds: 46));

        expect(
          (await pending as CaptureDrafts).drafts.single.title,
          'Call mum',
        );
        expect(fallback.lastTranscript, 'call mum');

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    test(
      'an extractor that cannot say whether it is ready is not used',
      () async {
        final FakeTaskExtractor fallback = FakeTaskExtractor(
          result: const <ExtractedTask>[ExtractedTask(title: 'Call mum')],
        );
        final VoiceCapturePipeline pipeline = pipelineOver(
          primary: UnaskableExtractor(),
          fallback: fallback,
        );

        await pipeline.extract('call mum');

        expect(fallback.lastTranscript, 'call mum');
      },
    );

    test(
      'a model still downloading means the deterministic one runs',
      () async {
        final FakeTaskExtractor primary = FakeTaskExtractor(ready: false);
        final FakeTaskExtractor fallback = FakeTaskExtractor(
          result: const <ExtractedTask>[ExtractedTask(title: 'Call mum')],
        );
        final VoiceCapturePipeline pipeline = pipelineOver(
          primary: primary,
          fallback: fallback,
        );

        await pipeline.extract('call mum');

        expect(primary.lastTranscript, isNull);
        expect(fallback.lastTranscript, 'call mum');
      },
    );

    test(
      'both extractors failing still leaves the user their own words',
      () async {
        // The last line of defence: one draft holding the raw transcript.
        final VoiceCapturePipeline pipeline = pipelineOver(
          primary: FakeTaskExtractor(throws: StateError('inference crashed')),
          fallback: FakeTaskExtractor(throws: StateError('parser crashed')),
        );

        final CaptureOutcome outcome = await pipeline.extract(
          'call mum tomorrow',
        );

        final List<TaskDraft> drafts = (outcome as CaptureDrafts).drafts;
        expect(drafts.single.title, 'call mum tomorrow');
        expect(drafts.single.sourceTranscript, 'call mum tomorrow');
      },
    );
  });

  group('cancelling', () {
    test('tears down the microphone and the speech session', () async {
      final FakeAudioRecorder recorder = FakeAudioRecorder();
      final FakeSpeechRecognizer recognizer = FakeSpeechRecognizer();
      final VoiceCapturePipeline pipeline = pipelineOver(
        recorder: recorder,
        recognizer: recognizer,
      );
      await pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});

      await pipeline.cancel();

      expect(recorder.cancelled, isTrue);
      expect(recorder.started, isFalse);
      expect(recognizer.cancelled, isTrue);
      expect(pipeline.wasCancelled, isTrue);
    });

    test('releasing the model frees it from native memory', () async {
      // Separate from cancel on purpose: reloading a 57 MB model between the
      // phases of one capture is several seconds the user watches.
      final FakeSpeechRecognizer recognizer = FakeSpeechRecognizer();
      final VoiceCapturePipeline pipeline = pipelineOver(
        recognizer: recognizer,
      );
      await pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});
      await pipeline.cancel();

      expect(recognizer.released, isFalse);
      await pipeline.releaseModel();
      expect(recognizer.released, isTrue);
    });

    test(
      'a recorder that throws on the way out still leaves it torn down',
      () async {
        final VoiceCapturePipeline pipeline = pipelineOver(
          recognizer: DyingRecognizer(FakeSpeechRecognizer()),
        );
        await pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});

        await pipeline.cancel();

        expect(pipeline.wasCancelled, isTrue);
        expect(pipeline.recordedDuration, Duration.zero);
      },
    );

    test('cancelling before anything started is harmless', () async {
      final VoiceCapturePipeline pipeline = pipelineOver();

      await pipeline.cancel();

      expect(pipeline.wasCancelled, isTrue);
    });
  });
}
