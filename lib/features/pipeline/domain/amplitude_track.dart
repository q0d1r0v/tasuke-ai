import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The waveform's data source.
///
/// A [ChangeNotifier] rather than a provider on purpose: the Recording screen
/// repaints its waveform about twenty times a second, and routing that through
/// Riverpod would rebuild the whole subtree at the same rate. A `CustomPainter`
/// listening to this repaints one layer inside a `RepaintBoundary` instead.
final class AmplitudeTrack extends ChangeNotifier {
  AmplitudeTrack({this.barCount = 32});

  final int barCount;

  final List<double> _samples = <double>[];

  double _level = 0;

  /// The most recent RMS level, 0..1.
  double get level => _level;

  /// The trailing window, oldest first, padded to [barCount] with zeros so the
  /// painter never has to special-case a short list.
  List<double> get samples {
    if (_samples.length >= barCount) {
      return _samples.sublist(_samples.length - barCount);
    }
    return <double>[
      ...List<double>.filled(barCount - _samples.length, 0),
      ..._samples,
    ];
  }

  /// Folds one PCM16 chunk into an RMS level.
  ///
  /// The scale factor and the floor are tuned so ordinary speech fills most of
  /// the bar height: a raw RMS over 32768 barely moves for a person talking at
  /// arm's length, and a waveform that never moves reads as a broken microphone.
  /// ⚠️ Read through [ByteData.sublistView] and `getInt16`, never
  /// `buffer.asInt16List()`: a chunk handed over by the platform can start at
  /// an odd `offsetInBytes`, and `asInt16List` at an odd offset throws. The
  /// throw would land inside the recorder's stream listener, where it takes the
  /// waveform down and drops the chunk on its way to the recogniser — audio the
  /// user will never get back. `RecordAudioRecorder.rmsOf` carries the same
  /// warning for the same reason. An odd trailing byte is dropped; it is half a
  /// sample at 16 kHz.
  void addChunk(Uint8List chunk) {
    final int count = chunk.lengthInBytes ~/ 2;
    if (count == 0) return;
    final ByteData view = ByteData.sublistView(chunk, 0, count * 2);
    double sum = 0;
    for (int i = 0; i < count; i++) {
      final double normalised = view.getInt16(i * 2, Endian.little) / 32768.0;
      sum += normalised * normalised;
    }
    final double rms = math.sqrt(sum / count);
    addLevel(rms);
  }

  void addLevel(double rms) {
    // Perceptual, not linear: speech spends most of its energy in the bottom
    // fifth of the linear range, so a linear bar looks flat.
    final double shaped = math.pow(rms.clamp(0.0, 1.0), 0.45).toDouble();
    final double scaled = (shaped * 1.6).clamp(0.0, 1.0);
    _level = scaled;
    _samples.add(scaled);
    if (_samples.length > barCount * 4) {
      _samples.removeRange(0, _samples.length - barCount);
    }
    notifyListeners();
  }

  void reset() {
    _samples.clear();
    _level = 0;
    notifyListeners();
  }
}

/// The recording timer, for the same reason as [AmplitudeTrack]: a `mm:ss`
/// label that ticks once a second should not rebuild a screen.
final class ElapsedTrack extends ChangeNotifier {
  Duration _value = Duration.zero;

  Duration get value => _value;

  set value(Duration next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  void reset() {
    _value = Duration.zero;
    notifyListeners();
  }
}
