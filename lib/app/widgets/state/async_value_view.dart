import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/widgets/state/empty_state.dart';
import 'package:tasuke_ai/app/widgets/state/loading_state.dart';

/// The one place in the app that calls [AsyncValue.when].
///
/// Everything else watches a provider and hands the value here. That is not
/// tidiness: `when` has three skip flags whose defaults decide whether a
/// refresh flashes a spinner over content that is already on screen, and having
/// twelve screens each make that call differently is how a list blinks on every
/// pull-to-refresh.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.data,
    this.error,
    this.loading,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T) data;
  final Widget Function(Object, StackTrace)? error;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      // Defaults, stated: a reload keeps the old data on screen, a refresh does
      // too, and an error over existing data still wins — a task list that has
      // gone stale is not a task list worth showing.
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: data,
      loading: () => loading ?? const LoadingState(),
      error: (Object e, StackTrace stack) =>
          error?.call(e, stack) ??
          EmptyState(
            // Deliberately not an ErrorState: there is no retry callback here,
            // and a button that cannot retry is a button that lies.
            title: context.l10n.errorGenericTitle,
            message: context.l10n.errorGenericBody,
            icon: Icons.error_outline_rounded,
          ),
    );
  }
}
