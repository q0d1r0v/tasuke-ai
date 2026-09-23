// A device-free, end-to-end measurement of the voice path: WAV clips go
// through the app's own WhisperSpeechRecognizer (the vendored whisper.cpp,
// built for the host) and the transcript through RuleBasedTaskExtractor.
//
//   tool/asr_eval/build_host_whisper.sh <dir>        # the host library
//   <venv>/bin/python tool/asr_eval/generate_corpus.py \
//       --out <corpus> --voices-dir <voices>           # the clips (TTS)
//   . tool/env.sh
//   LD_LIBRARY_PATH=<dir> \
//   TASUKE_ASR_MANIFEST=<corpus>/manifest.json \
//   TASUKE_ASR_OUT=/path/to/results.json \
//     flutter test test/asr/asr_eval_test.dart --tags asr
//
// It measures; it never fails on accuracy. It fails only when the harness
// itself cannot run: an unreadable manifest, a WAV that is not 16 kHz mono
// PCM16, a native library that will not load, a recogniser that breaks its
// contract or wedges. Without TASUKE_ASR_MANIFEST it skips, and the `asr` tag
// keeps it out of tool/verify.sh altogether.
//
// Environment:
//   TASUKE_ASR_MANIFEST  the manifest (required; the test skips without it)
//   TASUKE_ASR_FILTER    keep clips whose id or condition contains this
//                        (case-insensitive), e.g. "white", "us-amy", "cxdev"
//   TASUKE_ASR_LIMIT     keep the first N clips left after the filter
//   TASUKE_ASR_OUT       write every clip's result and the summary here (JSON)
//   TASUKE_ASR_REALTIME  1 = feed audio at recording speed instead of as fast
//                        as the recogniser takes it (see [_commitMs])
//
// Manifest (generate_corpus.py writes a bare list of clips):
//   [
//     {
//       "id": "clean_us-amy_dev-001",        // default: the WAV's file name
//       "wav": "/abs/or/relative/to/manifest/clean_us-amy_dev-001.wav",
//       "text": "Call the dentist tomorrow at 3 PM",
//       "now": "2026-09-21T10:00",
//       "tasks": [{"title": "Call the dentist",
//                  "date": "2026-09-22", "time": "15:00"}],
//       "condition": "clean",                // optional
//       "voice": "us-amy",                   // optional
//       "case_id": "dev-001",                // optional
//       "clean_pair": null                   // optional: on a degraded clip,
//     }                                      // the id of its clean twin
//   ]
// or {"now": <default for every clip>, "clips": [...]}.
//
// `tasks` has the shape of the text corpora in test/fixtures/nl/, `'*'`
// wildcards included, and is scored by test/helpers/extraction_scoring.dart.
// The extractor also runs on `text` itself, so a clip that is right from the
// text and wrong from the audio is a failure the ASR caused.
@Tags(<String>['asr'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/speech/whisper_decoding.dart';
import 'package:tasuke_ai/core/speech/whisper_speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';

import '../helpers/extraction_scoring.dart';

/// 16 kHz mono PCM16.
const int _bytesPerSecond = 16000 * 2;

/// 2048 samples, 128 ms: the size `record` delivers on a phone. Feeding the
/// whole clip as one chunk would exercise a path the app never takes.
const int _chunkBytes = 4096;

/// The native window commits its text once it passes 25 s, in whichever pass
/// crosses the line, and where that lands depends on how fast audio arrived.
/// Below it the final pass decodes the whole window from scratch, so feeding
/// faster than real time gives the phone's transcript. Above it, it may not:
/// such clips are counted in the report, and TASUKE_ASR_REALTIME=1 removes the
/// difference at the cost of real-time runs.
const int _commitMs = 25000;

/// After this many infrastructure errors in a row the rest would fail the same
/// way; the run stops and reports what it has.
const int _maxConsecutiveErrors = 5;

const int _worstShown = 40;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> env = Platform.environment;
  final String? manifest = _env(env, 'TASUKE_ASR_MANIFEST');

  test(
    'voice evaluation: WAV -> whisper -> rule-based extractor',
    () => _evaluate(manifest!, env),
    skip: manifest == null
        ? 'set TASUKE_ASR_MANIFEST to a manifest.json to run the voice '
              'evaluation (see the header of test/asr/asr_eval_test.dart)'
        : false,
    timeout: Timeout.none,
  );
}

String? _env(Map<String, String> env, String key) {
  final String? value = env[key]?.trim();
  return value == null || value.isEmpty ? null : value;
}

// ─── the run ───────────────────────────────────────────────────────────────

Future<void> _evaluate(String manifestPath, Map<String, String> env) async {
  _checkScorer();

  final File manifestFile = File(manifestPath).absolute;
  if (!manifestFile.existsSync()) {
    fail('TASUKE_ASR_MANIFEST: ${manifestFile.path} does not exist');
  }
  final List<_Clip> everything = _loadManifest(manifestFile);

  final String? filter = _env(env, 'TASUKE_ASR_FILTER');
  final String? limitText = _env(env, 'TASUKE_ASR_LIMIT');
  final int? limit = limitText == null ? null : int.tryParse(limitText);
  if (limitText != null && (limit == null || limit < 1)) {
    fail('TASUKE_ASR_LIMIT must be a positive integer, not "$limitText"');
  }
  final String? outPath = _env(env, 'TASUKE_ASR_OUT');
  final bool realtime = _env(env, 'TASUKE_ASR_REALTIME') == '1';

  List<_Clip> clips = everything;
  if (filter != null) {
    final String f = filter.toLowerCase();
    clips = <_Clip>[
      for (final _Clip c in clips)
        if (c.id.toLowerCase().contains(f) ||
            c.condition.toLowerCase().contains(f))
          c,
    ];
  }
  if (clips.isEmpty) {
    fail(
      'TASUKE_ASR_FILTER "$filter" matches none of the '
      '${everything.length} clips',
    );
  }
  if (limit != null && clips.length > limit) clips = clips.sublist(0, limit);

  _say(
    'ASR eval: ${clips.length} of ${everything.length} clips from '
    '${manifestFile.path}'
    '${filter == null ? '' : ' · filter "$filter"'}'
    '${limit == null ? '' : ' · limit $limit'}'
    ' · fed ${realtime ? 'in real time' : 'as fast as whisper takes it'}',
  );

  final Directory modelDir = Directory.systemTemp.createTempSync('tasuke_asr_');
  final WhisperModelAsset asset = WhisperModelAsset(
    supportDirPath: () async => modelDir.path,
  );
  // ⚠️ ONE recogniser for every clip, as the app holds one: the model stays
  // parked in native memory between sessions, so a clip's time is a decode,
  // not a 60 MB load.
  final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
    modelAsset: asset,
  );
  const RuleBasedTaskExtractor extractor = RuleBasedTaskExtractor();

  final List<_Result> results = <_Result>[];
  final Map<String, Object?> meta = <String, Object?>{
    'manifest': manifestFile.path,
    'generated_at': DateTime.now().toIso8601String(),
    'model': TasukeModels.whisperAsset,
    // What the recogniser primes whisper with: results files from before and
    // after a prompt change are otherwise indistinguishable.
    'initial_prompt': WhisperDecoding.app.initialPrompt,
    'prompt_on_previews': WhisperDecoding.app.promptOnPreviews,
    'filter': filter,
    'limit': limit,
    'realtime': realtime,
    'chunk_bytes': _chunkBytes,
  };
  String? aborted;

  try {
    final Stopwatch installing = Stopwatch()..start();
    await asset.ensureInstalled();
    installing.stop();
    expect(
      await recognizer.availability(),
      SpeechAvailability.ready,
      reason: 'the bundled model did not install from the asset bundle',
    );

    // A second of silence first. It loads the model and parks it, so the
    // first real clip's time is not a load, and it is the check that the
    // native library is there at all: silence must come back as noSpeech,
    // and anything else is the engine failing to start.
    final _Decode warm = await _transcribe(
      recognizer,
      Uint8List(_bytesPerSecond),
      realtime: false,
    );
    if (warm.error != null) {
      fail(
        'whisper did not start: ${warm.error}. Is LD_LIBRARY_PATH pointing '
        'at a directory with a host build of libwhisper_ggml.so?',
      );
    }
    meta['install_ms'] = installing.elapsedMilliseconds;
    meta['warmup_ms'] = warm.ms;
    _say(
      'model copied out of the bundle in ${installing.elapsedMilliseconds} ms'
      ', loaded and parked in ${warm.ms} ms\n',
    );

    int consecutiveErrors = 0;
    for (int i = 0; i < clips.length; i++) {
      final _Result result;
      try {
        result = await _runClip(clips[i], recognizer, extractor, realtime);
      } on _Wedged catch (wedged) {
        results.add(_Result(clips[i])..error = wedged.message);
        aborted = 'stopped at clip ${i + 1}: ${wedged.message}';
        break;
      }
      results.add(result);
      _say(_progressLine(i + 1, clips.length, result));
      consecutiveErrors = result.error == null ? 0 : consecutiveErrors + 1;
      if (consecutiveErrors >= _maxConsecutiveErrors) {
        aborted =
            'stopped at clip ${i + 1}: $_maxConsecutiveErrors '
            'infrastructure errors in a row';
        break;
      }
    }
  } finally {
    try {
      await recognizer.release().timeout(const Duration(seconds: 60));
    } on Object catch (error) {
      _say('releasing the model failed: $error');
    }
    try {
      modelDir.deleteSync(recursive: true);
    } on Object {
      // A temp directory left behind is not worth failing a measurement for.
    }
  }

  final _Summary summary = _report(results);
  if (aborted != null) _say('\n⚠️ $aborted');

  if (outPath != null) {
    final File out = File(outPath).absolute;
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        ...meta,
        'clips_in_manifest': everything.length,
        'clips_selected': clips.length,
        'aborted': aborted,
        'summary': <String, Object?>{
          'overall': summary.all.toJson(),
          'by_condition': <String, Object?>{
            for (final _Stats s in summary.conditions) s.key: s.toJson(),
          },
          'clean_paired': summary.cleanPaired?.toJson(),
          'by_voice': <String, Object?>{
            for (final _Stats s in summary.voices) s.key: s.toJson(),
          },
          'worst': <String>[for (final _Result r in summary.worst) r.clip.id],
        },
        'clips': <Map<String, Object?>>[
          for (final _Result r in results) r.toJson(),
        ],
      }),
    );
    _say('\nresults written to ${out.path}');
  }

  final List<_Result> broken = <_Result>[
    for (final _Result r in results)
      if (r.error != null) r,
  ];
  if (broken.isNotEmpty || aborted != null) {
    fail(
      '${broken.length} clip(s) hit an infrastructure error'
      '${aborted == null ? '' : ' ($aborted)'}:\n'
      '${broken.take(20).map((_Result r) => '  ${r.clip.id}: ${r.error}').join('\n')}',
    );
  }
}

Future<_Result> _runClip(
  _Clip clip,
  WhisperSpeechRecognizer recognizer,
  RuleBasedTaskExtractor extractor,
  bool realtime,
) async {
  final _Result result = _Result(clip);

  final Uint8List pcm;
  try {
    pcm = _pcm16Of(File(clip.wavPath).readAsBytesSync());
  } on Object catch (error) {
    return result..error = '${clip.wavPath}: $error';
  }
  result.audioMs = pcm.length * 1000 ~/ _bytesPerSecond;

  final _Decode decode = await _transcribe(recognizer, pcm, realtime: realtime);
  result
    ..ms = decode.ms
    ..stopMs = decode.stopMs
    ..partials = decode.partials;
  if (decode.error != null) return result..error = decode.error;

  result
    ..transcript = decode.text!
    ..noSpeech = decode.noSpeech
    ..refTokens = werTokens(clip.text)
    ..hypTokens = werTokens(decode.text!);
  result.edits = _editDistance(result.refTokens, result.hypTokens);
  result.wer = result.refTokens.isEmpty
      ? (result.hypTokens.isEmpty ? 0 : 1)
      : result.edits / result.refTokens.length;

  final LabelledNote note = LabelledNote(clip.text, clip.expected);
  final List<String> extractErrors = <String>[];
  result.fromAudio = await _extract(
    extractor,
    result.transcript,
    clip.now,
    (String e) => extractErrors.add('from audio: $e'),
  );
  result.fromText = await _extract(
    extractor,
    clip.text,
    clip.now,
    (String e) => extractErrors.add('from text: $e'),
  );
  if (extractErrors.isNotEmpty) result.extractError = extractErrors.join('; ');
  result
    ..audio = scoreNote(note, result.fromAudio)
    ..text = scoreNote(note, result.fromText);
  return result;
}

/// An extractor that throws is a product bug worth seeing, not a broken
/// harness: it is recorded against the clip and scored as no tasks.
Future<List<ExtractedTask>> _extract(
  RuleBasedTaskExtractor extractor,
  String transcript,
  LocalDateTime now,
  void Function(String) onError,
) async {
  try {
    return await extractor.extract(transcript, now: now);
  } on Object catch (error) {
    onError('$error');
    return const <ExtractedTask>[];
  }
}

// ─── the recogniser, driven the way the app drives it ──────────────────────

final class _Decode {
  /// The final transcript; '' when whisper heard no speech. Null on error.
  String? text;
  bool noSpeech = false;

  /// Set when the harness could not get a transcript: a native failure, a
  /// broken contract, a wedge that a cancel recovered from.
  String? error;

  /// From the first chunk to the SpeechFinal.
  int ms = 0;

  /// From end-of-input (the recogniser has taken every chunk and the close)
  /// to the SpeechFinal: what a user waits for after Stop.
  int? stopMs;
  int partials = 0;
}

/// The recogniser did not let go of its native session even when cancelled.
/// The next session would wait on it forever, so the run cannot go on.
final class _Wedged implements Exception {
  const _Wedged(this.message);

  final String message;
}

Future<_Decode> _transcribe(
  WhisperSpeechRecognizer recognizer,
  Uint8List pcm, {
  required bool realtime,
}) async {
  final _Decode decode = _Decode();
  final Duration deadline = Duration(
    milliseconds: math.max(120000, pcm.length * 10000 ~/ _bytesPerSecond),
  );

  // What the recorder is to the app: a single-subscription stream, which
  // buffers while the recogniser has not attached yet.
  final StreamController<Uint8List> mic = StreamController<Uint8List>();
  final Completer<void> finished = Completer<void>();
  final List<String> finals = <String>[];
  Object? streamError;
  int? finalAt;
  int? inputEndAt;
  final Stopwatch clock = Stopwatch()..start();

  final StreamSubscription<SpeechEvent> sub = recognizer
      .transcribeStream(mic.stream)
      .listen(
        (SpeechEvent event) {
          switch (event) {
            case SpeechFinal(:final String text):
              finals.add(text);
              finalAt ??= clock.elapsedMilliseconds;
            case SpeechPartial():
              decode.partials++;
            case SpeechAmplitude():
            case SpeechError():
              break;
          }
        },
        onError: (Object error, StackTrace _) => streamError ??= error,
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
      );

  for (int offset = 0; offset < pcm.length; offset += _chunkBytes) {
    // The recogniser already gave up (it failed to start): stop talking.
    if (finished.isCompleted) break;
    final int end = math.min(offset + _chunkBytes, pcm.length);
    mic.add(Uint8List.sublistView(pcm, offset, end));
    if (realtime) {
      final int dueMs = end * 1000 ~/ _bytesPerSecond;
      await Future<void>.delayed(
        Duration(milliseconds: math.max(0, dueMs - clock.elapsedMilliseconds)),
      );
    } else {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // End of input: what `record`'s stop does to its stream. `close()` completes
  // once the recogniser's subscription has taken the done event — so once
  // every chunk before it has gone into whisper's feed.
  final Future<void> closed = mic.close();
  bool timedOut = false;
  try {
    await Future.any(<Future<void>>[closed, finished.future]).timeout(deadline);
    inputEndAt = clock.elapsedMilliseconds;
    // Then Stop, in the pipeline's order: recorder first, recogniser second.
    // ⚠️ Not before the done event has been taken. `stop()` closes whisper's
    // feed at once, and a chunk still on its way into it is dropped — the
    // last 128 ms of the clip, which is where "at 3 PM" usually is. After it,
    // this is the no-op the contract promises ("a SpeechFinal when pcm16
    // closes or stop is called").
    await recognizer.stop();
    await finished.future.timeout(deadline);
  } on TimeoutException {
    timedOut = true;
  }

  if (timedOut) {
    // Discard the session, as the pipeline does when its own deadline fires.
    // Awaited here, unlike there: the next clip's session waits for this one
    // to hand the native context back.
    try {
      await recognizer.cancel().timeout(const Duration(seconds: 60));
    } on TimeoutException {
      unawaited(sub.cancel());
      throw _Wedged(
        'no transcript after ${deadline.inSeconds} s, and cancel() did not '
        'release the session',
      );
    }
    await sub.cancel();
    decode
      ..ms = clock.elapsedMilliseconds
      ..error = 'no transcript after ${deadline.inSeconds} s; cancelled';
    return decode;
  }
  await sub.cancel();

  final int? finalMs = finalAt;
  final int? endMs = inputEndAt;
  final Object? error = streamError;
  decode
    ..ms = finalMs ?? clock.elapsedMilliseconds
    ..stopMs = finalMs != null && endMs != null
        ? math.max(0, finalMs - endMs)
        : null;
  if (finals.length > 1) {
    decode.error = 'contract: ${finals.length} SpeechFinal events';
  } else if (finals.length == 1) {
    if (error != null) {
      decode.error = 'contract: a SpeechFinal and an error ($error)';
    } else {
      decode.text = finals.single;
    }
  } else if (error is TranscriptionFailure &&
      error.kind == TranscriptionFailureKind.noSpeech) {
    // Whisper heard nothing it would call speech. That is a result — an
    // empty transcript — not a broken harness.
    decode
      ..text = ''
      ..noSpeech = true;
  } else if (error != null) {
    decode.error = '$error';
  } else {
    decode.error =
        'contract: the stream ended with no SpeechFinal and no error';
  }
  return decode;
}

/// The PCM16 payload of a RIFF/WAVE file, after checking it is 16 kHz mono
/// PCM16 — whisper.cpp takes nothing else and transcribes noise from anything
/// else, confidently.
///
/// ⚠️ The `data` chunk is located, never assumed to start at byte 44: plenty
/// of writers put a `LIST` chunk first, and those bytes fed as audio are a
/// burst of noise at the start of every clip.
Uint8List _pcm16Of(Uint8List wav) {
  if (wav.length < 12 ||
      String.fromCharCodes(wav, 0, 4) != 'RIFF' ||
      String.fromCharCodes(wav, 8, 12) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  final ByteData view = ByteData.sublistView(wav);
  bool sawFormat = false;
  int offset = 12;
  while (offset + 8 <= wav.length) {
    final String id = String.fromCharCodes(wav, offset, offset + 4);
    final int size = view.getUint32(offset + 4, Endian.little);
    final int body = offset + 8;
    if (id == 'fmt ') {
      if (size < 16 || body + 16 > wav.length) {
        throw const FormatException('truncated fmt chunk');
      }
      int format = view.getUint16(body, Endian.little);
      final int channels = view.getUint16(body + 2, Endian.little);
      final int rate = view.getUint32(body + 4, Endian.little);
      final int bits = view.getUint16(body + 14, Endian.little);
      // WAVE_FORMAT_EXTENSIBLE: the real format leads the sub-format GUID.
      if (format == 0xFFFE && size >= 40 && body + 26 <= wav.length) {
        format = view.getUint16(body + 24, Endian.little);
      }
      if (format != 1 || channels != 1 || rate != 16000 || bits != 16) {
        throw FormatException(
          'need 16 kHz mono PCM16, got format $format, $channels channel(s), '
          '$rate Hz, $bits bit',
        );
      }
      sawFormat = true;
    } else if (id == 'data') {
      if (!sawFormat) throw const FormatException('data chunk before fmt');
      // A streaming writer that never went back to patch the size leaves 0 or
      // 0xFFFFFFFF; the audio then runs to the end of the file.
      final bool unpatched = size == 0 || size == 0xFFFFFFFF;
      if (!unpatched && body + size > wav.length) {
        throw FormatException(
          'data chunk says $size bytes, the file holds ${wav.length - body}',
        );
      }
      final int end = unpatched ? wav.length : body + size;
      // Whole samples only.
      return Uint8List.sublistView(wav, body, end - ((end - body) & 1));
    }
    // Chunks are word-aligned: an odd size carries one pad byte.
    offset = body + size + (size & 1);
  }
  throw FormatException(sawFormat ? 'no data chunk' : 'no fmt chunk');
}

// ─── the manifest ──────────────────────────────────────────────────────────

final class _Clip {
  const _Clip({
    required this.id,
    required this.wavPath,
    required this.text,
    required this.nowIso,
    required this.now,
    required this.expected,
    required this.condition,
    required this.voice,
    required this.cleanPair,
  });

  final String id;
  final String wavPath;
  final String text;
  final String nowIso;
  final LocalDateTime now;
  final List<ExpectedTask> expected;
  final String condition;
  final String voice;

  /// The id of the clean clip of the same case and voice, on a degraded clip.
  final String? cleanPair;
}

List<_Clip> _loadManifest(File file) {
  final Object? doc;
  try {
    doc = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    fail('${file.path} is not JSON: $error');
  }
  final Object? defaultNow = doc is Map<String, Object?> ? doc['now'] : null;
  final Object? list = switch (doc) {
    final List<Object?> entries => entries,
    final Map<String, Object?> map => map['clips'] ?? map['entries'],
    _ => null,
  };
  if (list is! List<Object?>) {
    fail('${file.path}: expected a list of clips, or {"clips": [...]}');
  }

  final Set<String> ids = <String>{};
  final List<_Clip> clips = <_Clip>[];
  for (int i = 0; i < list.length; i++) {
    final Object? raw = list[i];
    Never bad(String why) => fail('${file.path}: clip #${i + 1} $why');
    if (raw is! Map<String, Object?>) bad('is not an object');

    final Object? wav = raw['wav'] ?? raw['audio'] ?? raw['path'];
    if (wav is! String || wav.isEmpty) bad('has no "wav" path');
    final Object? text = raw['text'] ?? raw['note'];
    if (text is! String) bad('has no "text"');
    final Object? tasks = raw['tasks'];
    if (tasks is! List<Object?>) bad('has no "tasks" list');
    final Object? nowIso = raw['now'] ?? defaultNow;
    if (nowIso is! String) bad('has no "now", and the manifest sets none');
    final LocalDateTime? now = LocalDateTime.tryParseIso(nowIso);
    if (now == null) bad('has a "now" that is not YYYY-MM-DDTHH:MM: $nowIso');

    final List<ExpectedTask> expected = <ExpectedTask>[];
    for (final Object? t in tasks) {
      if (t is! Map<String, Object?> || t['title'] is! String) {
        bad('has a task without a "title": $t');
      }
      final Object? date = t['date'];
      final Object? time = t['time'];
      if ((date != null && date is! String) ||
          (time != null && time is! String)) {
        bad('has a task whose date or time is not a string: $t');
      }
      expected.add(
        ExpectedTask(t['title']! as String, date as String?, time as String?),
      );
    }

    final String wavPath = File(wav).isAbsolute
        ? wav
        : file.parent.uri.resolveUri(Uri.file(wav)).toFilePath();
    final Object? id = raw['id'];
    final String clipId = id is String && id.isNotEmpty
        ? id
        : wavPath
              .split(Platform.pathSeparator)
              .last
              .replaceAll(RegExp(r'\.wav$', caseSensitive: false), '');
    if (!ids.add(clipId)) bad('repeats the id "$clipId"');

    final Object? condition = raw['condition'];
    final Object? voice = raw['voice'];
    final Object? cleanPair = raw['clean_pair'];
    clips.add(
      _Clip(
        id: clipId,
        wavPath: wavPath,
        text: text,
        nowIso: nowIso,
        now: now,
        expected: expected,
        condition: condition is String && condition.isNotEmpty
            ? condition
            : 'default',
        voice: voice is String && voice.isNotEmpty ? voice : 'default',
        cleanPair: cleanPair is String && cleanPair.isNotEmpty
            ? cleanPair
            : null,
      ),
    );
  }
  if (clips.isEmpty) fail('${file.path} lists no clips');
  return clips;
}

// ─── word error rate ───────────────────────────────────────────────────────

/// The words of [text] as WER counts them.
///
/// Lowercased, punctuation gone, and every spelling of a number or a time of
/// day folded to one form, so that "3 PM", "3 p.m.", "3pm" and "three pm" are
/// all `3 pm`, "3:30" is "3.30" is "three thirty", "7:40 pm" is "740 p.m.",
/// "7:05" is "seven oh five", "3:00" is "three o'clock" is `3`, and "21st" is
/// "twenty-first". Whisper writes digits and TTS reads words, or the other
/// way round; neither is a recognition error, and counting them as one would
/// bury the real ones.
List<String> werTokens(String text) {
  String s = text.toLowerCase().replaceAll(RegExp('[’‘`´]'), "'");
  s = s
      .replaceAllMapped(
        RegExp(r'\$\s?(\d[\d,]*(?:\.\d+)?)'),
        (Match m) => ' ${m[1]} dollars ',
      )
      .replaceAll('%', ' percent ')
      .replaceAll('&', ' and ')
      .replaceAllMapped(RegExp(r'(\d),(?=\d{3}\b)'), (Match m) => m[1]!)
      // A clock time, written 7:40 or (whisper's other habit) 7.40.
      .replaceAllMapped(
        RegExp(r'\b(\d{1,2})[:.]00\b'),
        (Match m) => ' ${m[1]} ',
      )
      .replaceAllMapped(
        RegExp(r'\b(\d{1,2})[:.](\d{2})\b'),
        (Match m) => ' ${m[1]} ${m[2]} ',
      )
      // a.m. / p.m. in every spelling → am / pm, split off a digit.
      .replaceAllMapped(
        RegExp(r'(?<![a-z])([ap])\s?\.\s?m\b\.?'),
        (Match m) => ' ${m[1]}m ',
      )
      .replaceAllMapped(
        RegExp(r'(\d)\s*([ap]m)\b'),
        (Match m) => '${m[1]} ${m[2]}',
      )
      // "740 pm", "1130 am": a clock time with the colon left out.
      .replaceAllMapped(
        RegExp(r'\b(\d{1,2})([0-5]\d) ([ap]m)\b'),
        (Match m) => '${m[1]} ${m[2]} ${m[3]}',
      )
      .replaceAllMapped(RegExp(r'\b(\d+)(?:st|nd|rd|th)\b'), (Match m) => m[1]!)
      .replaceAll(RegExp(r"\bo'?\s?clock\b"), ' ')
      .replaceAll("'", '')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ');
  final List<String> words = <String>[
    for (final String w in s.split(' '))
      if (w.isNotEmpty) _spellings[w] ?? w,
  ];
  return _numbersAsDigits(words);
}

const Map<String, String> _spellings = <String, String>{
  'ok': 'okay',
  'mr': 'mister',
  'mrs': 'missus',
  'dr': 'doctor',
};

const Map<String, int> _small = <String, int>{
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'first': 1,
  'second': 2,
  'third': 3,
  'fourth': 4,
  'fifth': 5,
  'sixth': 6,
  'seventh': 7,
  'eighth': 8,
  'ninth': 9,
  'tenth': 10,
  'eleventh': 11,
  'twelfth': 12,
  'thirteenth': 13,
  'fourteenth': 14,
  'fifteenth': 15,
  'sixteenth': 16,
  'seventeenth': 17,
  'eighteenth': 18,
  'nineteenth': 19,
};

const Map<String, int> _tens = <String, int>{
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
  'twentieth': 20,
  'thirtieth': 30,
  'fortieth': 40,
  'fiftieth': 50,
  'sixtieth': 60,
  'seventieth': 70,
  'eightieth': 80,
  'ninetieth': 90,
};

enum _Part { none, small, tens, scale }

/// Spelled-out numbers → digits: "twenty five" → 25, "two thousand twenty
/// six" → 2026, "twenty-first" → 21. Numbers said side by side stay apart, as
/// a clock time's digits do: "three thirty" → 3 30, like "3:30".
List<String> _numbersAsDigits(List<String> words) {
  final List<String> out = <String>[];
  int? value;
  _Part part = _Part.none;
  void flush() {
    if (value != null) out.add('$value');
    value = null;
    part = _Part.none;
  }

  bool isNumberWord(String w) =>
      _small.containsKey(w) ||
      _tens.containsKey(w) ||
      w == 'hundred' ||
      w == 'thousand';

  for (int i = 0; i < words.length; i++) {
    final String w = words[i];
    final String? next = i + 1 < words.length ? words[i + 1] : null;
    final int? small = _small[w];
    final int? tens = _tens[w];
    final bool ordinal = w.endsWith('th') || _ordinalWords.contains(w);
    final int? v = value;
    if (small != null) {
      if (v != null &&
          ((part == _Part.tens && small < 10) || part == _Part.scale)) {
        value = v + small;
      } else {
        flush();
        value = small;
      }
      part = _Part.small;
      if (ordinal) flush();
    } else if (tens != null) {
      if (v != null && part == _Part.scale) {
        value = v + tens;
      } else {
        flush();
        value = tens;
      }
      part = _Part.tens;
      if (ordinal) flush();
    } else if (w == 'hundred') {
      final int low = (v ?? 0) % 1000;
      if (v == null) {
        value = 100;
      } else if (low > 0 && low < 100 && part != _Part.scale) {
        value = v - low + low * 100;
      } else {
        flush();
        value = 100;
      }
      part = _Part.scale;
    } else if (w == 'thousand') {
      if (v == null) {
        value = 1000;
      } else if (v < 1000) {
        value = v * 1000;
      } else {
        flush();
        value = 1000;
      }
      part = _Part.scale;
    } else if (w == 'and' &&
        part == _Part.scale &&
        next != null &&
        isNumberWord(next)) {
      // "one hundred and five".
      continue;
    } else if ((w == 'oh' || w == 'o') &&
        v != null &&
        next != null &&
        (_small[next] ?? 10) < 10) {
      // "seven oh five" is 7:05, which folds to 7 5.
      flush();
    } else if (RegExp(r'^\d+$').hasMatch(w)) {
      flush();
      out.add(w.replaceFirst(RegExp(r'^0+(?=\d)'), ''));
    } else {
      flush();
      out.add(w);
    }
  }
  flush();
  return out;
}

const Set<String> _ordinalWords = <String>{'first', 'second', 'third'};

/// Levenshtein distance over words: substitutions + deletions + insertions.
int _editDistance(List<String> ref, List<String> hyp) {
  List<int> previous = List<int>.generate(hyp.length + 1, (int j) => j);
  for (int i = 1; i <= ref.length; i++) {
    final List<int> current = List<int>.filled(hyp.length + 1, 0);
    current[0] = i;
    for (int j = 1; j <= hyp.length; j++) {
      final int substitute =
          previous[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1);
      current[j] = math.min(
        substitute,
        math.min(previous[j] + 1, current[j - 1] + 1),
      );
    }
    previous = current;
  }
  return previous[hyp.length];
}

double _wer(String ref, String hyp) {
  final List<String> r = werTokens(ref);
  final List<String> h = werTokens(hyp);
  if (r.isEmpty) return h.isEmpty ? 0 : 1;
  return _editDistance(r, h) / r.length;
}

/// The scorer checks itself before it scores anything: a normaliser that
/// stopped folding "3 PM" into "three pm" would silently inflate every WER.
void _checkScorer() {
  void same(String a, String b) => expect(
    werTokens(a),
    werTokens(b),
    reason: 'WER normalisation must fold "$a" and "$b" together',
  );
  same('3 PM', '3 p.m.');
  same('3 PM', 'three pm');
  same('3pm', 'Three P.M.');
  same('at 3:30 p.m.', 'at three thirty PM');
  same('7:05 a.m.', 'seven oh five am');
  same('at 3:00', "at three o'clock");
  same('Call Anna at 7:40 pm.', 'Call Anna at 740 p.m.');
  same('Call Anna at 7:40 pm.', 'Call Anna at 7.40 pm.');
  same('at 11:30 AM', 'at 1130 a.m.');
  same('at 7:00 pm', 'at 7.00 p.m.');
  same('on the 21st', 'on the twenty-first');
  same('Call Mom, then buy milk!', 'call mom then buy milk');
  same('twenty five', '25');
  same(r'$20', 'twenty dollars');
  same('in 2026', 'in two thousand twenty six');
  expect(werTokens('3 PM'), <String>['3', 'pm']);
  expect(_wer('Call mom at 3 PM', 'call Mom at three p.m.'), 0);
  expect(_wer('a b c d', 'a x c'), 0.5, reason: 'one substitution, one miss');
  expect(_wer('a b', 'a b c d'), 1, reason: 'two insertions over two words');
}

// ─── results ───────────────────────────────────────────────────────────────

final class _Result {
  _Result(this.clip);

  final _Clip clip;

  /// An infrastructure error: the clip was not measured.
  String? error;
  String transcript = '';
  bool noSpeech = false;
  int ms = 0;
  int? stopMs;
  int audioMs = 0;
  int partials = 0;
  List<String> refTokens = const <String>[];
  List<String> hypTokens = const <String>[];
  int edits = 0;
  double wer = 0;
  List<ExtractedTask> fromAudio = const <ExtractedTask>[];
  List<ExtractedTask> fromText = const <ExtractedTask>[];
  NoteScore? audio;
  NoteScore? text;
  String? extractError;

  bool get measured => error == null;
  bool get exactAudio => audio?.exact ?? false;
  bool get exactText => text?.exact ?? false;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': clip.id,
    'condition': clip.condition,
    'voice': clip.voice,
    'clean_pair': clip.cleanPair,
    'wav': clip.wavPath,
    'now': clip.nowIso,
    'text': clip.text,
    'transcript': measured ? transcript : null,
    'wer': measured ? wer : null,
    'ref_words': measured ? refTokens.length : null,
    'edits': measured ? edits : null,
    'ref_norm': measured ? refTokens.join(' ') : null,
    'hyp_norm': measured ? hypTokens.join(' ') : null,
    'tasks_expected': <Map<String, Object?>>[
      for (final ExpectedTask t in clip.expected)
        <String, Object?>{'title': t.title, 'date': t.date, 'time': t.time},
    ],
    'tasks_from_audio': measured ? _tasksJson(fromAudio) : null,
    'tasks_from_text': measured ? _tasksJson(fromText) : null,
    'exact_audio': measured ? exactAudio : null,
    'exact_text': measured ? exactText : null,
    'problems_audio': audio?.problems,
    'problems_text': text?.problems,
    'ms': ms,
    'stop_ms': stopMs,
    'audio_ms': audioMs,
    'partials': partials,
    'no_speech': noSpeech,
    'extract_error': extractError,
    'error': error,
  };
}

List<Map<String, Object?>> _tasksJson(List<ExtractedTask> tasks) =>
    <Map<String, Object?>>[
      for (final ExtractedTask t in tasks)
        <String, Object?>{
          'title': t.title,
          'date': t.date?.toIso(),
          'time': t.time?.toIso(),
        },
    ];

/// One row of the summary: a condition, a voice, or everything.
final class _Stats {
  /// [key] is the condition or the voice; [name] labels its row.
  _Stats(this.name, this.key, List<_Result> rows)
    : clips = rows.length,
      measured = <_Result>[
        for (final _Result r in rows)
          if (r.measured) r,
      ] {
    errors = clips - measured.length;
    if (measured.isEmpty) return;
    audio = Scorecard(name, <NoteScore>[
      for (final _Result r in measured) r.audio!,
    ]);
    text = Scorecard(name, <NoteScore>[
      for (final _Result r in measured) r.text!,
    ]);
    final int refWords = measured.fold(0, (int a, _Result r) {
      return a + r.refTokens.length;
    });
    final int edits = measured.fold(0, (int a, _Result r) => a + r.edits);
    meanWer =
        measured.fold(0.0, (double a, _Result r) => a + r.wer) /
        measured.length;
    pooledWer = refWords == 0 ? 0 : edits / refWords;
    empty = measured.where((_Result r) => r.noSpeech).length;
    lost = measured.where((_Result r) => r.exactText && !r.exactAudio).length;
    gained = measured.where((_Result r) => r.exactAudio && !r.exactText).length;
    long = measured.where((_Result r) => r.audioMs > _commitMs).length;
    final List<int> ms = <int>[for (final _Result r in measured) r.ms]..sort();
    p50 = _percentile(ms, 50);
    p95 = _percentile(ms, 95);
    final List<int> stop = <int>[
      for (final _Result r in measured)
        if (r.stopMs != null) r.stopMs!,
    ]..sort();
    if (stop.isNotEmpty) {
      stopP50 = _percentile(stop, 50);
      stopP95 = _percentile(stop, 95);
    }
  }

  final String name;
  final String key;
  final int clips;
  final List<_Result> measured;
  int errors = 0;
  Scorecard? audio;
  Scorecard? text;
  double meanWer = 0;
  double pooledWer = 0;
  int empty = 0;
  int lost = 0;
  int gained = 0;
  int long = 0;
  int p50 = 0;
  int p95 = 0;
  int? stopP50;
  int? stopP95;

  Map<String, Object?> toJson() => <String, Object?>{
    'clips': clips,
    'measured': measured.length,
    'errors': errors,
    if (audio != null && text != null) ...<String, Object?>{
      'mean_wer': meanWer,
      'pooled_wer': pooledWer,
      'no_speech': empty,
      'exact_audio': audio!.exactRate,
      'exact_text': text!.exactRate,
      'lost_to_asr': lost,
      'gained_from_asr': gained,
      'recall_audio': audio!.recall,
      'precision_audio': audio!.precision,
      'date_accuracy_audio': audio!.dateAccuracy,
      'time_accuracy_audio': audio!.timeAccuracy,
      'recall_text': text!.recall,
      'precision_text': text!.precision,
      'date_accuracy_text': text!.dateAccuracy,
      'time_accuracy_text': text!.timeAccuracy,
      'ms_p50': p50,
      'ms_p95': p95,
      'stop_ms_p50': stopP50,
      'stop_ms_p95': stopP95,
      'clips_over_25s': long,
    },
  };

  List<String> row() {
    final Scorecard? a = audio;
    final Scorecard? t = text;
    if (a == null || t == null) {
      return <String>[
        name,
        '$clips',
        '$errors',
        ...List<String>.filled(14, '-'),
      ];
    }
    return <String>[
      name,
      '$clips',
      '$errors',
      '$empty',
      _pct(meanWer),
      _pct(pooledWer),
      _pct(a.exactRate),
      _pct(t.exactRate),
      '$lost',
      _pct(a.recall),
      _pct(a.precision),
      _pct(a.dateAccuracy),
      _pct(a.timeAccuracy),
      _pct(t.dateAccuracy),
      _pct(t.timeAccuracy),
      '$p50',
      '$p95',
    ];
  }

  static const List<String> header = <String>[
    'group',
    'clips',
    'err',
    'empty',
    'WER',
    'WERpool',
    'exact A',
    'exact T',
    'lost',
    'recall A',
    'prec A',
    'date A',
    'time A',
    'date T',
    'time T',
    'p50 ms',
    'p95 ms',
  ];
}

int _percentile(List<int> sorted, int p) {
  if (sorted.isEmpty) return 0;
  final int rank = (p / 100 * sorted.length).ceil();
  return sorted[(rank - 1).clamp(0, sorted.length - 1)];
}

String _pct(double x) => '${(x * 100).toStringAsFixed(1)}%';

typedef _Summary = ({
  _Stats all,
  List<_Stats> conditions,
  _Stats? cleanPaired,
  List<_Stats> voices,
  List<_Result> worst,
});

_Summary _report(List<_Result> results) {
  List<_Stats> by(String prefix, String Function(_Clip) key) {
    final Map<String, List<_Result>> groups = <String, List<_Result>>{};
    for (final _Result r in results) {
      groups.putIfAbsent(key(r.clip), () => <_Result>[]).add(r);
    }
    // In manifest order: clean, fast, slow, white20, ... as generated.
    return <_Stats>[
      for (final MapEntry<String, List<_Result>> g in groups.entries)
        _Stats('$prefix${g.key}', g.key, g.value),
    ];
  }

  final _Stats all = _Stats('all', 'all', results);
  final List<_Stats> conditions = by('condition:', (_Clip c) => c.condition);
  final List<_Stats> voices = by('voice:', (_Clip c) => c.voice);

  // The clean clips that are some degraded clip's twin (same case, same
  // voice): the baseline each degraded condition is compared with. Every
  // generated degraded condition covers the same subset, so this one row
  // serves all of them.
  final Set<String> pairIds = <String>{
    for (final _Result r in results)
      if (r.clip.cleanPair != null) r.clip.cleanPair!,
  };
  final List<_Result> pairRows = <_Result>[
    for (final _Result r in results)
      if (pairIds.contains(r.clip.id)) r,
  ];
  final _Stats? cleanPaired = pairRows.isEmpty
      ? null
      : _Stats('condition:clean (paired)', 'clean_paired', pairRows);

  _say('\n══ summary ══');
  _say(
    'A = tasks extracted from the audio transcript, T = from the reference '
    'text. lost = right from the text, wrong from the audio (the ASR broke '
    'it). empty = whisper heard no speech. WER is the mean over clips; '
    'WERpool is all edits over all reference words.',
  );
  _say(
    _table(<List<String>>[
      _Stats.header,
      all.row(),
      for (final _Stats s in conditions) s.row(),
      ?cleanPaired?.row(),
      for (final _Stats s in voices) s.row(),
    ]),
  );
  if (cleanPaired != null) {
    _say(
      'clean (paired) = the ${cleanPaired.clips} clean clip(s) with the same '
      'case and voice as the degraded clips: their baseline.',
    );
  }
  if (all.stopP50 != null) {
    _say(
      'end of audio -> transcript: p50 ${all.stopP50} ms, '
      'p95 ${all.stopP95} ms',
    );
  }
  if (all.long > 0) {
    _say(
      '⚠️ ${all.long} clip(s) run past 25 s, where the native window commits '
      'text mid-way; fed faster than real time they may not decode as on a '
      'phone (TASUKE_ASR_REALTIME=1).',
    );
  }

  final List<_Result> worst = (<_Result>[
    for (final _Result r in results)
      if (r.measured) r,
  ]..sort(_worstFirst)).take(_worstShown).toList();
  if (worst.isNotEmpty) {
    _say('\n══ worst ${worst.length} clips ══');
    for (int i = 0; i < worst.length; i++) {
      _say(_describe(i + 1, worst[i]));
    }
  }

  final List<_Result> crashed = <_Result>[
    for (final _Result r in results)
      if (r.extractError != null) r,
  ];
  if (crashed.isNotEmpty) {
    _say('\n══ the extractor threw on ${crashed.length} clip(s) ══');
    for (final _Result r in crashed) {
      _say('  ${r.clip.id}: ${r.extractError}');
    }
  }

  final List<_Result> broken = <_Result>[
    for (final _Result r in results)
      if (!r.measured) r,
  ];
  if (broken.isNotEmpty) {
    _say('\n══ ${broken.length} clip(s) not measured ══');
    for (final _Result r in broken) {
      _say('  ${r.clip.id}: ${r.error}');
    }
  }

  return (
    all: all,
    conditions: conditions,
    cleanPaired: cleanPaired,
    voices: voices,
    worst: worst,
  );
}

/// Tasks the ASR broke first (right from the text, wrong from the audio),
/// then notes wrong either way, then clips whose tasks survived; worst WER
/// first within each.
int _worstFirst(_Result a, _Result b) {
  int rank(_Result r) => !r.exactAudio ? (r.exactText ? 0 : 1) : 2;
  final int byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  final int byWer = b.wer.compareTo(a.wer);
  if (byWer != 0) return byWer;
  return a.clip.id.compareTo(b.clip.id);
}

String _describe(int n, _Result r) {
  final String verdict = !r.exactAudio
      ? (r.exactText
            ? 'ASR broke it (text ✓, audio ✗)'
            : 'wrong from text and from audio')
      : (r.exactText ? 'tasks right' : 'right from audio only');
  final StringBuffer b = StringBuffer()
    ..writeln(
      '${'$n'.padLeft(2)}. ${r.clip.id}  [${r.clip.condition} / '
      '${r.clip.voice}]  WER ${_pct(r.wer)}  ${r.ms} ms  — $verdict',
    )
    ..writeln('    ref  : ${r.clip.text}')
    ..writeln('    heard: ${r.noSpeech ? '(no speech)' : r.transcript}');
  if (r.wer > 0) {
    b.writeln('    norm : ${r.refTokens.join(' ')}');
    b.writeln('         → ${r.hypTokens.join(' ')}');
  }
  b
    ..writeln('    want : ${_expectedText(r.clip.expected)}')
    ..writeln('    audio: ${_tasksText(r.fromAudio)}')
    ..writeln('    text : ${_tasksText(r.fromText)}');
  final List<String> audioProblems = r.audio?.problems ?? const <String>[];
  final List<String> textProblems = r.text?.problems ?? const <String>[];
  if (audioProblems.isNotEmpty) {
    b.writeln('    why A: ${audioProblems.join('; ')}');
  }
  if (textProblems.isNotEmpty) {
    b.writeln('    why T: ${textProblems.join('; ')}');
  }
  return b.toString().trimRight();
}

String _expectedText(List<ExpectedTask> tasks) => tasks.isEmpty
    ? '(none)'
    : tasks
          .map(
            (ExpectedTask t) =>
                '"${t.title}" ${t.date ?? '-'} ${t.time ?? '-'}',
          )
          .join(' | ');

String _tasksText(List<ExtractedTask> tasks) => tasks.isEmpty
    ? '(none)'
    : tasks
          .map(
            (ExtractedTask t) =>
                '"${t.title}" ${t.date?.toIso() ?? '-'} ${t.time?.toIso() ?? '-'}',
          )
          .join(' | ');

String _progressLine(int i, int total, _Result r) {
  final String counter = '[${'$i'.padLeft('$total'.length)}/$total]';
  final String where = '${r.clip.id} (${r.clip.condition}, ${r.clip.voice})';
  if (!r.measured) return '$counter $where  ERROR ${r.error}';
  return '$counter $where  WER ${_pct(r.wer).padLeft(6)}  '
      'exact audio ${r.exactAudio ? '✓' : '✗'} text ${r.exactText ? '✓' : '✗'}'
      '  ${r.ms} ms${r.noSpeech ? '  (no speech)' : ''}';
}

String _table(List<List<String>> rows) {
  final int columns = rows.first.length;
  final List<int> widths = List<int>.generate(
    columns,
    (int c) => rows.fold(0, (int w, List<String> row) {
      return math.max(w, row[c].length);
    }),
  );
  return rows
      .map(
        (List<String> row) => <String>[
          for (int c = 0; c < columns; c++)
            c == 0 ? row[c].padRight(widths[c]) : row[c].padLeft(widths[c]),
        ].join('  '),
      )
      .join('\n');
}

void _say(String message) {
  // ignore: avoid_print — the report is the point of this test.
  print(message);
}
