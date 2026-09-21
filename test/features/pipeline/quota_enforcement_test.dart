import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/pipeline/domain/voice_capture_pipeline.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

import '../../helpers/fakes.dart';

/// The pipeline plus the two things a quota test has to look at.
final class QuotaRig {
  QuotaRig({
    required this.pipeline,
    required this.clock,
    required this.recorder,
    required this.usage,
  });

  final VoiceCapturePipeline pipeline;
  final MutableClock clock;
  final FakeAudioRecorder recorder;
  final FakeUsageRepository usage;

  LocalDate get today => LocalDate.today(clock.nowLocal());

  Future<int> get capturesToday async => (await usage.read(today)).captureCount;

  /// The order the controller calls the pipeline in: quota, then permission,
  /// then the microphone. Returns the first refusal, or null.
  Future<Failure?> attemptCapture({bool isPro = false}) async {
    final Failure? quota = await pipeline.checkQuota(isPro: isPro);
    if (quota != null) return quota;
    final Failure? permission = await pipeline.ensureMicrophone();
    if (permission != null) return permission;
    return pipeline.startRecording(onPartial: (_) {}, onAutoStop: () {});
  }
}

QuotaRig rigAt(
  DateTime instant, {
  String transcript = 'call mum tomorrow',
  List<ExtractedTask> extracted = const <ExtractedTask>[
    ExtractedTask(title: 'Call mum'),
  ],
}) {
  final MutableClock clock = MutableClock(instant);
  final FakeAudioRecorder recorder = FakeAudioRecorder();
  final FakeUsageRepository usage = FakeUsageRepository();
  addTearDown(usage.dispose);

  int nextDraft = 0;
  final VoiceCapturePipeline pipeline = VoiceCapturePipeline(
    recorder: recorder,
    recognizer: FakeSpeechRecognizer(transcript: transcript),
    primaryExtractor: FakeTaskExtractor(result: extracted),
    fallbackExtractor: FakeTaskExtractor(result: extracted),
    permissions: FakePermissionService(),
    usage: usage,
    clock: clock,
    newDraftId: () => 'draft-${nextDraft++}',
  );
  addTearDown(pipeline.dispose);

  return QuotaRig(
    pipeline: pipeline,
    clock: clock,
    recorder: recorder,
    usage: usage,
  );
}

/// Wednesday 11 March 2026, 10:00 local.
DateTime get testNow => DateTime(2026, 3, 11, 10);

void main() {
  group('the free daily allowance', () {
    test('lets a first capture through', () async {
      final QuotaRig rig = rigAt(testNow);

      expect(await rig.pipeline.checkQuota(isPro: false), isNull);
    });

    test('lets the last free capture of the day through', () async {
      final QuotaRig rig = rigAt(testNow);
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures - 1; i++) {
        await rig.pipeline.recordUsage(taskCount: 1);
      }

      expect(await rig.pipeline.checkQuota(isPro: false), isNull);
    });

    test('refuses the one after that, and says what the numbers are', () async {
      final QuotaRig rig = rigAt(testNow);
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        await rig.pipeline.recordUsage(taskCount: 1);
      }

      final Failure? failure = await rig.pipeline.checkQuota(isPro: false);

      expect(failure, isA<QuotaFailure>());
      final QuotaFailure quota = failure! as QuotaFailure;
      expect(quota.used, ExtractionDefaults.freeDailyCaptures);
      expect(quota.limit, ExtractionDefaults.freeDailyCaptures);
    });

    test('an exhausted allowance never opens the microphone', () async {
      // ⚠️ The quota is checked BEFORE the mic. A user who is out of quota must
      // not see a recording UI they cannot use, and no audio may be captured
      // that is going to be thrown away.
      final QuotaRig rig = rigAt(testNow);
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        await rig.pipeline.recordUsage(taskCount: 1);
      }

      final Failure? failure = await rig.attemptCapture();

      expect(failure, isA<QuotaFailure>());
      expect(rig.recorder.started, isFalse);
    });

    test('Pro is not metered at all', () async {
      final QuotaRig rig = rigAt(testNow);
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures * 10; i++) {
        await rig.pipeline.recordUsage(taskCount: 1);
      }

      expect(await rig.pipeline.checkQuota(isPro: true), isNull);
      expect(await rig.attemptCapture(isPro: true), isNull);
      expect(rig.recorder.started, isTrue);
      await rig.pipeline.cancel();
    });

    test('subscribing unblocks a user who was already out', () async {
      final QuotaRig rig = rigAt(testNow);
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        await rig.pipeline.recordUsage(taskCount: 1);
      }

      expect(await rig.pipeline.checkQuota(isPro: false), isA<QuotaFailure>());
      expect(await rig.pipeline.checkQuota(isPro: true), isNull);
    });
  });

  group('the allowance is a local day, not a rolling window', () {
    test('yesterday\'s captures do not count against today', () async {
      final QuotaRig rig = rigAt(DateTime(2026, 3, 11, 23, 50));
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        await rig.pipeline.recordUsage(taskCount: 1);
      }
      expect(await rig.pipeline.checkQuota(isPro: false), isA<QuotaFailure>());

      // Twenty minutes later, on the user's own calendar, it is a new day.
      rig.clock.advance(const Duration(minutes: 20));

      expect(await rig.pipeline.checkQuota(isPro: false), isNull);
    });

    test('a capture is recorded against the day it happened on', () async {
      final QuotaRig rig = rigAt(DateTime(2026, 3, 11, 23, 50));

      await rig.pipeline.recordUsage(taskCount: 3);
      rig.clock.advance(const Duration(minutes: 20));
      await rig.pipeline.recordUsage(taskCount: 1);

      final DailyUsage wednesday = await rig.usage.read(
        const LocalDate(2026, 3, 11),
      );
      final DailyUsage thursday = await rig.usage.read(
        const LocalDate(2026, 3, 12),
      );
      expect(wednesday.captureCount, 1);
      expect(wednesday.taskCount, 3);
      expect(thursday.captureCount, 1);
      expect(thursday.taskCount, 1);
    });
  });

  group('what does NOT consume quota', () {
    // ⚠️ Usage is recorded only after tasks are saved. A capture the user got
    // nothing out of must not cost them one of five — that is the complaint
    // users actually file.

    test('a clip too short to be speech', () async {
      final QuotaRig rig = rigAt(testNow);
      await rig.attemptCapture();
      rig.clock.advance(const Duration(milliseconds: 300));

      await rig.pipeline.stopRecording();

      expect(await rig.capturesToday, 0);
    });

    test('a capture that heard only silence', () async {
      final QuotaRig rig = rigAt(testNow, transcript: '');
      await rig.attemptCapture();
      rig.clock.advance(const Duration(seconds: 3));

      final Object transcript = await rig.pipeline.stopRecording();
      final CaptureOutcome outcome = await rig.pipeline.extract(
        transcript as String,
      );

      expect(outcome, isA<CaptureRejected>());
      expect(await rig.capturesToday, 0);
    });

    test('a capture the user cancelled half-way through', () async {
      final QuotaRig rig = rigAt(testNow);
      await rig.attemptCapture();
      rig.clock.advance(const Duration(seconds: 3));

      await rig.pipeline.cancel();

      expect(await rig.capturesToday, 0);
    });

    test('a capture that produced drafts but was never saved', () async {
      // Confirm is a screen the user can back out of. Quota is spent on saved
      // tasks, not on words.
      final QuotaRig rig = rigAt(testNow);
      await rig.attemptCapture();
      rig.clock.advance(const Duration(seconds: 3));

      final Object transcript = await rig.pipeline.stopRecording();
      await rig.pipeline.extract(transcript as String);

      expect(await rig.capturesToday, 0);
    });

    test('a capture that fell back to the deterministic extractor', () async {
      final QuotaRig rig = rigAt(testNow);

      await rig.pipeline.extract('call mum tomorrow');

      expect(await rig.capturesToday, 0);
    });
  });

  group('recording a successful capture', () {
    test('spends exactly one of the five', () async {
      final QuotaRig rig = rigAt(testNow);

      await rig.pipeline.recordUsage(taskCount: 2);

      expect(await rig.capturesToday, 1);
      expect((await rig.usage.read(rig.today)).taskCount, 2);
    });

    test('a capture that saved nothing still counts as one capture', () async {
      // The user spoke, the app answered; the fact that they deleted every
      // card before saving is not a reason to hand the capture back.
      final QuotaRig rig = rigAt(testNow);

      await rig.pipeline.recordUsage(taskCount: 0);

      expect(await rig.capturesToday, 1);
      expect((await rig.usage.read(rig.today)).taskCount, 0);
    });

    test('five of them exhaust the allowance exactly', () async {
      final QuotaRig rig = rigAt(testNow);

      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        expect(
          await rig.pipeline.checkQuota(isPro: false),
          isNull,
          reason: 'capture ${i + 1} of ${ExtractionDefaults.freeDailyCaptures}',
        );
        await rig.pipeline.recordUsage(taskCount: 1);
      }

      expect(await rig.pipeline.checkQuota(isPro: false), isA<QuotaFailure>());
      expect(
        (await rig.usage.read(rig.today))
            .remaining(ExtractionDefaults.freeDailyCaptures),
        0,
      );
    });
  });
}
