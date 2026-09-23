import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tasuke_colors.dart';
import 'tasuke_spacing.dart';
import 'tasuke_typography.dart';

/// The app's [ThemeData].
///
/// Written as a named constructor with no arguments so that adding `dark()`
/// later touches no call site. v1 ships light only — see `TasukeApp` for why
/// `themeMode` is pinned rather than simply left unset.
abstract final class TasukeTheme {
  static ThemeData light() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(seedColor: TasukeColors.primary).copyWith(
          primary: TasukeColors.primary,
          onPrimary: TasukeColors.onPrimary,
          surface: TasukeColors.surface,
          onSurface: TasukeColors.ink,
          error: TasukeColors.danger,
          onError: TasukeColors.onPrimary,
          outline: TasukeColors.border,
          outlineVariant: TasukeColors.divider,
          surfaceContainerHighest: TasukeColors.canvas,
          shadow: const Color(0x1A1B3A6B),
          scrim: TasukeColors.scrim,
        );

    final TextTheme textTheme = TextTheme(
      displayLarge: TasukeTypography.wordmark,
      displayMedium: TasukeTypography.displayLg,
      displaySmall: TasukeTypography.displayMd,
      headlineMedium: TasukeTypography.titleLg,
      headlineSmall: TasukeTypography.titleMd,
      titleLarge: TasukeTypography.titleMd,
      titleMedium: TasukeTypography.titleSm,
      titleSmall: TasukeTypography.bodyLg,
      bodyLarge: TasukeTypography.bodyLg,
      bodyMedium: TasukeTypography.bodyMd,
      bodySmall: TasukeTypography.bodySm,
      labelLarge: TasukeTypography.button,
      labelMedium: TasukeTypography.label,
      labelSmall: TasukeTypography.caption,
    );

    return ThemeData(
      // Explicit while the flag still exists, even though it is the default
      // from Flutter 3.29 — an explicit `true` documents intent.
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: TasukeColors.canvas,
      canvasColor: TasukeColors.canvas,
      fontFamily: TasukeTypography.family,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // ⚠️ The DEFAULT splash factory, deliberately.
      //
      // `InkSparkle.splashFactory` — the Android 12 sparkle — was here and is
      // the wrong choice twice over. It renders as a bright rectangular flash
      // on a rounded control on real hardware, which is what a user reports as
      // "pressing the button shows a square"; and a glittering ripple is not
      // what this design sheet draws anywhere. The Material 3 default
      // (`InkRipple`) honours the surface's shape and is quiet.

      // The design is a premium, minimal, iOS-leaning sheet. Android's default
      // ZoomPageTransitionsBuilder reads as a different app next to it.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: TasukeColors.canvas,
        foregroundColor: TasukeColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        // ⚠️ M3 tints app bars, cards, bottom app bars and dialogs on elevation
        // by default. Leaving this unset is the single most common cause of
        // "my white surface turns faintly lavender when content scrolls".
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TasukeTypography.titleMd,
      ),

      cardTheme: CardThemeData(
        color: TasukeColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: TasukeRadii.rCard),
      ),

      dividerTheme: const DividerThemeData(
        color: TasukeColors.divider,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TasukeColors.surface,
        hintStyle: TasukeTypography.bodyMd.copyWith(
          color: TasukeColors.inkFaint,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TasukeSpacing.lg,
          vertical: TasukeSpacing.md + 2,
        ),
        border: const OutlineInputBorder(
          borderRadius: TasukeRadii.rField,
          borderSide: BorderSide(color: TasukeColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: TasukeRadii.rField,
          borderSide: BorderSide(color: TasukeColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: TasukeRadii.rField,
          borderSide: BorderSide(color: TasukeColors.primary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: TasukeRadii.rField,
          borderSide: BorderSide(color: TasukeColors.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: TasukeRadii.rField,
          borderSide: BorderSide(color: TasukeColors.danger, width: 1.5),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TasukeColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: TasukeRadii.rSheetTop),
        showDragHandle: true,
        dragHandleColor: TasukeColors.outlineSoft,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: TasukeColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: TasukeRadii.rCardLg),
        titleTextStyle: TasukeTypography.titleSm,
        contentTextStyle: TasukeTypography.bodyMd,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: TasukeColors.ink,
        contentTextStyle: TasukeTypography.bodyMd.copyWith(
          color: TasukeColors.onPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: TasukeRadii.rField),
        elevation: 0,
      ),

      // Matched to TasukeSwitch so a stray Material Switch is not visibly a
      // different control. TasukeSwitch is still custom: M3 draws an outlined
      // track when off and grows the thumb when on, and no theme removes
      // either.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => TasukeColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? TasukeColors.primary
              : TasukeColors.outlineSoft,
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TasukeColors.primary,
        // ⚠️ Not primaryTint. See TasukeColors.progressTrack — the tint is
        // invisible on every ground this app puts a progress bar on. Set here
        // rather than on the usage meter, so the next bar cannot repeat it.
        linearTrackColor: TasukeColors.progressTrack,
        circularTrackColor: TasukeColors.primaryTint,
      ),

      iconTheme: const IconThemeData(color: TasukeColors.ink, size: 22),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: TasukeSpacing.lg),
        minVerticalPadding: TasukeSpacing.md,
      ),

      // ⚠️ Both TRANSLUCENT, and that is the point.
      //
      // `primaryTint` is an opaque #EAF2FF: as a splash it paints a solid pale
      // block over whatever it lands on, which on the blue CTA reads as a
      // rectangle appearing rather than as a press. Ink is supposed to tint
      // what is underneath, so it has to have alpha.
      splashColor: const Color(0x1F2B7FFF),
      highlightColor: const Color(0x142B7FFF),
    );
  }
}
