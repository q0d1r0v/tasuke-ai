import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/app_router.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/theme/system_overlay.dart';

class TasukeApp extends ConsumerWidget {
  const TasukeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️ Annotated once, at the root. RenderView writes nothing to the platform
    // when a frame carries no AnnotatedRegion, so the bars keep whatever style
    // was last pushed — which is how an app ends up with white-on-white status
    // bar icons after visiting one dark screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: TasukeOverlay.light,
      child: MaterialApp.router(
        title: 'Tasuke AI',
        debugShowCheckedModeBanner: false,
        routerConfig: ref.watch(routerProvider),
        theme: TasukeTheme.light(),
        // ⚠️ Pinned, not merely "darkTheme is null". MaterialApp already falls
        // back to `theme` when `darkTheme` is absent, so today these behave
        // identically — the pin is what stops a later `darkTheme:` line from
        // silently shipping a dark mode nobody designed. All twelve frames of
        // the design sheet are light; an auto-derived dark theme would invert
        // the #F4F8FD canvas and leave the blue-tinted card shadows reading as
        // smudges, which users report as a bug rather than as an absence.
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) {
          // Clamp only the extremes. The layout is tested to 2.0×; beyond that
          // the design stops being the design, and below 0.8× it is unreadable
          // on a phone.
          final MediaQueryData media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 2,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
