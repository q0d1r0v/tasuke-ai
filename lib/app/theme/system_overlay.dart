import 'package:flutter/services.dart';

import 'tasuke_colors.dart';

/// Status- and navigation-bar styling.
///
/// ⚠️ `RenderView._updateSystemChrome` writes nothing when a frame carries no
/// `AnnotatedRegion<SystemUiOverlayStyle>` — the platform simply keeps whatever
/// was last pushed. So the style must be annotated at the app root, not left to
/// individual screens, or the bar keeps the style of whichever screen last set
/// one.
///
/// Tasuke is light on every frame of the design sheet, so [light] is annotated
/// once in `TasukeApp` and nothing overrides it.
abstract final class TasukeOverlay {
  /// Dark icons on a light background. The app default.
  static const SystemUiOverlayStyle light = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
  );

  /// Light icons on a dark background. Unused in v1; kept so that the one
  /// screen that might go dark later does not invent its own.
  static const SystemUiOverlayStyle dark = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
  );

  /// Kept next to the styles so the one colour they assume is visible here.
  static const Color assumedBackground = TasukeColors.canvas;
}
