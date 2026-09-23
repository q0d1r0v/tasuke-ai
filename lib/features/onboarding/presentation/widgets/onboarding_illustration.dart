import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

/// The art above each onboarding headline.
///
/// ⚠️ A drawn illustration, not a Material glyph on a blob.
///
/// The first version laid `Icons.mic_none_rounded` in the brand blue straight
/// onto the blurred brand orb — blue on blue. On a real phone the glyph was
/// invisible and all three pages read as the same decorative smudge; that is
/// what the shipped screenshots showed. Each page now carries its own picture,
/// and the picture is what tells the three pages apart.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({required this.asset, super.key});

  /// One of [TasukeArt]'s `guide*` pictures.
  final String asset;

  /// Sized to leave the headline and body most of a small phone. The page
  /// still scrolls when the copy outgrows it (320 × 568, or large type).
  static const double artSize = 216;

  /// Fixed, so the headline sits on the same baseline on all three pages and
  /// swiping between them does not make the text jump.
  static const double slotHeight = 230;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: slotHeight,
      width: double.infinity,
      child: Center(
        child: SvgIllustration(asset: asset, size: artSize),
      ),
    );
  }
}
