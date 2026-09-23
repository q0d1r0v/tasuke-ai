import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/pipeline/domain/amplitude_track.dart';
import 'package:tasuke_ai/features/pipeline/domain/voice_capture_pipeline.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

import '../../helpers/fakes.dart';

/// One PCM16 chunk, the way the recorder hands them over: 16 kHz mono,
/// little-endian, two bytes per sample.
Uint8List pcm16(List<int> samples) {
  final ByteData data = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// [FakeSpeechRecognizer] with a tap on the audio it is handed.
///
/// The shared fake drains the stream so the producer is not left unlistened,
/// but it keeps nothing — and "the bytes reached the recogniser" is the one
/// thing a capture test cannot take on trust.
final class TappedRecognizer implements SpeechRecognizer {
  @override
  Future<void> prepare() async {}

  TappedRecognizer(this.inner);

  final FakeSpeechRecognizer inner;
  final List<int> heard = <int>[];

  @override
  Future<SpeechAvailability> availability() => inner.availability();

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) =>
      inner.transcribeStream(
        pcm16.map((Uint8List chunk) {
          heard.addAll(chunk);
          return chunk;
        }),
      );

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> cancel() => inner.cancel();

  @override
  Future<void> release() => inner.release();
}

/// One capture attempt and every port behind it.
final class PipelineRig {
  PipelineRig({
    required this.pipeline,
    required this.clock,
    required this.recorder,
    required this.speech,
    required this.recognizer,
    required this.primary,
    required this.permissions,
    required this.usage,
  });

  final VoiceCapturePipeline pipeline;
  final MutableClock clock;
  final FakeAudioRecorder recorder;
  final FakeSpeechRecognizer speech;
  final TappedRecognizer recognizer;
  final FakeTaskExtractor primary;
  final FakePermissionService permissions;
  final FakeUsageRepository usage;

  final List<String> partials = <String>[];
  int autoStops = 0;
}

/// Wednesday 11 March 2026, 10:00 local. Midweek and far from any month or
/// year boundary, so a failure is never ambiguous between a bug and an
/// off-by-one in the fixture.
DateTime get testNow => DateTime(2026, 3, 11, 10);

PipelineRig rigWith({
  List<List<int>> chunks = const <List<int>>[],
  String transcript = 'call mum tomorrow',
  List<String> partials = const <String>[],
  List<ExtractedTask> extracted = const <ExtractedTask>[
    ExtractedTask(title: 'Call mum'),
  ],
  SpeechAvailability availability = SpeechAvailability.ready,
  PermissionState microphone = PermissionState.granted,
}) {
  final MutableClock clock = MutableClock(testNow);
  final FakeAudioRecorder recorder = FakeAudioRecorder(chunks: chunks);
  final FakeSpeechRecognizer speech = FakeSpeechRecognizer(
    transcript: transcript,
    partials: partials,
    available: availability,
  );
  final TappedRecognizer recognizer = TappedRecognizer(speech);
  final FakeTaskExtractor primary = FakeTaskExtractor(result: extracted);
  final FakePermissionService permissions = FakePermissionService(
    states: <AppPermission, PermissionState>{
      AppPermission.microphone: microphone,
    },
  );
  final FakeUsageRepository usage = FakeUsageRepository();
  addTearDown(usage.dispose);

  int nextDraft = 0;
  final VoiceCapturePipeline pipeline = VoiceCapturePipeline(
    recorder: recorder,
    recognizer: recognizer,
    primaryExtractor: primary,
    fallbackExtractor: FakeTaskExtractor(result: extracted),
    permissions: permissions,
    usage: usage,
    clock: clock,
    newDraftId: () => 'draft-${nextDraft++}',
  );
  addTearDown(pipeline.dispose);

  return PipelineRig(
    pipeline: pipeline,
    clock: clock,
    recorder: recorder,
    speech: speech,
    recognizer: recognizer,
    primary: primary,
    permissions: permissions,
    usage: usage,
  );
}

void main() {
  group('a capture that works', () {
    test('opens the microphone and feeds it to the recogniser', () async {
      final PipelineRig rig = rigWith(
        chunks: <List<int>>[
          pcm16(const <int>[900, -900, 1200]),
          pcm16(const <int>[400, -400, 600]),
        ],
        transcript: 'call mum tomorrow at three',
      );

      final Failure? started = await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );

      expect(started, isNull);
      expect(rig.recorder.started, isTrue);

      rig.clock.advance(const Duration(seconds: 3));
      final Object result = await rig.pipeline.stopRecording();

      expect(result, 'call mum tomorrow at three');
      expect(
        rig.recognizer.heard,
        hasLength(12),
        reason:
            'every captured byte must reach the recogniser, not just the '
            'waveform',
      );
      expect(rig.recorder.started, isFalse);
    });

    test('shows revised words while the user is still speaking', () async {
      // Whisper rewrites earlier words as more audio arrives, so each partial
      // replaces the last rather than appending to it.
      final PipelineRig rig = rigWith(
        partials: const <String>['call', 'call mum'],
        transcript: 'call mum tomorrow',
      );

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      rig.clock.advance(const Duration(seconds: 3));
      await rig.pipeline.stopRecording();

      expect(rig.partials, <String>['call', 'call mum']);
    });

    test('trims the transcript it hands on', () async {
      final PipelineRig rig = rigWith(transcript: '  call mum tomorrow  ');

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      rig.clock.advance(const Duration(seconds: 3));

      expect(await rig.pipeline.stopRecording(), 'call mum tomorrow');
    });

    test('turns each extracted task into an editable draft', () async {
      final PipelineRig rig = rigWith(
        extracted: const <ExtractedTask>[
          ExtractedTask(
            title: 'Call mum',
            date: LocalDate(2026, 3, 12),
            time: LocalTimeOfDay.hm(15, 0),
            hasReminder: true,
          ),
          ExtractedTask(title: 'Buy milk', confidence: Confidence.low),
        ],
      );

      final CaptureOutcome outcome = await rig.pipeline.extract(
        'call mum tomorrow at three and buy milk',
      );

      expect(outcome, isA<CaptureDrafts>());
      final List<TaskDraft> drafts = (outcome as CaptureDrafts).drafts;
      expect(drafts.map((TaskDraft d) => d.title), <String>[
        'Call mum',
        'Buy milk',
      ]);
      expect(drafts.first.date, const LocalDate(2026, 3, 12));
      expect(drafts.first.time, const LocalTimeOfDay.hm(15, 0));
      expect(drafts.first.hasReminder, isTrue);
      expect(
        drafts.last.lowConfidenceDate,
        isTrue,
        reason: 'the Confirm card flags the date the parser was unsure about',
      );
      expect(
        drafts.map((TaskDraft d) => d.draftId).toSet(),
        hasLength(2),
        reason: 'two cards that share an id cannot be edited independently',
      );
    });

    test(
      'hands the extractor the transcript and the current civil time',
      () async {
        final PipelineRig rig = rigWith();

        await rig.pipeline.extract('call mum');

        expect(rig.primary.lastTranscript, 'call mum');
        expect(rig.primary.lastNow?.date, const LocalDate(2026, 3, 11));
        expect(rig.primary.lastNow?.time, const LocalTimeOfDay.hm(10, 0));
      },
    );

    test('zero extracted tasks hands back the raw transcript, not a dead end', () async {
      // ⚠️ The user spoke. Discarding what they said and asking them to say it
      // again is the single most frustrating thing this app could do.
      final PipelineRig rig = rigWith(extracted: const <ExtractedTask>[]);

      final CaptureOutcome outcome = await rig.pipeline.extract(
        'remind me about  the thing',
      );

      final CaptureDrafts drafts = outcome as CaptureDrafts;
      expect(drafts.drafts.single.title, 'remind me about the thing');
      expect(
        drafts.drafts.single.sourceTranscript,
        'remind me about  the thing',
      );
      expect(drafts.transcript, 'remind me about  the thing');
    });

    test('every draft carries the transcript it came from', () async {
      final PipelineRig rig = rigWith(
        extracted: const <ExtractedTask>[
          ExtractedTask(title: 'Call mum'),
          ExtractedTask(title: 'Buy milk'),
        ],
      );

      final CaptureDrafts drafts =
          await rig.pipeline.extract('call mum and buy milk') as CaptureDrafts;

      expect(
        drafts.drafts.map((TaskDraft d) => d.sourceTranscript),
        everyElement('call mum and buy milk'),
      );
    });
  });

  group('a clip too short to be speech', () {
    test('is refused rather than transcribed', () async {
      final PipelineRig rig = rigWith(transcript: 'uh');

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      // Under `minRecordingDuration` — a cough, or a mis-tap on the mic.
      rig.clock.advance(const Duration(milliseconds: 300));
      final Object result = await rig.pipeline.stopRecording();

      expect(result, isA<RecordingFailure>());
      expect((result as RecordingFailure).kind, RecordingFailureKind.tooShort);
      expect(
        rig.primary.lastTranscript,
        isNull,
        reason: 'nothing may be handed to the extractor that was never heard',
      );
    });

    test('still releases the microphone and the speech session', () async {
      // ⚠️ The real recorder throws `RecordingFailure(busy)` from `start()`
      // while a session is open, so a microphone left running here bricks
      // capture for the rest of the process — every later tap on the mic comes
      // back "Could not start recording". The OS recording indicator stays lit
      // too, which users report as the app listening to them.
      final PipelineRig rig = rigWith();

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      rig.clock.advance(const Duration(milliseconds: 300));
      await rig.pipeline.stopRecording();

      expect(rig.recorder.started, isFalse);
      expect(rig.recorder.cancelled, isTrue);
      expect(rig.speech.cancelled, isTrue);
    });

    test('a clip exactly at the minimum is long enough', () async {
      final PipelineRig rig = rigWith(transcript: 'ok');

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      rig.clock.advance(const Duration(milliseconds: 900));

      expect(await rig.pipeline.stopRecording(), 'ok');
    });
  });

  group('the one-minute cap', () {
    test('auto-stops the recording and flags it as truncated', () async {
      final PipelineRig rig = rigWith(transcript: 'a very long list of things');
      final Completer<void> autoStopped = Completer<void>();

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () {
          rig.autoStops++;
          if (!autoStopped.isCompleted) autoStopped.complete();
        },
      );
      // The pipeline's own ticker notices; the clock, not the test, decides.
      rig.clock.advance(const Duration(seconds: 61));
      await autoStopped.future;

      expect(rig.autoStops, 1);
      expect(rig.pipeline.hitRecordingLimit, isTrue);
      expect(
        await rig.pipeline.stopRecording(),
        'a very long list of things',
        reason: 'a capture cut off at the cap still keeps what was heard',
      );
    });

    test('a short clip does not report the limit', () async {
      final PipelineRig rig = rigWith();

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      rig.clock.advance(const Duration(seconds: 3));
      await rig.pipeline.stopRecording();

      expect(rig.pipeline.hitRecordingLimit, isFalse);
      expect(rig.autoStops, 0);
    });

    test('the elapsed track follows the clock while recording', () async {
      final PipelineRig rig = rigWith();
      final Completer<void> ticked = Completer<void>();

      await rig.pipeline.startRecording(
        onPartial: rig.partials.add,
        onAutoStop: () => rig.autoStops++,
      );
      rig.pipeline.elapsed.addListener(() {
        if (!ticked.isCompleted) ticked.complete();
      });
      rig.clock.advance(const Duration(seconds: 5));
      await ticked.future;

      expect(rig.pipeline.elapsed.value, const Duration(seconds: 5));
      rig.clock.advance(const Duration(seconds: 2));
      expect(rig.pipeline.recordedDuration, const Duration(seconds: 7));
      await rig.pipeline.stopRecording();
    });

    test('a pipeline that never recorded reports no elapsed time', () {
      final PipelineRig rig = rigWith();

      expect(rig.pipeline.recordedDuration, Duration.zero);
    });
  });

  group('AmplitudeTrack', () {
    test('keeps exactly barCount samples however much audio arrives', () {
      final AmplitudeTrack track = AmplitudeTrack(barCount: 32);
      addTearDown(track.dispose);

      for (int i = 0; i < 200; i++) {
        track.addChunk(pcm16(const <int>[1200, -1200, 900]));
      }

      expect(track.samples, hasLength(32));
    });

    test('pads a short history so the painter never sees a short list', () {
      final AmplitudeTrack track = AmplitudeTrack(barCount: 32);
      addTearDown(track.dispose);

      track.addLevel(0.5);

      expect(track.samples, hasLength(32));
      expect(track.samples.take(31), everyElement(0.0));
      expect(track.samples.last, greaterThan(0));
    });

    test('is oldest first, so the newest sample is the last bar', () {
      final AmplitudeTrack track = AmplitudeTrack(barCount: 4);
      addTearDown(track.dispose);

      for (final double level in <double>[0.1, 0.2, 0.3, 0.4, 0.5]) {
        track.addLevel(level);
      }

      final List<double> samples = track.samples;
      expect(samples, hasLength(4));
      expect(
        samples,
        orderedEquals(List<double>.from(samples)..sort()),
        reason: 'a rising input must draw a rising waveform',
      );
      expect(samples.first, lessThan(samples.last));
    });

    test('silence stays near the floor', () {
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);

      track.addChunk(pcm16(List<int>.filled(160, 0)));

      expect(track.level, lessThan(0.05));
    });

    test('a loud chunk approaches the top of the bar', () {
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);

      track.addChunk(pcm16(List<int>.filled(160, 32000)));

      expect(track.level, greaterThan(0.9));
      expect(track.level, lessThanOrEqualTo(1.0));
    });

    test('ordinary speech fills most of the bar rather than a sliver', () {
      // ⚠️ A raw RMS over 32768 barely moves for a person talking at arm's
      // length, and a waveform that never moves reads as a broken microphone —
      // which is why the fold is perceptual rather than linear.
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);

      // ~0.1 RMS: a person at arm's length.
      track.addChunk(pcm16(List<int>.filled(160, 3277)));

      expect(track.level, greaterThan(0.5));
      expect(track.level, lessThan(1.0));
    });

    test('never leaves the 0..1 range whatever it is handed', () {
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);

      for (final double level in <double>[-5, 0, 0.5, 1, 42]) {
        track.addLevel(level);
        expect(track.level, inInclusiveRange(0, 1));
      }
    });

    test('a chunk too small to hold one sample is ignored', () {
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);

      track.addChunk(Uint8List.fromList(const <int>[7]));

      expect(track.level, 0);
      expect(track.samples, everyElement(0.0));
    });

    test('a chunk that starts at an odd byte offset is folded, not thrown', () {
      // ⚠️ A chunk handed over by the platform can start at an odd
      // `offsetInBytes` — `RecordAudioRecorder.rmsOf` carries the same warning.
      // `buffer.asInt16List` at an odd offset throws, and the throw lands inside
      // the recorder's stream listener, where it kills the waveform and drops
      // the chunk on its way to the recogniser.
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);

      final Uint8List backing = Uint8List.fromList(<int>[
        0,
        ...pcm16(List<int>.filled(80, 16000)),
      ]);
      final Uint8List view = Uint8List.sublistView(backing, 1);

      expect(view.offsetInBytes.isOdd, isTrue);
      expect(() => track.addChunk(view), returnsNormally);
      expect(track.level, greaterThan(0));
    });

    test('reset clears the window between captures', () {
      final AmplitudeTrack track = AmplitudeTrack();
      addTearDown(track.dispose);
      track.addChunk(pcm16(List<int>.filled(160, 20000)));

      track.reset();

      expect(track.level, 0);
      expect(track.samples, everyElement(0.0));
    });

    test(
      'notifies its listener per chunk, which is what repaints the bars',
      () {
        final AmplitudeTrack track = AmplitudeTrack();
        addTearDown(track.dispose);
        int repaints = 0;
        track.addListener(() => repaints++);

        track.addChunk(pcm16(const <int>[1000, -1000]));
        track.addChunk(pcm16(const <int>[2000, -2000]));

        expect(repaints, 2);
      },
    );
  });

  group('ElapsedTrack', () {
    test('notifies only when the label would actually change', () {
      // A `mm:ss` label that ticks five times a second would repaint the screen
      // five times a second for four identical frames.
      final ElapsedTrack elapsed = ElapsedTrack();
      addTearDown(elapsed.dispose);
      int notifications = 0;
      elapsed.addListener(() => notifications++);

      elapsed.value = const Duration(seconds: 1);
      elapsed.value = const Duration(seconds: 1);
      elapsed.value = const Duration(seconds: 2);

      expect(notifications, 2);
    });

    test('reset returns it to zero', () {
      final ElapsedTrack elapsed = ElapsedTrack();
      addTearDown(elapsed.dispose);
      elapsed.value = const Duration(seconds: 9);

      elapsed.reset();

      expect(elapsed.value, Duration.zero);
    });
  });
}
