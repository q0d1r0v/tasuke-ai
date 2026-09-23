// The only test in this repo that runs the REAL native stack: the vendored
// whisper.cpp binding against the bundled ggml model, on a real device.
//
//   tool/env.sh
//   adb push test-audio.wav /data/local/tmp/tasuke/jfk.wav
//   flutter test integration_test/real_pipeline_test.dart \
//     --dart-define=TASUKE_AUDIO_FIXTURE=/data/local/tmp/tasuke/jfk.wav \
//     -d <device-id>
//
// ⚠️ Why this exists, and why its absence was expensive.
//
// Every other test in the project overrides `speechRecognizerProvider` with a
// fake, because a widget test cannot load a 60 MB ggml model or open a
// microphone. That is correct — and it meant the native path had never been
// executed once, on any machine, by anything. The consequence shipped:
// `WhisperModelAsset.ensureInstalled()` had no caller at all, so the model was
// never copied out of the APK, `availability()` answered `modelUnavailable`
// forever, and every voice capture on every device died on "The voice model
// isn't ready" while 1098 tests stayed green.
//
// ⚠️ The fixture is passed by PATH, never bundled. Declaring a test WAV under
// `flutter.assets` would ship it inside the release APK to every user.
@Tags(<String>['device'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/speech/whisper_speech_recognizer.dart';

/// Path to a 16 kHz mono PCM16 WAV of clearly-spoken English.
const String audioFixturePath = String.fromEnvironment('TASUKE_AUDIO_FIXTURE');

/// What the fixture says, lowercased and stripped of punctuation.
///
/// Defaults to the whisper.cpp project's own `samples/jfk.wav`, which is the
/// canonical smoke-test clip for this engine.
const String expectedPhrase = String.fromEnvironment(
  'TASUKE_AUDIO_EXPECT',
  defaultValue: 'ask not what your country can do for you',
);

/// Strips everything a transcriber may legitimately disagree about.
String _fold(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The PCM16 payload of a RIFF/WAVE file.
///
/// ⚠️ The `data` chunk is located rather than assumed to start at byte 44.
/// Plenty of encoders write a `LIST`/`INFO` chunk first, and feeding those
/// bytes to whisper as audio produces a burst of noise and a confident
/// transcription of nothing.
Uint8List pcm16BodyOf(Uint8List wav) {
  final ByteData view = ByteData.sublistView(wav);
  if (String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }

  int offset = 12;
  while (offset + 8 <= wav.length) {
    final String id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final int size = view.getUint32(offset + 4, Endian.little);
    final int body = offset + 8;
    if (id == 'fmt ') {
      final int channels = view.getUint16(body + 2, Endian.little);
      final int rate = view.getUint32(body + 4, Endian.little);
      final int bits = view.getUint16(body + 14, Endian.little);
      expect(
        <int>[channels, rate, bits],
        <int>[1, 16000, 16],
        reason: 'whisper.cpp takes 16 kHz mono PCM16 and nothing else',
      );
    }
    if (id == 'data') {
      return Uint8List.sublistView(wav, body, body + size);
    }
    // Chunks are word-aligned; an odd size carries one pad byte.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final bool haveFixture = audioFixturePath.isNotEmpty;

  testWidgets('the bundled model installs, and whisper transcribes speech', (
    WidgetTester tester,
  ) async {
    // ⚠️ `runAsync` throughout. Every await below is real native work that
    // completes on real time; inside the default FakeAsync zone none of these
    // futures ever resolve and the test simply hangs.
    await tester.runAsync(() async {
      final WhisperModelAsset asset = WhisperModelAsset(
        supportDirPath: () async =>
            (await getApplicationSupportDirectory()).path,
      );

      // ── 1. the copy that was never wired up ──────────────────────────────
      final Stopwatch installing = Stopwatch()..start();
      final String modelPath = await asset.ensureInstalled();
      installing.stop();

      final int bytes = File(modelPath).lengthSync();
      // ignore: avoid_print — the numbers are the point of a device test.
      print(
        'whisper model: ${(bytes / 1e6).toStringAsFixed(1)} MB copied out of '
        'the bundle in ${installing.elapsedMilliseconds} ms -> $modelPath',
      );
      expect(bytes, greaterThan(50 * 1000 * 1000));
      expect(await asset.pathIfInstalled(), modelPath);

      // A second call must be cheap: it is on the launch path.
      final Stopwatch again = Stopwatch()..start();
      expect(await asset.ensureInstalled(), modelPath);
      again.stop();
      expect(
        again.elapsedMilliseconds,
        lessThan(250),
        reason: 're-installing must be a size check, not a 60 MB re-copy',
      );

      // ── 2. availability stops lying ──────────────────────────────────────
      final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
        modelAsset: asset,
      );
      expect(await recognizer.availability(), SpeechAvailability.ready);

      if (!haveFixture) {
        // ignore: avoid_print
        print('no TASUKE_AUDIO_FIXTURE — stopping after the install check');
        await recognizer.release();
        return;
      }

      // ── 3. real audio through real whisper ───────────────────────────────
      final Uint8List pcm = pcm16BodyOf(
        await File(audioFixturePath).readAsBytes(),
      );
      // ignore: avoid_print
      print(
        'fixture: ${pcm.lengthInBytes} bytes '
        '(${(pcm.lengthInBytes / 32000).toStringAsFixed(1)} s of audio)',
      );

      // 4096 bytes is 128 ms, which is the order `record` delivers at. Feeding
      // the whole clip as one chunk would exercise a path the app never uses.
      const int chunk = 4096;
      Stream<Uint8List> feed() async* {
        for (int i = 0; i < pcm.lengthInBytes; i += chunk) {
          yield Uint8List.sublistView(
            pcm,
            i,
            (i + chunk).clamp(0, pcm.lengthInBytes),
          );
          await Future<void>.delayed(Duration.zero);
        }
      }

      final List<SpeechEvent> events = <SpeechEvent>[];
      final Completer<void> finished = Completer<void>();
      final Stopwatch transcribing = Stopwatch()..start();

      final StreamSubscription<SpeechEvent> sub = recognizer
          .transcribeStream(feed())
          .listen(
            events.add,
            onError: (Object error, StackTrace stack) {
              if (!finished.isCompleted) finished.completeError(error, stack);
            },
            onDone: () {
              if (!finished.isCompleted) finished.complete();
            },
          );

      await finished.future.timeout(const Duration(minutes: 3));
      transcribing.stop();
      await sub.cancel();

      final SpeechFinal result = events.whereType<SpeechFinal>().single;
      // ignore: avoid_print
      print(
        'transcribed in ${transcribing.elapsedMilliseconds} ms: '
        '"${result.text}"',
      );
      // ignore: avoid_print
      print('partials: ${events.whereType<SpeechPartial>().length}');

      expect(
        _fold(result.text),
        contains(_fold(expectedPhrase)),
        reason: 'whisper heard something, but not what was said',
      );

      await recognizer.release();
    });
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets(
    'Stop returns promptly even when the decoder is behind',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final WhisperModelAsset asset = WhisperModelAsset(
          supportDirPath: () async =>
              (await getApplicationSupportDirectory()).path,
        );
        await asset.ensureInstalled();
        final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
          modelAsset: asset,
        );

        // ⚠️ Four copies of an 11 s clip — 44 s, the length of the recording the
        // bug was first reported on — pushed in as fast as the stream will take
        // them, with no pacing at all. That is the shape of a phone whose
        // decoder runs slower than real time.
        //
        // Before backpressure, every 4 KiB chunk was its own message in the
        // worker's mailbox: ~350 of them, each triggering inference, with
        // `['stop']` queued behind the lot. Stop could not even begin for
        // minutes, which on the phone looked like a dead button and a timer that
        // would not stop counting.
        final Uint8List clip = pcm16BodyOf(
          await File(audioFixturePath).readAsBytes(),
        );

        const int chunk = 4096;
        Stream<Uint8List> feed() async* {
          for (int pass = 0; pass < 4; pass++) {
            for (int i = 0; i < clip.lengthInBytes; i += chunk) {
              yield Uint8List.sublistView(
                clip,
                i,
                (i + chunk).clamp(0, clip.lengthInBytes),
              );
              await Future<void>.delayed(Duration.zero);
            }
          }
        }

        final Completer<void> finished = Completer<void>();
        final List<SpeechEvent> events = <SpeechEvent>[];
        final StreamSubscription<SpeechEvent> sub = recognizer
            .transcribeStream(feed())
            .listen(
              events.add,
              onError: (Object error, StackTrace stack) {
                if (!finished.isCompleted) finished.completeError(error, stack);
              },
              onDone: () {
                if (!finished.isCompleted) finished.complete();
              },
            );

        // Let a couple of seconds of audio go in, then stop like the user does.
        await Future<void>.delayed(const Duration(seconds: 2));
        final Stopwatch stopping = Stopwatch()..start();
        await recognizer.stop();
        await finished.future.timeout(const Duration(minutes: 3));
        stopping.stop();
        await sub.cancel();

        // ignore: avoid_print — the number is the point.
        print('Stop -> final took ${stopping.elapsedMilliseconds} ms');
        expect(
          stopping.elapsedMilliseconds,
          lessThan(90000),
          reason:
              'Stop must be at most a couple of inferences away, never a '
              'drained backlog',
        );
        expect(events.whereType<SpeechFinal>(), hasLength(1));

        await recognizer.release();
      });
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: !haveFixture,
  );
}
