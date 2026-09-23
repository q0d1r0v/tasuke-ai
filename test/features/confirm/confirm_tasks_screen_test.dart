import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/confirm/presentation/confirm_tasks_screen.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// A task store that cannot write.
///
/// `noSuchMethod` rather than eighteen stub members: a save that fails on its
/// first write reaches nothing else on the port, and a stub that quietly
/// returned an empty list would hide the day it does.
final class _UnwritableTaskRepository implements TaskRepository {
  _UnwritableTaskRepository(this.error);

  final Object error;

  @override
  Future<List<Task>> saveDrafts(
    List<TaskDraft> drafts, {
    required String captureId,
    required int allDayReminderMinute,
  }) async {
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  /// Wednesday 2026-03-11, 10:00 local.
  final Clock clock = FixedClock(DateTime(2026, 3, 11, 10));

  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeUsageRepository usage;
  late FakeLocalNotifier notifier;

  setUp(() {
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    usage = FakeUsageRepository();
    notifier = FakeLocalNotifier();
  });

  tearDown(() {
    tasks.dispose();
    settings.dispose();
    usage.dispose();
    notifier.dispose();
  });

  TaskDraft draft(
    String id, {
    String title = 'Send the build to James',
    LocalDate? date,
  }) => TaskDraft(draftId: id, title: title, date: date);

  Future<GoRouter> pumpConfirm(
    WidgetTester tester, {
    required CaptureState seed,
    TaskRepository? repository,
  }) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = GoRouter(
      initialLocation: '/capture/confirm',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home screen')),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => const Scaffold(body: Text('recording screen')),
          routes: <RouteBase>[
            GoRoute(
              path: 'confirm',
              builder: (_, _) => const ConfirmTasksScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            settings: settings,
            clock: clock,
            notifier: notifier,
          ),
          // ⚠️ Every one of these is backed by drift in production, and a drift
          // database opened inside `testWidgets`' FakeAsync deadlocks the
          // isolate outright.
          taskRepositoryProvider.overrideWithValue(repository ?? tasks),
          usageRepositoryProvider.overrideWithValue(usage),
          primaryTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          fallbackTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          captureControllerProvider.overrideWithBuild(
            (Ref ref, CaptureController notifier) => seed,
          ),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await pumpSettled(tester);
    return router;
  }

  CaptureState stateOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    ).read(captureControllerProvider);
  }

  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('the count line', () {
    testWidgets('nothing found still invites an edit rather than a retry', (
      WidgetTester tester,
    ) async {
      await pumpConfirm(
        tester,
        seed: const CaptureState(phase: CapturePhase.confirming),
      );

      expect(
        find.text(
          "We didn't find a task in that. Edit it below, or try again.",
        ),
        findsOneWidget,
      );

      await shutdown(tester);
    });

    testWidgets('one draft reads in the singular', (WidgetTester tester) async {
      await pumpConfirm(
        tester,
        seed: CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[draft('a')],
        ),
      );

      expect(
        find.text('We found 1 task. You can edit it before saving.'),
        findsOneWidget,
      );

      await shutdown(tester);
    });

    testWidgets('two drafts read in the plural', (WidgetTester tester) async {
      await pumpConfirm(
        tester,
        seed: CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[
            draft('a'),
            draft('b', title: 'Book the flight'),
          ],
        ),
      );

      expect(
        find.text('We found 2 tasks. You can edit them before saving.'),
        findsOneWidget,
      );

      await shutdown(tester);
    });

    testWidgets('a task typed by hand is not called found', (
      WidgetTester tester,
    ) async {
      // "Type a task instead": nothing was recorded, so "We found 1 task"
      // reads like the app misheard something.
      await pumpConfirm(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[
            TaskDraft(draftId: 'm', title: '', source: TaskSource.manual),
          ],
        ),
      );

      expect(find.text('Type your task, then save it.'), findsOneWidget);
      expect(find.textContaining('We found'), findsNothing);

      await shutdown(tester);
    });
  });

  testWidgets('editing a title writes straight through to the draft', (
    WidgetTester tester,
  ) async {
    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[draft('a')],
      ),
    );

    await tester.enterText(find.byType(TextField), 'Send the build to Priya');
    await pumpSettled(tester);

    expect(stateOf(tester).drafts.single.title, 'Send the build to Priya');

    await shutdown(tester);
  });

  testWidgets('deleting a card removes that draft and nothing else', (
    WidgetTester tester,
  ) async {
    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[
          draft('a'),
          draft('b', title: 'Book the flight'),
        ],
      ),
    );

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.close_rounded).at(1),
    );
    await pumpSettled(tester);

    expect(stateOf(tester).drafts.map((TaskDraft d) => d.draftId), <String>[
      'a',
    ]);
    expect(
      find.text('We found 1 task. You can edit it before saving.'),
      findsOneWidget,
    );
    expect(find.text('Book the flight'), findsNothing);

    await shutdown(tester);
  });

  testWidgets('deleting a card above the focused one keeps typing in place', (
    WidgetTester tester,
  ) async {
    // ⚠️ Unkeyed cards are matched by position. Deleting the first handed the
    // focused second field the THIRD draft, and what the user typed next was
    // saved into a task they never touched.
    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[
          draft('a', title: 'Call mum'),
          draft('b', title: 'Book the flight'),
          draft('c', title: 'Buy milk'),
        ],
      ),
    );

    await tester.showKeyboard(find.byType(TextField).at(1));
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.close_rounded).at(0),
    );
    await pumpSettled(tester);
    tester.testTextInput.enterText('Book the flight to Tokyo');
    await pumpSettled(tester);

    final List<TaskDraft> drafts = stateOf(tester).drafts;
    await shutdown(tester);

    expect(drafts.map((TaskDraft d) => d.draftId), <String>['b', 'c']);
    expect(drafts[0].title, 'Book the flight to Tokyo');
    expect(drafts[1].title, 'Buy milk');
  });

  testWidgets('"Add another task" appends an empty draft', (
    WidgetTester tester,
  ) async {
    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[draft('a')],
      ),
    );

    await tester.tap(find.byType(DashedAddRow));
    await pumpSettled(tester);

    final List<TaskDraft> drafts = stateOf(tester).drafts;
    expect(drafts, hasLength(2));
    expect(drafts.last.title, isEmpty);
    expect(drafts.last.source, TaskSource.manual);

    await shutdown(tester);
  });

  testWidgets('Save is refused while any title is empty, and offered once it '
      'is not', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[
          draft('a'),
          draft('b', title: ''),
        ],
      ),
    );

    // ⚠️ Both directions. A Save that stays greyed after the user fixes the
    // row is the same bug as one that writes an empty task.
    expect(
      tester.getSemantics(find.byType(PrimaryButton)),
      isSemantics(label: 'Save Tasks', isButton: true, isEnabled: false),
    );

    await tester.enterText(find.byType(TextField).at(1), 'Book the flight');
    await pumpSettled(tester);

    expect(
      tester.getSemantics(find.byType(PrimaryButton)),
      isSemantics(label: 'Save Tasks', isButton: true, isEnabled: true),
    );

    handle.dispose();
    await shutdown(tester);
  });

  testWidgets('the one-minute banner appears only for a truncated capture', (
    WidgetTester tester,
  ) async {
    const String banner =
        "We stopped at one minute. Anything after that wasn't recorded.";

    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[draft('a')],
      ),
    );
    expect(find.text(banner), findsNothing);
    await shutdown(tester);

    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[draft('a')],
        truncatedAtLimit: true,
      ),
    );
    expect(find.text(banner), findsOneWidget);

    await shutdown(tester);
  });

  group('a save that fails', () {
    testWidgets('keeps every draft on screen and says so', (
      WidgetTester tester,
    ) async {
      await pumpConfirm(
        tester,
        seed: CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[
            draft('a'),
            draft('b', title: 'Book the flight'),
          ],
        ),
        repository: _UnwritableTaskRepository(StateError('write failed')),
      );

      await tester.tap(find.byType(PrimaryButton));
      await pumpSettled(tester);

      expect(find.text('Please try again.'), findsOneWidget);

      // ⚠️ The assertion this test exists for. A failed save that also ate the
      // user's edits is the worst possible outcome of this screen.
      expect(stateOf(tester).drafts, hasLength(2));
      expect(find.text('Send the build to James'), findsOneWidget);
      expect(find.text('Book the flight'), findsOneWidget);
      expect(find.byType(EditableTaskCard), findsNWidgets(2));
      expect(find.text('home screen'), findsNothing);

      await shutdown(tester);
    });

    testWidgets('names a full disk, which the user can actually act on', (
      WidgetTester tester,
    ) async {
      await pumpConfirm(
        tester,
        seed: CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[draft('a')],
        ),
        repository: _UnwritableTaskRepository(
          StateError('database or disk is full'),
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      await pumpSettled(tester);

      expect(
        find.text(
          "There isn't enough space to save. Free some up and try again.",
        ),
        findsOneWidget,
      );
      expect(stateOf(tester).drafts, hasLength(1));

      await shutdown(tester);
    });
  });

  testWidgets('a save that works writes the tasks and routes Home', (
    WidgetTester tester,
  ) async {
    await pumpConfirm(
      tester,
      seed: CaptureState(
        phase: CapturePhase.confirming,
        drafts: <TaskDraft>[
          draft('a'),
          draft('b', title: 'Book the flight'),
        ],
      ),
    );

    await tester.tap(find.byType(PrimaryButton));
    await pumpSettled(tester);

    expect(
      tasks.all.map((Task t) => t.title),
      containsAll(<String>['Send the build to James', 'Book the flight']),
    );
    expect(find.text('home screen'), findsOneWidget);
    expect(find.text('2 tasks saved'), findsOneWidget);

    await shutdown(tester);
  });

  group('leaving with unsaved drafts', () {
    testWidgets('asks first, and stays put when the answer is no', (
      WidgetTester tester,
    ) async {
      await pumpConfirm(
        tester,
        seed: CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[draft('a')],
        ),
      );

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded),
      );
      await pumpSettled(tester);
      expect(find.text('Discard these tasks?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await pumpSettled(tester);

      expect(find.byType(ConfirmTasksScreen), findsOneWidget);
      expect(stateOf(tester).drafts, hasLength(1));

      await shutdown(tester);
    });

    testWidgets('discards and routes Home when the answer is yes', (
      WidgetTester tester,
    ) async {
      await pumpConfirm(
        tester,
        seed: CaptureState(
          phase: CapturePhase.confirming,
          drafts: <TaskDraft>[draft('a')],
        ),
      );

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded),
      );
      await pumpSettled(tester);
      await tester.tap(find.text('Discard'));
      await pumpSettled(tester);

      expect(find.text('home screen'), findsOneWidget);
      expect(stateOf(tester).phase, CapturePhase.idle);
      expect(tasks.all, isEmpty);

      await shutdown(tester);
    });
  });
}
