import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override`, `ProviderListenable` or the
// `*Family` types from its main library — only from `misc.dart`. Naming any of
// them without this import is a `non_type_as_type_argument` error that reads
// like a missing dependency.
import 'package:flutter_riverpod/misc.dart';

/// Bridges Riverpod to go_router's `refreshListenable`.
///
/// go_router re-runs its redirect when this notifies. Each watched provider is
/// subscribed once and disposed with the notifier, so a provider that rebuilds
/// for an unrelated reason does not leak a listener.
final class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(
    this._ref,
    List<ProviderListenable<Object?>> providers,
  ) {
    for (final ProviderListenable<Object?> provider in providers) {
      _subscriptions.add(
        _ref.listen<Object?>(
          provider,
          (Object? _, Object? _) => notifyListeners(),
          fireImmediately: false,
        ),
      );
    }
  }

  final Ref _ref;
  final List<ProviderSubscription<Object?>> _subscriptions =
      <ProviderSubscription<Object?>>[];

  @override
  void dispose() {
    for (final ProviderSubscription<Object?> subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
