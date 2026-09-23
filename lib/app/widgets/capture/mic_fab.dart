import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_gradients.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';

/// The gradient mic button: the one thing the whole app is built around.
class MicFab extends StatelessWidget {
  const MicFab({
    required this.onTap,
    this.enabled = true,
    this.progressLabel,
    this.size = TasukeMetrics.micFab,
    super.key,
  });

  final VoidCallback onTap;

  /// False greys the button and ignores taps. It stays in place rather than
  /// disappearing, because its absence is the one thing that would make the
  /// app look broken. Nothing in the app passes false today: a spent quota
  /// opens the paywall instead.
  final bool enabled;

  /// What the mic is waiting on, with its progress. Announced, and turns the
  /// glyph into a ring. Nothing in the app sets it since the model download,
  /// its only caller, was removed.
  ///
  /// ⚠️ Drawn as a ring and not as text. A 64pt circle cannot lay out a label at
  /// 2× type scale, and a `SizedBox` that clips it is the overflow this
  /// catalogue exists to avoid.
  final String? progressLabel;

  final double size;

  @override
  Widget build(BuildContext context) {
    final bool busy = progressLabel != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: progressLabel ?? context.l10n.homeSpeak,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled ? TasukeGradients.brand : null,
            color: enabled ? null : TasukeColors.outlineSoft,
            boxShadow: enabled ? TasukeShadows.fab : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(
                    Icons.mic_rounded,
                    color: TasukeColors.onPrimary,
                    size: size * 0.44,
                  ),
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.all(TasukeSpacing.xs),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          TasukeColors.onPrimary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
