import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/capture/waveform_view.dart';

/// `mm:ss`, driven by a [Listenable] for the same reason [WaveformView] is.
class RecordingTimer extends StatelessWidget {
  const RecordingTimer({
    required this.elapsed,
    required this.valueOf,
    super.key,
  });

  final Listenable elapsed;
  final Duration Function() valueOf;

  /// Never `intl`'s formatter: this is a stopwatch, not a time of day, and
  /// `Duration.toString()` prints microseconds.
  static String format(Duration value) {
    final int total = value.isNegative ? 0 : value.inSeconds;
    final String minutes = (total ~/ 60).toString().padLeft(2, '0');
    final String seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: elapsed,
      builder: (BuildContext context, Widget? child) {
        // Tabular figures come from TasukeTypography.timer — without them the
        // counter changes its own width once a second under a centred layout.
        return Text(format(valueOf()), style: TasukeTypography.timer);
      },
    );
  }
}
