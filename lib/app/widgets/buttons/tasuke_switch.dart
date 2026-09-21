import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';

/// The UIKit switch geometry the design sheet draws, stated once.
///
/// Not in `TasukeMetrics` because nothing else in the app is 51×31 — these three
/// numbers only mean anything together, and together they are this control.
const double _trackWidth = 51;
const double _trackHeight = 31;
const double _thumbInset = 2;
const double _thumbSize = _trackHeight - (_thumbInset * 2);

/// A flat pill switch, drawn by hand.
///
/// ⚠️ Custom rather than a themed [Switch] because Material 3 draws an outlined
/// track in the off state and grows the thumb from 16 to 24 when it turns on.
/// Neither is removable through `SwitchThemeData`: the outline is only
/// suppressible to transparent (the track then reads 2pt short), and the thumb
/// size is hard-coded in `_SwitchConfigM3`. The design has one thumb size and no
/// outline, so the control is painted here instead.
class TasukeSwitch extends StatelessWidget {
  const TasukeSwitch({
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.semanticLabel,
    super.key,
  });

  final bool value;

  /// `null` disables the switch.
  final ValueChanged<bool>? onChanged;

  /// An in-flight write — a notification permission request, a store restore.
  /// Taps are ignored so the user cannot queue two opposite writes.
  final bool busy;

  /// Announced by a screen reader. The switch itself has no visible text, so
  /// without this it is read as an unlabelled toggle.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null && !busy;
    final Color track = value
        ? (enabled ? TasukeColors.primary : TasukeColors.primaryWash)
        : TasukeColors.outlineSoft;

    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        toggled: value,
        enabled: enabled,
        child: GestureDetector(
          // Opaque so the whole 48pt box is the target, not just the 31pt pill.
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  unawaited(HapticFeedback.selectionClick());
                  onChanged!(!value);
                }
              : null,
          child: SizedBox(
            width: _trackWidth,
            height: TasukeMetrics.minTapTarget,
            child: Center(
              child: AnimatedContainer(
                duration: TasukeDurations.fast,
                curve: Curves.easeOut,
                width: _trackWidth,
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: TasukeRadii.rPill,
                ),
                child: AnimatedAlign(
                  duration: TasukeDurations.fast,
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(_thumbInset),
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: const BoxDecoration(
                        color: TasukeColors.surface,
                        shape: BoxShape.circle,
                        boxShadow: TasukeShadows.card,
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(TasukeSpacing.xs + 2),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
