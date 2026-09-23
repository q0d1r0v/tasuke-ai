import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/search/presentation/search_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_actions.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Debounced because every keystroke would otherwise re-run a LIKE query
    // and rebuild the list; 220 ms is below the threshold where typing feels
    // laggy and above the rate at which anyone types.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String query = ref.watch(searchQueryProvider);
    final LocalDate today = ref.watch(todayProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TasukeSpacing.gutter,
              TasukeSpacing.lg,
              TasukeSpacing.gutter,
              TasukeSpacing.md,
            ),
            child: Text(
              context.l10n.searchTitle,
              style: TasukeTypography.titleLg,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TasukeSpacing.gutter,
            ),
            child: TasukeTextField(
              controller: _controller,
              hint: context.l10n.searchHint,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              prefix: const Icon(Icons.search_rounded),
              suffix: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        // ⚠️ `clear()` fires no onChanged, so a keystroke's
                        // pending debounce would otherwise land after this and
                        // put the cleared query back under an empty field.
                        _debounce?.cancel();
                        _controller.clear();
                        ref.read(searchQueryProvider.notifier).set('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: TasukeSpacing.lg),
          Expanded(
            child: query.trim().isEmpty
                ? EmptyState(
                    title: context.l10n.emptySearchPromptTitle,
                    message: context.l10n.emptySearchPromptBody,
                    icon: Icons.search_rounded,
                  )
                : AsyncValueView<List<Task>>(
                    value: ref.watch(searchResultsProvider),
                    data: (List<Task> tasks) {
                      if (tasks.isEmpty) {
                        return EmptyState(
                          title: context.l10n.emptySearchNoResultsTitle(
                            query.trim(),
                          ),
                          message: context.l10n.emptySearchNoResultsBody,
                          icon: Icons.search_off_rounded,
                        );
                      }
                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          TasukeSpacing.gutter,
                          0,
                          TasukeSpacing.gutter,
                          TasukeMetrics.navBandHeightOf(context) +
                              TasukeSpacing.lg,
                        ),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: TasukeSpacing.cardGap),
                        itemBuilder: (_, int index) {
                          final Task task = tasks[index];
                          return TaskListTile(
                            task: task,
                            relativeDayLabel: task.due == null
                                ? context.l10n.dateSomeday
                                : DateLabels.day(
                                    context,
                                    task.due!.date,
                                    today,
                                  ),
                            timeLabel: DateLabels.tileTime(context, task),
                            onToggle: (bool value) => unawaited(
                              ref
                                  .read(taskActionsProvider)
                                  .setCompleted(task.id, completed: value),
                            ),
                            onTap: () =>
                                context.push(taskDetailLocation(task.id)),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
