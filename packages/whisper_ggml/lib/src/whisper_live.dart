import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:universal_io/io.dart';

/// Native streaming bindings.
typedef _StreamStartNative = Pointer<Utf8> Function(Pointer<Utf8> body);
typedef _StreamFeedNative = Pointer<Utf8> Function(
  Pointer<Float> pcm,
  Int32 nSamples,
);
typedef _StreamFeedDart = Pointer<Utf8> Function(Pointer<Float> pcm, int n);
typedef _StreamStopNative = Pointer<Utf8> Function();

/// A running live transcription session.
///
/// Obtain one from `WhisperController.transcribeLive` or
/// [startWhisperLiveSession]. Listen to [partials] for progressively refined
/// transcripts while audio is being fed, and call [stop] to get the final
/// text and release the native context.
class WhisperLiveSession {
  WhisperLiveSession._(this._worker, this._toWorker, this._partials);

  final Isolate _worker;
  final SendPort _toWorker;
  final StreamController<String> _partials;
  final Completer<String> _final = Completer<String>();
  bool _stopped = false;

  /// Audio captured but not yet handed to the worker.
  ///
  /// ⚠️ This buffer is the whole point, and its absence was a hang.
  ///
  /// `feed` used to post every chunk straight into the worker's mailbox. A
  /// recorder delivers roughly every 128 ms; on any device where the model
  /// decodes slower than real time — which is most phones past a few seconds
  /// of speech — inference falls behind and the mailbox grows without bound.
  /// A 45-second recording queues ~350 messages, and `['stop']` goes in behind
  /// every one of them, so the final transcript cannot even begin until the
  /// backlog drains. The user taps Stop and nothing happens, for minutes,
  /// while the partial text sits frozen on a transcript from half a minute
  /// ago.
  ///
  /// Coalescing instead of queueing fixes both halves: the mailbox never holds
  /// more than one feed, so Stop is at most one inference away, and the
  /// decoder gets one large contiguous chunk per pass instead of a hundred
  /// tiny ones — which is also the better input for it.
  final BytesBuilder _pending = BytesBuilder(copy: false);

  /// Whether a feed is with the worker right now, awaiting its ack.
  bool _feedInFlight = false;

  /// Progressively refined transcripts of the audio fed so far. Each event
  /// replaces the previous one (it is the full text, not a delta).
  Stream<String> get partials => _partials.stream;

  /// Feed 16 kHz mono PCM16 (little-endian) audio bytes.
  void feed(Uint8List pcm16Bytes) {
    if (_stopped) return;
    _pending.add(pcm16Bytes);
    _flush();
  }

  void _flush() {
    if (_feedInFlight || _pending.isEmpty) return;
    _feedInFlight = true;
    _toWorker.send(['feed', _pending.takeBytes()]);
  }

  /// The worker finished a chunk and is ready for the next.
  void _onAck() {
    _feedInFlight = false;
    if (!_stopped) _flush();
  }

  /// Finish the session: transcribe any remaining audio, release the native
  /// context, and return the final transcript.
  Future<String> stop() {
    if (!_stopped) {
      // ⚠️ Hand over the remainder. Whatever is still buffered is audio the
      // user actually spoke, and `stream_stop` only decodes what the native
      // window has been given. Dropping it truncates the transcript at
      // whatever the decoder happened to have reached.
      //
      // It rides on 'stop' rather than going as a 'feed': a feed can start a
      // preview over the whole window, and the final pass overwrites that text
      // anyway. The mailbox is at most [feed?, stop].
      _stopped = true;
      _toWorker.send(<Object>[
        'stop',
        if (_pending.isNotEmpty) _pending.takeBytes(),
      ]);
    }
    return _final.future;
  }

  /// End the session without transcribing: the native context is handed back
  /// as [stop] would, but the final pass is skipped. For a cancel, whose text
  /// nobody reads. Completes with the last partial; after [stop], it is the
  /// same future as [stop]'s.
  Future<String> abort() {
    if (!_stopped) {
      _stopped = true;
      _pending.clear();
      _toWorker.send(const ['abort']);
    }
    return _final.future;
  }
}

/// Start a live transcription session against the ggml model file at
/// [modelPath].
///
/// This is the low-level entry point behind
/// `WhisperController.transcribeLive`: it accepts any local model file and
/// leaves audio delivery to the caller — feed 16 kHz mono little-endian
/// PCM16 audio with [WhisperLiveSession.feed] and finish with
/// [WhisperLiveSession.stop]. A worker isolate owns the native stream, so
/// inference never blocks the calling isolate. Only one live session can
/// run at a time.
///
/// The `gate*` parameters tune the native energy gate that keeps silence
/// away from the decoder; see `WhisperController.transcribeLive` for
/// details.
///
/// [keepModelLoaded] parks the session's model in native memory on
/// [WhisperLiveSession.stop] instead of freeing it, so the next session
/// (or one-shot transcription) with the same model file skips the
/// multi-second load — see `TranscribeRequest.keepModelLoaded` for the
/// memory trade-off. A session also borrows an already-parked model
/// automatically when the path matches, and returns it on stop.
///
/// [initialPrompt] primes every pass, previews included. With
/// [promptOnPreviews] false it primes only the passes whose text is final —
/// the pass [WhisperLiveSession.stop] runs, and the one that commits a
/// 25-second window — which keeps the prompt's cost off the previews.
Future<WhisperLiveSession> startWhisperLiveSession({
  required String modelPath,
  String lang = 'en',
  bool translate = false,
  String? initialPrompt,
  bool suppressNonSpeechTokens = false,
  bool keepModelLoaded = false,
  int threads = 4,
  double gateRmsMin = 0.0015,
  double gateVoiceRatio = 2.5,
  double gateNoiseFloorCap = 0.01,
  bool promptOnPreviews = true,
}) async {
  final ReceivePort fromWorker = ReceivePort();
  // ⚠️ The VM's own channels, kept apart from [fromWorker].
  //
  // Without them, an isolate that dies before it sends 'ready' — a missing
  // libwhisper.so on some ABI, a lookupFunction that finds no symbol, an
  // uncaught throw while decoding — simply stops existing, and the
  // `await ready.future` below waits for a message that can no longer come.
  // Nothing upstream has a timeout, so Stop becomes a spinner that never ends
  // and the user's recording is lost with no way out but killing the app.
  //
  // They are separate ports because the VM's message shape is `[error, stack]`
  // and this protocol's is `[tag, ...]`; funnelled through the same listener,
  // a crash would be read as an unknown tag and swallowed.
  final ReceivePort crash = ReceivePort();
  final ReceivePort exited = ReceivePort();
  final Isolate worker = await Isolate.spawn(
    _liveWorker,
    fromWorker.sendPort,
    onError: crash.sendPort,
    onExit: exited.sendPort,
    debugName: 'whisper-live',
  );

  final StreamController<String> partials = StreamController<String>();
  final Completer<SendPort> ready = Completer<SendPort>();
  final Completer<void> started = Completer<void>();
  late final WhisperLiveSession session;

  String lastText = '';

  /// Set once the session has ended for any reason, so a normal stop's
  /// `onExit` is not mistaken for a crash.
  bool done = false;

  void closePorts() {
    crash.close();
    exited.close();
    fromWorker.close();
  }

  /// The single place a dead worker becomes a failed Future.
  ///
  /// The branch order is load-bearing: [session] is `late final` and is only
  /// assigned once [ready] has completed, so the arm that touches it is
  /// guarded behind `started.isCompleted`, which cannot be true before then.
  void fail(Object error, [StackTrace? stack]) {
    if (done) return;
    done = true;
    if (!ready.isCompleted) {
      ready.completeError(error, stack);
    } else if (!started.isCompleted) {
      started.completeError(error, stack);
    } else if (!session._final.isCompleted) {
      // Same contract as the 'error' arm below: keep whatever was heard.
      if (!partials.isClosed) {
        partials
          ..addError(error)
          ..close();
      }
      session._final.complete(lastText);
    }
    closePorts();
  }

  crash.listen((dynamic message) {
    final List<dynamic> pair = message as List<dynamic>;
    final String? trace = pair.length > 1 ? pair[1] as String? : null;
    fail(
      Exception('whisper worker crashed: ${pair.first}'),
      trace == null ? null : StackTrace.fromString(trace),
    );
  });
  exited.listen(
    (_) => fail(Exception('whisper worker exited before it finished')),
  );

  fromWorker.listen((dynamic message) {
    final List<dynamic> msg = message as List<dynamic>;
    switch (msg[0] as String) {
      case 'ready':
        ready.complete(msg[1] as SendPort);
      case 'started':
        started.complete();
      case 'ack':
        // The worker is free. `session` exists by now: an ack can only follow
        // a feed, and a feed can only follow `ready`.
        session._onAck();
      case 'partial':
        lastText = msg[1] as String;
        if (!partials.isClosed) partials.add(lastText);
      case 'final':
        done = true;
        if (!partials.isClosed) partials.close();
        session._final.complete(msg[1] as String);
        closePorts();
        session._worker.kill();
      case 'error':
        final error = Exception(msg[1] as String);
        if (!started.isCompleted) {
          // ⚠️ Through fail(), which knows whether 'ready' or 'started' is
          // the one being awaited. A failed native load reports here BEFORE
          // 'ready'; completing `started` then left `ready` pending forever,
          // with the ports that could have failed it already closed.
          fail(error);
        } else if (!session._final.isCompleted) {
          // A mid-session native error is fatal: surface it on [partials],
          // then finalize with the last known text so stop() never hangs.
          done = true;
          if (!partials.isClosed) {
            partials
              ..addError(error)
              ..close();
          }
          session._final.complete(lastText);
          closePorts();
          session._worker.kill();
        }
    }
  });

  final SendPort toWorker;
  try {
    toWorker = await ready.future;
  } on Object {
    worker.kill(priority: Isolate.immediate);
    closePorts();
    // ⚠️ Not awaited, here or below: nothing ever listened to [partials], and
    // close() on a single-subscription controller that was never listened to
    // never completes. Awaited, every native failure hung instead of throwing.
    unawaited(partials.close());
    rethrow;
  }
  session = WhisperLiveSession._(worker, toWorker, partials);

  toWorker.send([
    'start',
    json.encode({
      'model': modelPath,
      'language': lang,
      'is_translate': translate,
      'threads': threads,
      'suppress_non_speech_tokens': suppressNonSpeechTokens,
      'keep_model_loaded': keepModelLoaded,
      'gate_rms_min': gateRmsMin,
      'gate_voice_ratio': gateVoiceRatio,
      'gate_floor_cap': gateNoiseFloorCap,
      'prompt_on_previews': promptOnPreviews,
      if (initialPrompt != null && initialPrompt.isNotEmpty)
        'initial_prompt': initialPrompt,
    }),
  ]);

  try {
    await started.future;
  } catch (_) {
    worker.kill(priority: Isolate.immediate);
    closePorts();
    unawaited(partials.close());
    rethrow;
  }
  return session;
}

/// Worker isolate: owns all FFI calls so whisper_full never blocks the UI
/// isolate. Messages arriving while inference runs simply queue in the
/// mailbox; the native side only re-runs inference once enough new audio
/// has accumulated, so queued chunks drain quickly.
///
/// Note: backpressure is bounded only by decode speed. On devices where the
/// model decodes slower than real time, the mailbox and the native window
/// grow and partial latency drifts behind the audio. If that becomes a
/// target, cap the window or surface an "audio seconds behind" metric.
DynamicLibrary _openLib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libwhisper.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('whisper_ggml.dll');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libwhisper_ggml.so');
  } else {
    return DynamicLibrary.process();
  }
}

void _liveWorker(SendPort toMain) {
  final DynamicLibrary lib;
  final _StreamStartNative start;
  final _StreamFeedDart feed;
  final _StreamStopNative stopFn;

  // ⚠️ The library open and the three symbol lookups, inside a try.
  //
  // Each of them throws on a device where the .so for this ABI is missing or
  // has been stripped of an export, and a throw here kills the isolate before
  // 'ready' is ever sent. The main isolate now survives that (see
  // `startWhisperLiveSession`), but reporting it through the protocol's own
  // 'error' tag gives the caller the real message instead of "worker exited".
  try {
    lib = _openLib();
    start = lib.lookupFunction<_StreamStartNative, _StreamStartNative>(
      'stream_start',
    );
    feed = lib.lookupFunction<_StreamFeedNative, _StreamFeedDart>(
      'stream_feed',
    );
    stopFn = lib.lookupFunction<_StreamStopNative, _StreamStopNative>(
      'stream_stop',
    );
  } on Object catch (error) {
    toMain.send(['error', 'whisper native load failed: $error']);
    return;
  }

  // ⚠️ Optional, each in its own try: both exports are newer than the rest,
  // and a binary built without them must still transcribe exactly as before
  // rather than fail every session at the lookup. Without `stream_append` the
  // Stop tail costs one extra preview; without `stream_abort` a cancel costs
  // the final pass.
  _StreamFeedDart append = feed;
  try {
    append = lib.lookupFunction<_StreamFeedNative, _StreamFeedDart>(
      'stream_append',
    );
  } on Object {
    // Keep the fallback.
  }
  _StreamStopNative abortFn = stopFn;
  try {
    abortFn = lib.lookupFunction<_StreamStopNative, _StreamStopNative>(
      'stream_abort',
    );
  } on Object {
    // Keep the fallback.
  }

  final ReceivePort inbox = ReceivePort();
  toMain.send(['ready', inbox.sendPort]);

  String lastPartial = '';
  int pendingByte = -1; // odd trailing byte carried into the next chunk

  /// PCM16 bytes as a malloc'd float buffer the caller frees, or null when
  /// the chunk holds no whole sample.
  (Pointer<Float>, int)? toFloats(Uint8List chunk) {
    Uint8List bytes = chunk;
    // Normalize the chunk: asInt16List needs an even byte offset, and an
    // odd-length chunk would shift every following sample by one byte
    // (silent corruption), so the trailing byte is carried into the next
    // chunk instead.
    if (pendingByte >= 0 || bytes.offsetInBytes.isOdd || bytes.length.isOdd) {
      final Uint8List merged = Uint8List(
        bytes.length + (pendingByte >= 0 ? 1 : 0),
      );
      int offset = 0;
      if (pendingByte >= 0) merged[offset++] = pendingByte;
      merged.setRange(offset, offset + bytes.length, bytes);
      if (merged.length.isOdd) {
        pendingByte = merged.last;
        bytes = Uint8List.sublistView(merged, 0, merged.length - 1);
      } else {
        pendingByte = -1;
        bytes = merged;
      }
    }
    if (bytes.isEmpty) return null;
    final Int16List samples = bytes.buffer.asInt16List(
      bytes.offsetInBytes,
      bytes.length ~/ 2,
    );
    final Pointer<Float> pcm = malloc.allocate<Float>(
      samples.length * sizeOf<Float>(),
    );
    final Float32List dest = pcm.asTypedList(samples.length);
    for (int i = 0; i < samples.length; i++) {
      dest[i] = samples[i] / 32768.0;
    }
    return (pcm, samples.length);
  }

  Map<String, dynamic> parse(Pointer<Utf8> res) {
    // ⚠️ `toDartString()` on nullptr is a segfault, not an exception — it
    // takes the whole process down, not just this isolate. The native side
    // returns null when its own allocation fails, which is exactly the
    // low-memory moment a 60 MB model makes likely.
    if (res == nullptr) {
      throw StateError('whisper native returned a null response');
    }
    final Map<String, dynamic> result =
        json.decode(res.toDartString()) as Map<String, dynamic>;
    // The native side allocates responses with malloc for exactly this free.
    malloc.free(res);
    return result;
  }

  inbox.listen((dynamic message) {
    // ⚠️ One try around every arm. Anything thrown in here — a malformed
    // response, a null pointer, an allocation that failed — would otherwise
    // terminate the isolate with no message, and the main isolate would be
    // left waiting on a Future that can never complete. The protocol already
    // has a tag that says what happened; use it.
    try {
      final List<dynamic> msg = message as List<dynamic>;
      switch (msg[0] as String) {
        case 'start':
          final Pointer<Utf8> body = (msg[1] as String).toNativeUtf8();
          final Map<String, dynamic> result = parse(start(body));
          malloc.free(body);
          if (result['@type'] == 'error') {
            toMain.send(['error', result['message']]);
          } else {
            toMain.send(const ['started']);
          }
        case 'feed':
          final (Pointer<Float>, int)? pcm = toFloats(msg[1] as Uint8List);
          if (pcm == null) {
            // ⚠️ Still acked. A `return` without one strands the buffer: the
            // main isolate waits for an ack that never comes and no audio is
            // ever fed again.
            toMain.send(const ['ack']);
            return;
          }
          final Map<String, dynamic> result = parse(feed(pcm.$1, pcm.$2));
          malloc.free(pcm.$1);
          if (result['@type'] == 'error') {
            toMain.send(['error', result['message']]);
          } else {
            final String text = result['text'] as String? ?? '';
            if (text != lastPartial) {
              lastPartial = text;
              toMain.send(['partial', text]);
            }
          }
          // ⚠️ Always, and after the work — this is the backpressure signal.
          // The main isolate holds the next chunk until it arrives, which is
          // what keeps `['stop']` from queueing behind a backlog.
          toMain.send(const ['ack']);
        case 'stop':
          // The audio still buffered at Stop, appended without a preview: the
          // full pass below decodes it anyway.
          final (Pointer<Float>, int)? tail = msg.length > 1
              ? toFloats(msg[1] as Uint8List)
              : null;
          if (tail != null) {
            try {
              parse(append(tail.$1, tail.$2));
            } on Object {
              // Not fatal: stream_stop still decodes what the window holds,
              // and it is the call that hands the context back.
            } finally {
              malloc.free(tail.$1);
            }
          }
          final Map<String, dynamic> result = parse(stopFn());
          toMain.send([
            'final',
            result['@type'] == 'error' ? lastPartial : result['text'] as String,
          ]);
          inbox.close();
        case 'abort':
          // Hands the context back like 'stop', minus the final pass.
          parse(abortFn());
          toMain.send(['final', lastPartial]);
          inbox.close();
      }
    } on Object catch (error) {
      toMain.send(['error', '$error']);
    }
  });
}
