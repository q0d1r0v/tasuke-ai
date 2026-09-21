import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/audio/record_audio_recorder.dart';

/// PCM16 little-endian bytes for [samples].
Uint8List pcm(List<int> samples) {
  final ByteData data = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  // There is no microphone on a CI box and `record` is a MethodChannel, so what
  // is testable here is the arithmetic and the format contract — which is also
  // where the two real traps live.

  group('the capture format', () {
    test('is whisper.cpp native: 16 kHz, mono, PCM16', () {
      // ⚠️ A 44.1 kHz stereo capture does not fail. It resamples badly inside
      // the binding and halves transcription quality, and nobody debugging
      // "the model got worse" looks at the recorder.
      expect(kTasukeRecordConfig.sampleRate, 16000);
      expect(kTasukeRecordConfig.numChannels, 1);
      expect(kTasukeRecordConfig.encoder.name, 'pcm16bits');
    });
  });

  group('rmsOf', () {
    test('silence is zero', () {
      expect(RecordAudioRecorder.rmsOf(pcm(<int>[0, 0, 0, 0])), 0);
    });

    test('an empty chunk is zero, not a division by zero', () {
      expect(RecordAudioRecorder.rmsOf(Uint8List(0)), 0);
    });

    test('a constant half-scale signal reads 0.5', () {
      expect(
        RecordAudioRecorder.rmsOf(pcm(<int>[16384, 16384, 16384, 16384])),
        closeTo(0.5, 1e-9),
      );
    });

    test('full scale saturates at 1.0 rather than overshooting', () {
      expect(
        RecordAudioRecorder.rmsOf(pcm(<int>[-32768, -32768])),
        closeTo(1.0, 1e-9),
      );
    });

    test('a symmetric signal is measured by power, not by mean', () {
      // +8192 and -8192 average to zero. RMS is what makes the waveform move.
      expect(
        RecordAudioRecorder.rmsOf(pcm(<int>[8192, -8192, 8192, -8192])),
        closeTo(0.25, 1e-9),
      );
    });

    test('an odd trailing byte is dropped, not misread', () {
      final Uint8List odd = Uint8List.fromList(<int>[0x00, 0x40, 0x7F]);
      expect(RecordAudioRecorder.rmsOf(odd), closeTo(0.5, 1e-9));
    });

    test('a chunk at an odd byte offset still decodes in phase', () {
      // ⚠️ The trap. `bytes.buffer.asInt16List()` on a view whose
      // `offsetInBytes` is odd either throws or reads every sample one byte out
      // of phase — which looks like plausible noise, not like a bug. Platform
      // chunks really do arrive at odd offsets.
      final Uint8List backing = Uint8List.fromList(<int>[
        0xFF,
        0x00,
        0x40,
        0x00,
        0x40,
      ]);
      final Uint8List view = Uint8List.sublistView(backing, 1);

      expect(view.offsetInBytes.isOdd, isTrue);
      expect(RecordAudioRecorder.rmsOf(view), closeTo(0.5, 1e-9));
    });

    test('is bounded to 0..1 for any input', () {
      for (final int sample in <int>[-32768, -1, 0, 1, 32767]) {
        final double level = RecordAudioRecorder.rmsOf(pcm(<int>[sample]));
        expect(level, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
