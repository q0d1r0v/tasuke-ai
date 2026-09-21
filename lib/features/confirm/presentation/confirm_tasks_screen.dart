import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/confirm/presentation/draft_date_sheet.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

class ConfirmTasksScreen extends ConsumerWidget {
  const ConfirmTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CaptureState state = ref.watch(captureControllerProvider);
    final CaptureController controller = ref.read(
      captureControllerProvider.notifier,
    );
    final LocalDate today = ref.watch(todayProvider);

    Future<void> leave() async {
      if (state.hasDrafts) {
        final bool discard = await showDiscardDraftsDialog(context) ?? false;
        if (!discard) return;
      }
      await controller.cancel();
      if (context.mounted) context.go('/home');
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        backgroundColor: TasukeColors.canvas,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              ScreenHeader(
                title: context.l10n.confirmTitle,
                onBack: () => unawaited(leave()),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TasukeSpacing.gutter,
                  ),
                  children: <Widget>[
                    Text(
                      context.l10n.confirmFoundTasks(state.drafts.length),
                      style: TasukeTypography.bodyMd,
                    ),
                    if (state.truncatedAtLimit) ...<Widget>[
                      const SizedBox(height: TasukeSpacing.lg),
                      TasukeBanner(
                        message: context.l10n.recordingMaxReached,
                        icon: Icons.timer_outlined,
                        tone: BannerTone.warning,
                      ),
                    ],
                    if (state.failure is StorageFailure) ...<Widget>[
                      const SizedBox(height: TasukeSpacing.lg),
                      TasukeBanner(
                        message: (state.failure! as StorageFailure).diskFull
                            ? context.l10n.errorDiskFull
                            : context.l10n.errorGenericBody,
                        icon: Icons.error_outline_rounded,
                        tone: BannerTone.danger,
                      ),
                    ],
                    const SizedBox(height: TasukeSpacing.xl),
                    for (final TaskDraft draft in state.drafts) ...<Widget>[
                      EditableTaskCard(
                        draft: draft,
                        dateLabelBuilder: (TaskDraft d) =>
                            _dateLabel(context, d, today),
                        onChanged: controller.updateDraft,
                        onDelete: () => controller.removeDraft(draft.draftId),
                        onEditDate: () async {
                          final TaskDraft? updated = await showDraftDateSheet(
                            context,
                            draft: draft,
                            today: today,
                          );
                          if (updated != null) controller.updateDraft(updated);
                        },
                      ),
                      const SizedBox(height: TasukeSpacing.cardGap),
                    ],
                    DashedAddRow(
                      label: context.l10n.confirmAddAnother,
                      onTap: controller.addBlankDraft,
                    ),
                    const SizedBox(height: TasukeSpacing.xxl),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TasukeSpacing.gutter,
                  0,
                  TasukeSpacing.gutter,
                  TasukeSpacing.xxl,
                ),
                child: PrimaryButton(
                  label: context.l10n.confirmSave,
                  busy: state.phase.isBusy,
                  onPressed: state.allDraftsValid
                      ? () async {
                          final int count = state.drafts.length;
                          final bool saved = await controller.save();
                          if (!context.mounted) return;
                          if (saved) {
                            context.go('/home');
                            AppSnack.success(
                              context,
                              context.l10n.confirmSaved(count),
                            );
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(BuildContext context, TaskDraft draft, LocalDate today) {
    final LocalDate? date = draft.date;
    if (date == null) return context.l10n.taskNoDate;
    final String day = DateLabels.day(context, date, today);
    if (draft.time == null) {
      return '$day · ${context.l10n.taskAllDay}';
    }
    return '$day · ${DateLabels.time(context, draft.time!)}';
  }
}
