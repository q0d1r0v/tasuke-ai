import 'dart:async';
import 'dart:typed_data';

import 'package:tasuke_ai/core/audio/audio_recorder.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/store_page_opener.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

/// Fakes for every port.
///
/// They are installed by default in `pumpApp`, whether or not a test asks for
/// them: a screen that reaches a real MethodChannel under `flutter_test` throws
/// inside a Future, the error lands in an `AsyncValue.error`, and the test
/// passes having exercised nothing at all.

final class FakeAudioRecorder implements AudioRecorder {
  FakeAudioRecorder({this.chunks = const <List<int>>[]});

  /// PCM16 chunks to emit, in order.
  final List<List<int>> chunks;

  bool granted = true;
  bool started = false;
  bool cancelled = false;
  bool disposed = false;

  StreamController<Uint8List>? _controller;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> isRecording() async => started;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    final StreamController<Uint8List> controller =
        StreamController<Uint8List>();
    _controller = controller;
    for (final List<int> chunk in chunks) {
      controller.add(Uint8List.fromList(chunk));
    }
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    started = false;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    await stop();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}

final class FakeSpeechRecognizer implements SpeechRecognizer {
  /// How many times the pipeline asked for the model to be put in place.
  ///
  /// ⚠️ Asserted on by `pipeline` tests. The real recogniser's model install
  /// had no caller at all and nothing noticed, because every test swapped this
  /// fake in and fakes need no model. Counting the call is the cheapest thing
  /// that would have failed.
  int prepareCalls = 0;

  @override
  Future<void> prepare() async => prepareCalls++;
  FakeSpeechRecognizer({
    this.transcript = '',
    this.partials = const <String>[],
    this.available = SpeechAvailability.ready,
  });

  String transcript;
  final List<String> partials;
  SpeechAvailability available;

  bool released = false;
  bool cancelled = false;

  StreamController<SpeechEvent>? _events;

  @override
  Future<SpeechAvailability> availability() async => available;

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) {
    final StreamController<SpeechEvent> controller =
        StreamController<SpeechEvent>();
    _events = controller;
    // Drain the audio so the producer is not left with an unlistened stream.
    pcm16.listen((_) {}, onDone: () {});
    for (final String partial in partials) {
      controller.add(SpeechPartial(partial));
    }
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    _events?.add(SpeechFinal(transcript));
    await _events?.close();
    _events = null;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    await _events?.close();
    _events = null;
  }

  @override
  Future<void> release() async => released = true;
}

/// Returns whatever it was handed, so a pipeline test can assert plumbing
/// without depending on the grammar.
final class FakeTaskExtractor implements TaskExtractor {
  FakeTaskExtractor({
    this.result = const <ExtractedTask>[],
    this.ready = true,
    this.throws,
    this.delay,
  });

  List<ExtractedTask> result;
  bool ready;
  Object? throws;
  Duration? delay;

  String? lastTranscript;
  LocalDateTime? lastNow;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) async {
    lastTranscript = transcript;
    lastNow = now;
    if (delay != null) await Future<void>.delayed(delay!);
    final Object? error = throws;
    if (error != null) throw error;
    return result;
  }
}

final class FakePermissionService implements PermissionService {
  FakePermissionService({
    Map<AppPermission, PermissionState>? states,
    this.grantOnRequest = false,
    Map<AppPermission, PermissionState>? answers,
  }) : _answers = answers ?? <AppPermission, PermissionState>{},
       _states =
           states ??
           <AppPermission, PermissionState>{
             AppPermission.microphone: PermissionState.granted,
             AppPermission.notifications: PermissionState.granted,
             AppPermission.exactAlarm: PermissionState.granted,
           };

  final Map<AppPermission, PermissionState> _states;

  int settingsOpened = 0;
  final List<AppPermission> requested = <AppPermission>[];

  void set(AppPermission permission, PermissionState state) =>
      _states[permission] = state;

  @override
  Future<PermissionState> status(AppPermission permission) async =>
      _states[permission] ?? PermissionState.notDetermined;

  /// When true, a request the OS could answer is answered "yes" and the new
  /// state sticks — a user tapping Allow on every prompt. Off by default, so a
  /// request that is expected to change nothing does not.
  final bool grantOnRequest;

  /// What a request answers, and what the status then stays at. Models
  /// Android, where `status` says `denied` until a request reveals that the OS
  /// will not ask again.
  final Map<AppPermission, PermissionState> _answers;

  @override
  Future<PermissionState> request(AppPermission permission) async {
    requested.add(permission);
    final PermissionState? answer = _answers[permission];
    if (answer != null) return _states[permission] = answer;
    final PermissionState? current = _states[permission];
    if (grantOnRequest && !(current?.needsSettings ?? false)) {
      _states[permission] = PermissionState.granted;
    }
    return _states[permission] ?? PermissionState.granted;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

final class FakeLocalNotifier implements LocalNotifier {
  FakeLocalNotifier({this.permitted = true, this.exact = true});

  bool permitted;
  bool exact;

  final List<ScheduledReminder> scheduled = <ScheduledReminder>[];
  final List<int> cancelled = <int>[];
  bool cancelledAll = false;
  String? launchPayload;

  final StreamController<String> _taps = StreamController<String>.broadcast();

  @override
  Future<void> initialise() async {}

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<bool> requestPermission() async => permitted;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<bool> requestExactAlarmPermission() async => exact;

  @override
  Future<ScheduleResult> schedule(ScheduledReminder reminder) async {
    // Replaces by id, the way the real notifier does (it cancels first): the
    // same id scheduled twice is one alarm on a phone, never two.
    scheduled
      ..removeWhere((ScheduledReminder r) => r.id == reminder.id)
      ..add(reminder);
    return ScheduleResult(
      exact ? SchedulePrecision.exact : SchedulePrecision.inexact,
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.removeWhere((ScheduledReminder r) => r.id == id);
  }

  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
    cancelled.addAll(scheduled.map((ScheduledReminder r) => r.id));
    scheduled.clear();
  }

  @override
  Future<List<int>> pendingIds() async =>
      scheduled.map((ScheduledReminder r) => r.id).toList();

  @override
  Future<String?> consumeLaunchPayload() async {
    final String? payload = launchPayload;
    launchPayload = null;
    return payload;
  }

  @override
  Stream<String> get taps => _taps.stream;

  void emitTap(String payload) => _taps.add(payload);

  void dispose() => _taps.close();
}

final class FakePurchaseGateway implements PurchaseGateway {
  /// Whether the bootstrap actually subscribed to the store.
  ///
  /// ⚠️ Asserted on by `test/app/bootstrap/app_bootstrap_test.dart`. The real
  /// `initialise()` had zero callers and two doc comments claiming the
  /// bootstrap awaited it; a purchase therefore never activated and Google
  /// Play refunded it three days later. A boolean is all it takes to notice.
  bool initialised = false;

  @override
  Future<void> initialise() async => initialised = true;
  FakePurchaseGateway({
    this.available = true,
    this.plans = const <SubscriptionPlan>[],
    Entitlement initial = Entitlement.free,
  }) : _current = initial;

  bool available;
  List<SubscriptionPlan> plans;
  Entitlement _current;

  int restoreCount = 0;
  final List<String> bought = <String>[];

  final StreamController<Entitlement> _controller =
      StreamController<Entitlement>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<SubscriptionPlan>> loadPlans() async => plans;

  @override
  Future<void> buy(SubscriptionPlan plan) async {
    bought.add(plan.id);
    emit(Entitlement(status: EntitlementStatus.proActive, productId: plan.id));
  }

  @override
  Future<void> restore() async {
    restoreCount++;
    final Object? failure = restoreFailure;
    if (failure != null) throw failure;
  }

  /// Thrown by [restore], the way a store that could not answer throws.
  Object? restoreFailure;

  @override
  Stream<Entitlement> get entitlements => _controller.stream;

  @override
  Entitlement get current => _current;

  void emit(Entitlement entitlement) {
    _current = entitlement;
    _controller.add(entitlement);
  }

  @override
  Future<void> dispose() async => _controller.close();
}

/// Records the store pages the app asked to open, instead of leaving it.
final class FakeStorePageOpener implements StorePageOpener {
  final List<Uri> opened = <Uri>[];

  /// False plays a device where nothing can open the page.
  bool opens = true;

  @override
  Future<bool> open(Uri page) async {
    opened.add(page);
    return opens;
  }
}

/// An in-memory task store.
///
/// ⚠️ Flow tests use this rather than a real drift database, and the reason is
/// mechanical rather than stylistic: `testWidgets` runs inside `FakeAsync`,
/// where no real timer fires. Drift closes its query streams through a
/// zero-duration timer and `close()` waits on work that needs the real event
/// loop, so a database opened in a widget test either reports "a Timer is still
/// pending" or deadlocks the isolate outright — a hang no test timeout can
/// interrupt. The database has its own eighty tests on the Dart VM, where those
/// constraints do not apply.
final class FakeTaskRepository implements TaskRepository {
  final Map<String, Task> _tasks = <String, Task>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  int _nextNotificationId = 1;

  List<Task> get all => _tasks.values.toList();

  void seed(Iterable<Task> tasks) {
    for (final Task task in tasks) {
      _tasks[task.id] = task;
    }
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  List<Task> _sorted(Iterable<Task> tasks) {
    final List<Task> list = tasks.toList()
      ..sort((Task a, Task b) {
        final TaskDue? da = a.due;
        final TaskDue? db = b.due;
        if (da == null && db == null) return a.sortOrder.compareTo(b.sortOrder);
        if (da == null) return 1;
        if (db == null) return -1;
        final int byDate = da.date.compareTo(db.date);
        if (byDate != 0) return byDate;
        final int am = da.time?.minuteOfDay ?? -1;
        final int bm = db.time?.minuteOfDay ?? -1;
        return am.compareTo(bm);
      });
    return list;
  }

  @override
  Stream<List<Task>> watchToday(LocalDate today) => _watch<List<Task>>(
    () => _sorted(
      _tasks.values.where(
        (Task t) =>
            !t.completed && (t.due == null || !t.due!.date.isAfter(today)),
      ),
    ),
  );

  @override
  Stream<List<TaskGroup>> watchUpcoming(LocalDate today) =>
      _watch<List<TaskGroup>>(
        () => TaskGroup.groupByDate(
          _sorted(
            _tasks.values.where(
              (Task t) => !t.completed && (t.due?.date.isAfter(today) ?? false),
            ),
          ),
          today: today,
        ),
      );

  @override
  Stream<List<TaskGroup>> watchCompleted(LocalDate today, {int limit = 200}) =>
      _watch<List<TaskGroup>>(
        () => TaskGroup.groupByCompletion(
          _tasks.values.where((Task t) => t.completed).toList(),
          today: today,
        ),
      );

  @override
  Stream<List<Task>> watchSomeday() => _watch<List<Task>>(
    () => _sorted(_tasks.values.where((Task t) => t.due == null)),
  );

  @override
  Stream<List<Task>> watchSearch(String query, {int limit = 100}) {
    final String needle = query.toLowerCase();
    return _watch<List<Task>>(
      () => _sorted(
        _tasks.values.where((Task t) => t.title.toLowerCase().contains(needle)),
      ).take(limit).toList(),
    );
  }

  @override
  Stream<Task?> watchById(String id) => _watch<Task?>(() => _tasks[id]);

  @override
  Future<Task?> findById(String id) async => _tasks[id];

  @override
  Future<List<Task>> pendingReminders(
    LocalDateTime from, {
    int limit = 64,
  }) async => allSchedulableSync(from).take(limit).toList();

  @override
  Future<List<Task>> allSchedulable(LocalDateTime from) async =>
      allSchedulableSync(from);

  List<Task> allSchedulableSync(LocalDateTime from) {
    final List<Task> due =
        _tasks.values
            .where(
              (Task t) =>
                  !t.completed &&
                  t.reminder.enabled &&
                  (t.reminder.at?.isAfter(from) ?? false),
            )
            .toList()
          ..sort((Task a, Task b) => a.reminder.at!.compareTo(b.reminder.at!));
    return due;
  }

  @override
  Future<List<Task>> saveDrafts(
    List<TaskDraft> drafts, {
    required String captureId,
    required int allDayReminderMinute,
  }) async {
    final List<Task> saved = <Task>[
      for (final TaskDraft draft in drafts)
        _fromDraft(
          draft,
          captureId: captureId,
          allDayMinute: allDayReminderMinute,
        ),
    ];
    for (final Task task in saved) {
      _tasks[task.id] = task;
    }
    _emit();
    return saved;
  }

  @override
  Future<Task> create(
    TaskDraft draft, {
    required int allDayReminderMinute,
  }) async {
    final Task task = _fromDraft(draft, allDayMinute: allDayReminderMinute);
    _tasks[task.id] = task;
    _emit();
    return task;
  }

  Task _fromDraft(
    TaskDraft draft, {
    String? captureId,
    required int allDayMinute,
  }) {
    final DateTime now = DateTime.utc(2026, 3, 11, 5);
    final TaskDue? due = draft.date == null
        ? null
        : TaskDue(date: draft.date!, time: draft.time);
    return Task(
      id: draft.draftId,
      title: draft.title,
      createdAt: now,
      updatedAt: now,
      due: due,
      source: draft.source,
      sourceTranscript: draft.sourceTranscript,
      captureId: captureId,
      reminder: due == null
          ? TaskReminder.none
          : TaskReminder(
              enabled: draft.hasReminder,
              at: due.resolve(allDayMinute: allDayMinute),
              notificationId: _nextNotificationId++,
            ),
    );
  }

  @override
  Future<Task> update(Task task) async {
    _tasks[task.id] = task;
    _emit();
    return task;
  }

  @override
  Future<void> setCompleted(String id, {required bool completed}) async {
    final Task? task = _tasks[id];
    if (task == null) return;
    _tasks[id] = task.copyWith(
      completed: completed,
      completedAt: completed ? DateTime.utc(2026, 3, 11, 5) : null,
      clearCompletedAt: !completed,
    );
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _tasks.remove(id);
    _emit();
  }

  @override
  Future<void> deleteAll() async {
    _tasks.clear();
    _emit();
  }

  @override
  Stream<TaskStats> watchStats(LocalDate today) => _watch<TaskStats>(() {
    final int completed = _tasks.values.where((Task t) => t.completed).length;
    return TaskStats(
      pending: _tasks.values.where((Task t) => !t.completed).length,
      completedTotal: completed,
      completedThisWeek: completed,
      streakDays: completed > 0 ? 1 : 0,
      completionsByDay: <int>[0, 0, 0, 0, 0, 0, completed],
    );
  });

  void dispose() => _changes.close();
}

final class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository([this._settings = AppSettings.defaults]);

  AppSettings _settings;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  @override
  Stream<AppSettings> watch() async* {
    yield _settings;
    yield* _controller.stream;
  }

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
    _controller.add(settings);
  }

  void dispose() => _controller.close();
}

final class FakeUsageRepository implements UsageRepository {
  final Map<String, DailyUsage> _days = <String, DailyUsage>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<DailyUsage> watchToday(LocalDate today) async* {
    yield _days[today.toIso()] ?? DailyUsage.empty(today);
    yield* _changes.stream.map(
      (_) => _days[today.toIso()] ?? DailyUsage.empty(today),
    );
  }

  @override
  Future<DailyUsage> read(LocalDate day) async =>
      _days[day.toIso()] ?? DailyUsage.empty(day);

  @override
  Future<void> recordCapture(LocalDate day, {required int taskCount}) async {
    final DailyUsage current = _days[day.toIso()] ?? DailyUsage.empty(day);
    _days[day.toIso()] = DailyUsage(
      day: day,
      captureCount: current.captureCount + 1,
      taskCount: current.taskCount + taskCount,
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> prune(LocalDate today, {int keepDays = 90}) async {
    // The real repository deletes days strictly BEFORE the cutoff, so today
    // survives even `keepDays: 0` — which is what stops "Delete all data"
    // from handing out a fresh free capture.
    final String cutoff = today.addDays(-keepDays).toIso();
    _days.removeWhere((String day, DailyUsage _) => day.compareTo(cutoff) < 0);
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() => _changes.close();
}
