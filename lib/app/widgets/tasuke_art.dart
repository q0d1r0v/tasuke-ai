import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Every vector illustration the app ships, by name.
///
/// Screens name a member here rather than a string literal, for the same reason
/// they never write `Text('Save')`: a mistyped asset path is not a compile
/// error, it is an "Unable to load asset" exception on one screen of one build,
/// and `asset_manifest_test.dart` can only check paths it can enumerate.
abstract final class TasukeArt {
  /// Onboarding page 1 — a microphone ringed by a waveform.
  static const String guideVoice = 'assets/images/guide_voice.svg';

  /// Onboarding page 2 — three task cards with ticked checks.
  static const String guideTasks = 'assets/images/guide_tasks.svg';

  /// Onboarding page 3 — a shield with a padlock.
  static const String guidePrivacy = 'assets/images/guide_privacy.svg';

  /// Frames of the breathing blob, in loop order.
  ///
  /// Hand-drawn frames rather than a Dart-side morph: the blob's outline, its
  /// inner core and its specular highlight all move independently between
  /// frames, and interpolating three of those in code produces a wobble, not a
  /// breath.
  ///
  /// ⚠️ Both artboards this app has been given ship a closing frame that is
  /// byte-identical to the opening one — the loop supplies that for free by
  /// wrapping — so the duplicate is dropped on the way in. Animating it held
  /// one image for an extra beat once per cycle, and that hitch is what made
  /// the breathing read as broken rather than as slow.
  /// `art_test.dart` fails if two frames are ever identical again.
  static const int blobFrameCount = 8;

  static String blobFrame(int index) {
    assert(
      index >= 0 && index < blobFrameCount,
      'frame $index is out of range',
    );
    final String number = (index + 1).toString().padLeft(2, '0');
    return 'assets/images/blob/blob_frame_$number.svg';
  }

  /// Every asset above, for the manifest test.
  static List<String> get all => <String>[
    guideVoice,
    guideTasks,
    guidePrivacy,
    for (int i = 0; i < blobFrameCount; i++) blobFrame(i),
  ];
}

/// One of [TasukeArt]'s pictures, sized and inert.
///
/// ⚠️ Decoration, so it is excluded from semantics and takes no taps. The
/// headline underneath each illustration already says what the page is about;
/// a screen reader that also announces "image" here reads the page twice.
class SvgIllustration extends StatelessWidget {
  const SvgIllustration({required this.asset, required this.size, super.key});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        // ⚠️ The SizedBox, not just `SvgPicture`'s own width/height. A picture
        // that has not parsed yet renders its placeholder and takes whatever
        // space is going, so without this the headline below jumps upward on
        // the first frame of every onboarding page and settles a frame later.
        child: SizedBox.square(
          dimension: size,
          child: SvgPicture.asset(
            asset,
            fit: BoxFit.contain,
            // The art is square and already carries its own padding; letting
            // it grow with the text scale would push the headline off the page.
            //
            // ⚠️ No `colorFilter`. Every illustration is multi-colour by
            // design, and a filter would flatten the gradients to one tint.
          ),
        ),
      ),
    );
  }
}
