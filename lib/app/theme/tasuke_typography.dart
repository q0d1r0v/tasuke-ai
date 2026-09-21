import 'package:flutter/painting.dart';

import 'tasuke_colors.dart';

/// The type scale, measured off the design sheet frame by frame.
///
/// One family, one axis. Every style sets **both** `fontWeight` and
/// `fontVariations`, and they are not redundant: `fontVariations` is what the
/// renderer cuts Inter at, while `fontWeight` is what the platform fallback
/// family is matched on and what a `TextStyle` lerp reads. Leaving `fontWeight`
/// at its default makes every fallback glyph — emoji, CJK — render regular.
abstract final class TasukeTypography {
  static const String family = 'Inter';

  /// The design's body weight, as a `wght` axis value.
  ///
  /// Not a [FontWeight]: that type is a closed set of nine hundreds, 450 is not
  /// one of them, and the axis is the only way to cut glyphs at this weight.
  static const double wghtBody = 450;
  static const double wghtMedium = 500;
  static const double wghtSemi = 600;
  static const double wghtBold = 700;

  static TextStyle _inter(
    double size, {
    required FontWeight weight,
    required double wght,
    double tracking = 0,
    double height = 1.4,
    Color color = TasukeColors.ink,
    List<FontFeature>? features,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      fontVariations: <FontVariation>[FontVariation('wght', wght)],
      letterSpacing: tracking * size,
      height: height,
      color: color,
      fontFeatures: features,
    );
  }

  // ── Display ────────────────────────────────────────────────────────────────

  /// Splash "Tasuke AI".
  static final TextStyle wordmark = _inter(
    30,
    weight: FontWeight.w700,
    wght: wghtBold,
    tracking: -0.02,
    height: 1.15,
  );

  /// Onboarding "Turn Your Voice into Action".
  static final TextStyle displayLg = _inter(
    26,
    weight: FontWeight.w700,
    wght: wghtBold,
    tracking: -0.02,
    height: 1.25,
  );

  /// Permissions "Let's Get Started"; Paywall "Tasuke Pro"; Processing title.
  static final TextStyle displayMd = _inter(
    24,
    weight: FontWeight.w700,
    wght: wghtBold,
    tracking: -0.015,
    height: 1.3,
  );

  // ── Titles ─────────────────────────────────────────────────────────────────

  /// Home "Let's make it happen today".
  static final TextStyle titleLg = _inter(
    22,
    weight: FontWeight.w700,
    wght: wghtBold,
    tracking: -0.01,
    height: 1.3,
  );

  /// Screen titles: "Confirm Tasks", "Task Details", "Recording...".
  static final TextStyle titleMd = _inter(
    20,
    weight: FontWeight.w600,
    wght: wghtSemi,
    height: 1.3,
  );

  /// Card headings; Paywall "Unlock your full potential".
  static final TextStyle titleSm = _inter(
    17,
    weight: FontWeight.w600,
    wght: wghtSemi,
    height: 1.35,
  );

  // ── Body ───────────────────────────────────────────────────────────────────

  /// Settings row title; permission row title.
  static final TextStyle bodyLg = _inter(
    15.5,
    weight: FontWeight.w500,
    wght: wghtMedium,
    height: 1.45,
  );

  /// Onboarding body; permission subtitles. The app's default.
  static final TextStyle bodyMd = _inter(
    15,
    weight: FontWeight.w400,
    wght: wghtBody,
    height: 1.55,
    color: TasukeColors.inkBody,
  );

  /// Recording hint; plan period.
  static final TextStyle bodySm = _inter(
    13.5,
    weight: FontWeight.w400,
    wght: wghtBody,
    height: 1.45,
    color: TasukeColors.inkMuted,
  );

  // ── Tasks ──────────────────────────────────────────────────────────────────

  static final TextStyle taskTitle = _inter(
    16,
    weight: FontWeight.w600,
    wght: wghtSemi,
    tracking: -0.005,
    height: 1.3,
  );

  /// "Today, 10:00 AM".
  static final TextStyle taskMeta = _inter(
    13,
    weight: FontWeight.w400,
    wght: wghtBody,
    height: 1.3,
    color: TasukeColors.inkMuted,
  );

  /// "Tomorrow" / "Friday" / "Next Week" section headers.
  static final TextStyle sectionHeader = _inter(
    15,
    weight: FontWeight.w700,
    wght: wghtBold,
    height: 1.3,
  );

  // ── Controls ───────────────────────────────────────────────────────────────

  static final TextStyle tabLabel = _inter(
    14,
    weight: FontWeight.w600,
    wght: wghtSemi,
    height: 1.2,
  );

  static final TextStyle button = _inter(
    16,
    weight: FontWeight.w600,
    wght: wghtSemi,
    height: 1.2,
    color: TasukeColors.onPrimary,
  );

  /// Date chips and trailing values in a settings row.
  static final TextStyle label = _inter(
    13,
    weight: FontWeight.w500,
    wght: wghtMedium,
    height: 1.2,
    color: TasukeColors.inkMuted,
  );

  /// "We respect your privacy…"; "v1.0.0".
  static final TextStyle caption = _inter(
    12.5,
    weight: FontWeight.w400,
    wght: wghtBody,
    height: 1.4,
    color: TasukeColors.inkMuted,
  );

  /// "Save 33%".
  static final TextStyle badge = _inter(
    11,
    weight: FontWeight.w700,
    wght: wghtBold,
    tracking: 0.02,
    height: 1.1,
  );

  // ── Numerals ───────────────────────────────────────────────────────────────
  //
  // ⚠️ Both of these MUST carry tabularFigures. Inter's default figures are
  // proportional: a mm:ss counter ticking with proportional digits visibly
  // changes its own width once a second, and the design centres it.

  static final TextStyle price = _inter(
    22,
    weight: FontWeight.w700,
    wght: wghtBold,
    tracking: -0.01,
    height: 1.1,
    features: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Recording "00:12".
  static final TextStyle timer = _inter(
    34,
    weight: FontWeight.w600,
    wght: wghtSemi,
    tracking: 0.01,
    height: 1,
    features: const <FontFeature>[FontFeature.tabularFigures()],
  );
}
