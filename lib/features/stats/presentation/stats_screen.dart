import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/features/stats/presentation/stats_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: AsyncValueView<TaskStats>(
        value: ref.watch(taskStatsProvider),
        data: (TaskStats stats) {
          final bool nothingYet =
              stats.pending == 0 && stats.completedTotal == 0;
          if (nothingYet) {
            return EmptyState(
              title: context.l10n.emptyStatsTitle,
              message: context.l10n.emptyStatsBody,
              icon: Icons.insights_rounded,
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(
              TasukeSpacing.gutter,
              TasukeSpacing.lg,
              TasukeSpacing.gutter,
              TasukeMetrics.navBandHeightOf(context) + TasukeSpacing.lg,
            ),
            children: <Widget>[
              Text(context.l10n.statsTitle, style: TasukeTypography.titleLg),
              const SizedBox(height: TasukeSpacing.xl),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      value: stats.pending,
                      label: context.l10n.statsPending,
                      color: TasukeColors.primary,
                    ),
                  ),
                  const SizedBox(width: TasukeSpacing.cardGap),
                  Expanded(
                    child: _StatTile(
                      value: stats.completedTotal,
                      label: context.l10n.statsCompleted,
                      color: TasukeColors.success,
                    ),
                  ),
                  const SizedBox(width: TasukeSpacing.cardGap),
                  Expanded(
                    child: _StatTile(
                      value: stats.completedThisWeek,
                      label: context.l10n.statsThisWeek,
                      color: TasukeColors.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TasukeSpacing.xl),
              TasukeCard(
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: TasukeColors.gold,
                    ),
                    const SizedBox(width: TasukeSpacing.md),
                    Text(
                      context.l10n.statsStreak(stats.streakDays),
                      style: TasukeTypography.bodyLg,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TasukeSpacing.xl),
              SectionHeader(label: context.l10n.statsLastSevenDays),
              const SizedBox(height: TasukeSpacing.sectionGap),
              TasukeCard(child: _WeekBars(counts: stats.completionsByDay)),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TasukeCard(
      padding: const EdgeInsets.symmetric(
        vertical: TasukeSpacing.lg,
        horizontal: TasukeSpacing.md,
      ),
      child: Column(
        children: <Widget>[
          Text('$value', style: TasukeTypography.price.copyWith(color: color)),
          const SizedBox(height: TasukeSpacing.xs),
          Text(
            label,
            style: TasukeTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    // ⚠️ `reduce(max)` on an empty list throws, and a fresh install has exactly
    // that. `fold` with a floor of 1 also removes the divide-by-zero below.
    final int peak = counts.fold<int>(1, (int a, int b) => b > a ? b : a);

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int i = 0; i < counts.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: TasukeSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text('${counts[i]}', style: TasukeTypography.caption),
                  const SizedBox(height: TasukeSpacing.xs),
                  // ⚠️ A FRACTION of what is left, never a computed pixel
                  // height. The first version was `12 + 88 * count / peak`
                  // inside a fixed 120pt box, which overflowed by 2px the
                  // moment the label above it was a real glyph — and by far
                  // more at a larger type scale. A fraction of the remaining
                  // space cannot overflow whatever the label does.
                  Expanded(
                    child: FractionallySizedBox(
                      alignment: Alignment.bottomCenter,
                      // ⚠️ `widthFactor: 1` is load-bearing. Without it
                      // FractionallySizedBox leaves the cross axis loose, and a
                      // childless DecoratedBox with loose width collapses to
                      // zero — the bars simply do not appear, with no error and
                      // no overflow to notice.
                      // Half the column: a bar that fills its cell reads as a
                      // stacked block rather than as a bar chart.
                      widthFactor: 0.5,
                      heightFactor: (0.14 + 0.86 * counts[i] / peak).clamp(
                        0.0,
                        1.0,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: counts[i] == 0
                              ? TasukeColors.primaryTint
                              : TasukeColors.primary,
                          borderRadius: TasukeRadii.rPill,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
