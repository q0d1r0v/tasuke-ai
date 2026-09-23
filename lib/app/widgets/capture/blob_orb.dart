import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/tasuke_art.dart';

/// The breathing blob: [TasukeArt.blobFrameCount] vector frames cross-faded on
/// a loop.
///
/// Used wherever the app is working and has nothing precise to report — the
/// processing screen. It replaces a blurred circle, which on a real phone read
/// as a smudge rather than as motion.
///
/// ⚠️ It animates forever, so a test that reaches it must never call
/// `pumpAndSettle` — the same rule the waveform already imposes. `pumpSettled`
/// in test/helpers pumps a fixed number of frames for exactly this reason.
class BlobOrb extends StatefulWidget {
  const BlobOrb({this.size = 180, super.key});

  final double size;

  @override
  State<BlobOrb> createState() => _BlobOrbState();
}

class _BlobOrbState extends State<BlobOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TasukeDurations.blobCycle,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_warmCache());
  }

  /// Pulls all eight frames into flutter_svg's cache before the loop needs
  /// them.
  ///
  /// Without this, the first cycle fades *into a frame that has not parsed
  /// yet*: `SvgPicture` renders nothing until its bytes arrive, so the orb
  /// blinks once per frame for the first two seconds of the screen that is
  /// supposed to reassure the user that work is happening.
  ///
  /// Failures are swallowed on purpose. A missing frame degrades to a shorter
  /// loop; it must never take down the processing screen, which the user
  /// cannot back out of while a capture is being read.
  Future<void> _warmCache() async {
    for (int i = 0; i < TasukeArt.blobFrameCount; i++) {
      try {
        await SvgAssetLoader(TasukeArt.blobFrame(i)).loadBytes(null);
      } on Object {
        // Intentionally ignored — see above.
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour "reduce motion". A looping blob is precisely the kind of ambient
    // movement that setting exists to stop, and the screens that host it stay
    // legible frozen on frame one.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, _) {
              final double position =
                  _controller.value * TasukeArt.blobFrameCount;
              final int current = position.floor() % TasukeArt.blobFrameCount;
              final int next = (current + 1) % TasukeArt.blobFrameCount;
              final double blend = position - position.floorToDouble();

              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Only ever two layers, never eight. Each visible layer with
                  // a fractional opacity costs a saveLayer, and the outgoing
                  // frame is the only one that ever has one.
                  _Frame(index: current, opacity: 1),
                  _Frame(index: next, opacity: blend),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.index, required this.opacity});

  final int index;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();

    final Widget picture = SvgPicture.asset(
      TasukeArt.blobFrame(index),
      fit: BoxFit.contain,
    );
    return opacity >= 1 ? picture : Opacity(opacity: opacity, child: picture);
  }
}
