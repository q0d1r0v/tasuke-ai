import 'package:flutter/widgets.dart';

/// Spacing scale. Every gap in the app comes from here.
abstract final class TasukeSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Screen side padding. Content is 335 wide inside the sheet's 375 frame.
  static const double gutter = 20;

  /// Between stacked cards in a list.
  static const double cardGap = 12;

  /// Between a section header and its first row.
  static const double sectionGap = 12;
}

/// Corner radii, and a prebuilt [BorderRadius] for each so no call site
/// constructs one inline and drifts by a pixel.
abstract final class TasukeRadii {
  static const double card = 18;
  static const double cardLg = 20;
  static const double button = 16;
  static const double field = 14;
  static const double tile = 14;
  static const double sheet = 24;
  static const double pill = 999;

  static const BorderRadius rCard = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rCardLg = BorderRadius.all(Radius.circular(cardLg));
  static const BorderRadius rButton = BorderRadius.all(Radius.circular(button));
  static const BorderRadius rField = BorderRadius.all(Radius.circular(field));
  static const BorderRadius rTile = BorderRadius.all(Radius.circular(tile));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius rSheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// Shadows.
///
/// ⚠️ All of them are blue-tinted, not black. The canvas is `#F4F8FD`; a
/// neutral black shadow over it desaturates to grey and the cards read as
/// dirty rather than as raised.
abstract final class TasukeShadows {
  /// Under every white card on the canvas.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0F1B3A6B), offset: Offset(0, 4), blurRadius: 16),
  ];

  /// The blue glow under a primary CTA — the design's colour, not an elevation.
  static const List<BoxShadow> button = <BoxShadow>[
    BoxShadow(color: Color(0x332B7FFF), offset: Offset(0, 8), blurRadius: 20),
  ];

  /// The mic button's halo. Deeper and wider than [button]; it floats over
  /// content rather than sitting in a list.
  static const List<BoxShadow> fab = <BoxShadow>[
    BoxShadow(color: Color(0x4D2B7FFF), offset: Offset(0, 6), blurRadius: 18),
  ];

  /// Cast UPWARD by the bottom nav bar onto the list scrolling under it.
  static const List<BoxShadow> nav = <BoxShadow>[
    BoxShadow(color: Color(0x140B1B33), offset: Offset(0, -2), blurRadius: 18),
  ];
}

/// Fixed component sizes taken from the design sheet.
abstract final class TasukeMetrics {
  /// Every full-width CTA.
  static const double controlHeight = 54;

  /// Settings and permission rows.
  static const double rowHeight = 64;

  /// The rounded icon squares.
  static const double iconTile = 44;

  static const double checkCircle = 24;

  /// The centre mic button on the bottom bar.
  static const double micFab = 64;

  /// The Recording screen's mic circle.
  static const double micOrb = 128;

  /// The bar itself, with no system chrome.
  static const double navBarHeight = 68;

  /// Bar + the mic button's overhang + room for its shadow.
  static const double navBandHeight = 88;

  /// Minimum tap target. Anything interactive is at least this in both axes.
  static const double minTapTarget = 48;

  /// What the nav band really occupies on THIS screen.
  ///
  /// ⚠️ Android 15 (targetSdk 35+) enforces edge-to-edge with no opt-out, so
  /// the Flutter view extends under the system navigation bar — 48dp for
  /// 3-button navigation, ~24dp for the gesture handle. Laying out against
  /// [navBandHeight] alone draws the bar's bottom underneath the back/home/
  /// recents glyphs. The design sheet contains no system chrome, so no constant
  /// taken from it can stand in here.
  ///
  /// `paddingOf`, not `viewPaddingOf`: padding collapses to zero with the
  /// keyboard up, which is correct — the keyboard already covers the bar.
  static double navBandHeightOf(BuildContext context) =>
      navBandHeight + MediaQuery.paddingOf(context).bottom;
}

/// Animation durations.
abstract final class TasukeDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 400);

  /// The Recording orb's breathing cycle.
  static const Duration orbPulse = Duration(milliseconds: 1600);

  /// One full pass through the eight blob frames.
  ///
  /// 2.4 s over eight frames is 300 ms of dwell each. Faster than about 200 ms
  /// and the blob stops reading as breathing and starts reading as a stutter;
  /// slower than about 400 ms and it reads as a still image that occasionally
  /// twitches.
  static const Duration blobCycle = Duration(milliseconds: 2400);

  /// Minimum time a Processing checklist row stays "in progress" before it may
  /// tick.
  ///
  /// On-device extraction can finish in a few hundred milliseconds; without
  /// this the four rows go green almost simultaneously and the screen reads as
  /// a glitch rather than as work being done.
  static const Duration processingStepDwell = Duration(milliseconds: 380);
}
