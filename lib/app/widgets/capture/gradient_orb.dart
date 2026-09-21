import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_gradients.dart';

/// The soft brand-coloured blob behind the onboarding and processing art.
///
/// Blurred with [ImageFiltered] rather than a `BackdropFilter`: a backdrop
/// filter samples everything painted beneath it, which on a scrolling screen
/// means re-reading the layer every frame.
class GradientOrb extends StatelessWidget {
  const GradientOrb({this.size = 180, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Decoration only: it never takes a tap from the content above it and it
    // has nothing to announce.
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: size * 0.16,
            sigmaY: size * 0.16,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: TasukeGradients.brand,
            ),
          ),
        ),
      ),
    );
  }
}
