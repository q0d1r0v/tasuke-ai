import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/speech/whisper_decoding.dart';
import 'package:tasuke_ai/core/speech/whisper_speech_recognizer.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// The recogniser's session lifecycle, against a scripted binding.
///
/// Every one of these used to hang or lose audio, and none of it showed in the
/// pipeline tests: their fake recogniser returns from `stop()` and `cancel()`
/// at once, whatever the native side is doing.
void main() {
  // A regression here is a hang. Bound every await so it fails as one.
  const Duration bounded = Duration(seconds: 10);
  const int chunkBytes = 4096; // 128 ms, the order `record` delivers at

  late Directory dir;
  late WhisperModelAsset asset;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('whisper_recognizer_test');
    final File model = File('${dir.path}/${TasukeModels.whisperFileName}');
    await model.writeAsBytes(<int>[1, 2, 3]);
    await File('${model.path}.size').writeAsString('3');
    asset = WhisperModelAsset(supportDirPath: () async => dir.path);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Uint8List chunk(int i) => Uint8List(chunkBytes)..fillRange(0, chunkBytes, i);

  group('a model that fails to load', () {
    _test('fails the stream, and Stop and Cancel still return', () async {
      final Completer<void> load = Completer<void>();
      final _FakeController controller = _FakeController(
        load: () => load.future,
      );
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: asset,
        controller: controller,
      );
      final _Capture capture = _Capture(recognizer);
      capture.audio.add(chunk(1));
      await pumpEventQueue();

      load.completeError(StateError('stream_start: failed to load model'));
      await capture.done.future.timeout(bounded);
      expect(capture.events.single, isA<TranscriptionFailure>());

      // What the pipeline does next, on Stop and then on Cancel.
      await capture.audio.close();
      await recognizer.stop().timeout(bounded);
      await recognizer.cancel().timeout(bounded);
      await capture.sub.cancel().timeout(bounded);
    });

    _test('also when Stop comes first', () async {
      final Completer<void> load = Completer<void>();
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: asset,
        controller: _FakeController(load: () => load.future),
      );
      final _Capture capture = _Capture(recognizer);
      capture.audio.add(chunk(1));
      await pumpEventQueue();

      await capture.audio.close();
      // ⚠️ This used to wait on the feed's close(), which never completes
      // when the binding never subscribes — before the pipeline's timeout.
      await recognizer.stop().timeout(bounded);

      load.completeError(StateError('stream_start: failed to load model'));
      await capture.done.future.timeout(bounded);
      expect(capture.events.single, isA<TranscriptionFailure>());
      await recognizer.cancel().timeout(bounded);
    });

    _test(
      'through the real binding, which has no native library here',
      () async {
        // No libwhisper on the test host: the worker reports a failed load
        // before 'ready'. That used to leave transcribeLive waiting forever.
        final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
          modelAsset: asset,
        );
        final _Capture capture = _Capture(recognizer);
        capture.audio.add(chunk(1));

        await capture.done.future.timeout(bounded);
        expect(capture.events.single, isA<TranscriptionFailure>());
        await capture.audio.close();
        await recognizer.stop().timeout(bounded);
        await recognizer.cancel().timeout(bounded);
      },
    );
  });

  _test('Stop during the model load still delivers every byte', () async {
    final Completer<void> load = Completer<void>();
    final _FakeController controller = _FakeController(load: () => load.future);
    final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
      modelAsset: asset,
      controller: controller,
    );
    final _Capture capture = _Capture(recognizer);
    for (int i = 0; i < 20; i++) {
      capture.audio.add(chunk(i));
    }
    await pumpEventQueue();
    await capture.audio.close();
    await recognizer.stop().timeout(bounded);

    load.complete();
    await capture.done.future.timeout(bounded);

    // ⚠️ The session used to be stopped a microtask after it existed, with
    // most of the buffered recording still queued behind it and then dropped.
    expect(controller.sessions.single.fedAtStop, 20 * chunkBytes);
    expect(
      capture.events.whereType<SpeechFinal>().single.text,
      'call mom at five',
    );
  });

  // Stop before the feed exists: the model path is still being looked up.
  // Once with the source closed first, as the pipeline stops its recorder
  // first, and once with a source that never closes, which the Stop has to end.
  for (final bool sourceCloses in <bool>[true, false]) {
    _test('Stop before the model path is known still delivers every byte '
        '(source closes: $sourceCloses)', () async {
      final Completer<String> supportDir = Completer<String>();
      final _FakeController controller = _FakeController();
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: WhisperModelAsset(supportDirPath: () => supportDir.future),
        controller: controller,
      );
      final _Capture capture = _Capture(recognizer);
      for (int i = 0; i < 20; i++) {
        capture.audio.add(chunk(i));
      }
      await pumpEventQueue();
      // Not awaited: nothing has subscribed to it yet.
      if (sourceCloses) unawaited(capture.audio.close());
      await recognizer.stop().timeout(bounded);

      supportDir.complete(dir.path);
      await capture.done.future.timeout(bounded);

      // ⚠️ The feed used to be closed right after subscribing, before the
      // source replayed its buffer, so every chunk was dropped.
      expect(controller.sessions.single.fedAtStop, 20 * chunkBytes);
      expect(
        capture.events.whereType<SpeechFinal>().single.text,
        'call mom at five',
      );
    });
  }

  group('cancel', () {
    _test('aborts the session rather than running the final pass', () async {
      final _FakeController controller = _FakeController();
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: asset,
        controller: controller,
      );
      final _Capture capture = _Capture(recognizer);
      capture.audio.add(chunk(1));
      await pumpEventQueue();

      await recognizer.cancel().timeout(bounded);

      final _FakeSession session = controller.sessions.single;
      expect(session.aborted, isTrue);
      expect(session.stopped, isFalse, reason: 'that pass is thrown away');
      expect(capture.events.whereType<SpeechFinal>(), isEmpty);
    });

    _test(
      'during the model load waits for the session, then aborts it',
      () async {
        final Completer<void> load = Completer<void>();
        final _FakeController controller = _FakeController(
          load: () => load.future,
        );
        final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
          modelAsset: asset,
          controller: controller,
        );
        final _Capture capture = _Capture(recognizer);
        capture.audio.add(chunk(1));
        await pumpEventQueue();

        bool returned = false;
        final Future<void> cancelling = recognizer.cancel().then((_) {
          returned = true;
        });
        await pumpEventQueue();
        // `release()` frees the model right after this returns, and a context
        // the loading session still holds cannot be freed.
        expect(returned, isFalse);

        load.complete();
        await cancelling.timeout(bounded);
        final _FakeSession session = controller.sessions.single;
        expect(session.aborted, isTrue);
        expect(session.stopped, isFalse);
      },
    );

    _test('by the subscriber does not wait on a wedged session', () async {
      final _FakeController controller = _FakeController()..wedgeNext = true;
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: asset,
        controller: controller,
      );
      final _Capture capture = _Capture(recognizer);
      capture.audio.add(chunk(1));
      await pumpEventQueue();
      await capture.audio.close();
      await recognizer.stop();
      await pumpEventQueue();
      expect(controller.sessions.single.stopped, isTrue);

      // ⚠️ The pipeline's teardown awaits exactly this, after its own 30 s
      // timeout has given up on the transcript. It used to wait for the
      // decode anyway.
      await capture.sub.cancel().timeout(bounded);
    });
  });

  group('decoding', () {
    Future<_FakeController> transcribeOnce(WhisperDecoding? decoding) async {
      final _FakeController controller = _FakeController();
      final WhisperSpeechRecognizer recognizer = decoding == null
          ? WhisperSpeechRecognizer(modelAsset: asset, controller: controller)
          : WhisperSpeechRecognizer(
              modelAsset: asset,
              controller: controller,
              decoding: decoding,
            );
      final _Capture capture = _Capture(recognizer);
      capture.audio.add(chunk(1));
      await pumpEventQueue();
      await capture.audio.close();
      await capture.done.future.timeout(bounded);
      return controller;
    }

    _test(
      'primes the final pass with the Uzbek names, not the previews',
      () async {
        final _FakeController controller = await transcribeOnce(null);

        // ⚠️ Previews unprimed: primed, they cost a session 25% more time
        // instead of 12%, for text the final pass throws away.
        expect(controller.initialPrompts.single, whisperNamesPrompt);
        expect(controller.promptOnPreviews.single, isFalse);
      },
    );

    _test("passes a caller's decoding through unchanged", () async {
      final _FakeController controller = await transcribeOnce(
        WhisperDecoding.unprimed,
      );

      expect(controller.initialPrompts.single, isNull);
      expect(controller.promptOnPreviews.single, isTrue);
    });
  });

  _test(
    'a session still finishing holds the next back and leaves it alone',
    () async {
      final _FakeController controller = _FakeController()..wedgeNext = true;
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: asset,
        controller: controller,
      );

      // A: stopped, then abandoned mid-decode the way the pipeline's timeout
      // does it.
      final _Capture a = _Capture(recognizer);
      a.audio.add(chunk(1));
      await pumpEventQueue();
      await a.audio.close();
      await recognizer.stop();
      await pumpEventQueue();
      unawaited(recognizer.cancel());
      await a.sub.cancel().timeout(bounded);

      controller.wedgeNext = false;
      final _Capture b = _Capture(recognizer);
      b.audio.add(chunk(2));
      await pumpEventQueue();
      expect(
        controller.sessions,
        hasLength(1),
        reason: 'the native stream is a singleton that A still holds',
      );

      controller.sessions.first.finish('from the abandoned capture');
      await pumpEventQueue();
      expect(controller.sessions, hasLength(2));

      // A's run has ended; B's microphone must still be connected.
      b.audio.add(chunk(3));
      await pumpEventQueue();
      await b.audio.close();
      await recognizer.stop();
      await b.done.future.timeout(bounded);

      expect(controller.sessions.last.fedAtStop, 2 * chunkBytes);
      expect(b.events.whereType<SpeechFinal>().single.text, 'call mom at five');
      expect(a.events.whereType<SpeechFinal>(), isEmpty);
    },
  );
}

/// A real-async test, with the framework's stack-trace handling.
///
/// ⚠️ Not a plain `test()`: the recogniser logs a failure with its stack, and
/// outside `testWidgets` that stack is a package:stack_trace chain that
/// `debugPrintStack` asserts on — which throws inside the very catch block
/// under test.
void _test(String description, Future<void> Function() body) {
  testWidgets(description, (WidgetTester tester) async {
    await tester.runAsync(body);
  });
}

/// One `transcribeStream` call, listened to the way the pipeline does.
final class _Capture {
  _Capture(WhisperSpeechRecognizer recognizer) {
    sub = recognizer
        .transcribeStream(audio.stream)
        .listen(events.add, onError: events.add, onDone: done.complete);
  }

  final StreamController<Uint8List> audio = StreamController<Uint8List>();
  final List<Object> events = <Object>[];
  final Completer<void> done = Completer<void>();
  late final StreamSubscription<SpeechEvent> sub;
}

/// Stands in for the native session, and records how it was ended.
final class _FakeSession implements WhisperLiveSession {
  _FakeSession({required this.wedged});

  /// When set, the final pass never finishes until [finish] is called.
  final bool wedged;

  final StreamController<String> _partials = StreamController<String>();
  final Completer<String> _result = Completer<String>();
  int _fed = 0;
  bool stopped = false;
  bool aborted = false;

  /// Bytes received when `stop()` was first called.
  int? fedAtStop;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  void feed(Uint8List pcm16Bytes) {
    // As the real binding: nothing is taken after stop or abort.
    if (stopped || aborted) return;
    _fed += pcm16Bytes.length;
  }

  @override
  Future<String> stop() {
    if (!stopped && !aborted) {
      stopped = true;
      fedAtStop = _fed;
      if (!wedged) _result.complete('call mom at five');
    }
    return _result.future;
  }

  @override
  Future<String> abort() {
    if (!stopped && !aborted) {
      aborted = true;
      _result.complete('');
    }
    return _result.future;
  }

  void finish(String text) => _result.complete(text);
}

final class _FakeController extends WhisperController {
  _FakeController({this.load});

  /// The model load. Awaited before the session exists; throw to fail it.
  final Future<void> Function()? load;

  final List<_FakeSession> sessions = <_FakeSession>[];
  bool wedgeNext = false;

  /// What each `transcribeLive` call asked the binding for.
  final List<String?> initialPrompts = <String?>[];
  final List<bool> promptOnPreviews = <bool>[];

  @override
  Future<WhisperLiveSession> transcribeLive({
    WhisperModel? model,
    String? modelPath,
    required Stream<Uint8List> pcm16Stream,
    String lang = 'en',
    String? initialPrompt,
    bool suppressNonSpeechTokens = false,
    bool keepModelLoaded = false,
    double gateRmsMin = 0.0015,
    double gateVoiceRatio = 2.5,
    double gateNoiseFloorCap = 0.01,
    bool promptOnPreviews = true,
  }) async {
    initialPrompts.add(initialPrompt);
    this.promptOnPreviews.add(promptOnPreviews);
    await load?.call();
    final _FakeSession session = _FakeSession(wedged: wedgeNext);
    sessions.add(session);
    // What the real binding does, in the same order: it subscribes only
    // once the native session has started.
    pcm16Stream.listen(session.feed, onDone: session.stop);
    return session;
  }

  @override
  Future<void> releaseModel() async {}
}
