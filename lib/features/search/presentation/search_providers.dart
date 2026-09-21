import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

final NotifierProvider<SearchQueryController, String> searchQueryProvider =
    NotifierProvider<SearchQueryController, String>(SearchQueryController.new);

final class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final StreamProvider<List<Task>> searchResultsProvider =
    StreamProvider<List<Task>>((Ref ref) {
      final String query = ref.watch(searchQueryProvider).trim();
      if (query.isEmpty) return Stream<List<Task>>.value(const <Task>[]);
      return ref.watch(taskRepositoryProvider).watchSearch(query, limit: 100);
    });
