import 'dart:ui';

/// Tasuke AI's palette, sampled from the twelve-frame design sheet.
///
/// Sampled values are given as measured. Derived values state what they were
/// derived from — a hex with no note is a hex nobody can safely change.
abstract final class TasukeColors {
  // ── Brand blue ─────────────────────────────────────────────────────────────

  /// The brand blue. Sampled `#2B7FFF`.
  ///
  /// ⚠️ The sheet also yields `#287FFE`, `#267DFC` and `#1C76FD` from what is
  /// visibly the same fill — four hexes within 2/255 of one another, which is
  /// PNG chroma subsampling, not four decisions. Shipping all four would put a
  /// colour ramp where the design has one flat fill. Two tokens carry the whole
  /// family: this one and [primaryPressed].
  static const Color primary = Color(0xFF2B7FFF);

  /// The darkest of the sampled blues, `#1C76FD`. Pressed buttons and the
  /// selected segmented-tab pill.
  static const Color primaryPressed = Color(0xFF1C76FD);

  /// [primary] at 10% over [surface]. The rounded icon tiles on Permissions,
  /// Task Details and Settings; an unselected plan card's fill.
  static const Color primaryTint = Color(0xFFEAF2FF);

  /// [primary] at 18% over [surface]. The selected plan card's border wash and
  /// the "Save 33%" badge ground.
  static const Color primaryWash = Color(0xFFD6E6FF);

  /// The brand gradient stops, sampled top-left → bottom-right off the app icon
  /// and the mic button. Used through `TasukeGradients.brand`; never painted as
  /// a flat fill.
  static const Color gradientStart = Color(0xFF4FA6FE);
  static const Color gradientEnd = Color(0xFF2B75FA);

  // ── Surfaces ───────────────────────────────────────────────────────────────

  /// The page canvas. Sampled `#F4F8FD` — a blue-tinted off-white, not a grey.
  ///
  /// This is why [TasukeShadows] are blue-tinted rather than black: a neutral
  /// black shadow over this canvas desaturates to grey and the cards read as
  /// dirty rather than as raised.
  static const Color canvas = Color(0xFFF4F8FD);

  /// Cards, sheets, fields, the bottom nav bar. Sampled `#FFFFFF`.
  static const Color surface = Color(0xFFFFFFFF);

  /// The splash backdrop's soft blue wash. Sampled `#E2EEFD`.
  static const Color splashTint = Color(0xFFE2EEFD);

  // ── Ink ────────────────────────────────────────────────────────────────────

  /// Headings and task titles.
  static const Color ink = Color(0xFF0F1B33);

  /// Body copy — onboarding paragraphs, permission subtitles.
  static const Color inkBody = Color(0xFF243049);

  /// Secondary metadata: "Today, 10:00 AM", "Good morning,", settings values,
  /// the privacy footer.
  static const Color inkMuted = Color(0xFF6B7A99);

  /// Placeholders, disabled labels, inactive nav glyphs, chevrons.
  static const Color inkFaint = Color(0xFF9AA7C0);

  // ── Lines ──────────────────────────────────────────────────────────────────

  /// Card and field borders where the design draws a hairline.
  static const Color border = Color(0xFFE4EBF5);

  /// Row separators inside a settings group. Lighter than [border] on purpose:
  /// the design separates rows without boxing them.
  static const Color divider = Color(0xFFEEF3FA);

  /// The unchecked task circle's stroke, and the dashed "Add another task"
  /// outline on Confirm.
  static const Color outlineSoft = Color(0xFFCBD7E8);

  // ── Semantic ───────────────────────────────────────────────────────────────

  /// Destructive. Sampled `#F82732` off the Recording "Stop" button and the
  /// Task Details "Delete Task" label.
  static const Color danger = Color(0xFFF82732);

  /// [danger] at 8% over [surface] — the "Delete Task" button's fill.
  static const Color dangerTint = Color(0xFFFEEAEB);

  /// Completed bars on Stats. Not in the sheet; chosen because the only other
  /// candidate was [primary], and a blue "done" bar on a blue-primary screen
  /// carries no information.
  static const Color success = Color(0xFF22C55E);

  /// [success] at 10% over [surface].
  static const Color successTint = Color(0xFFE7FAEE);

  /// The Pro crown on the paywall.
  static const Color gold = Color(0xFFF5B301);

  /// [gold] at 12% over [surface] — the crown's tile.
  static const Color goldTint = Color(0xFFFEF3D9);

  // ── Component-specific ─────────────────────────────────────────────────────

  /// Idle waveform bars behind the live ones — [primary] at ~25%.
  static const Color waveformIdle = Color(0xFFBFD8FF);

  /// Scrim behind dialogs and sheets — [ink] at 40%, not black at 40%.
  /// Black greys the blue canvas rather than deepening it.
  static const Color scrim = Color(0x660F1B33);

  /// Content that sits on [primary] or on the brand gradient.
  static const Color onPrimary = Color(0xFFFFFFFF);
}
