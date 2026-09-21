import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

/// The instant every database test is pinned to: Wednesday 2026-03-11, 10:00
/// local. A midweek date, so "yesterday", "tomorrow" and "this week" are all
/// unambiguous, and nowhere near a month or year boundary that would make a
/// failure ambiguous between a bug and an off-by-one in the fixture.
final DateTime kTestNowLocal = DateTime(2026, 3, 11, 10);

final LocalDate kToday = LocalDate.today(kTestNowLocal);

/// A fresh in-memory database, already through `beforeOpen`.
///
/// `NativeDatabase.memory()` and not a temp file: each test gets an empty,
/// isolated database and nothing is left on disk for the next run to inherit.
AppDatabase openTestDatabase({Clock? clock}) => AppDatabase.forTesting(
  NativeDatabase.memory(),
  clock: clock ?? FixedClock(kTestNowLocal),
);

/// A task row with sensible defaults, so each test names only the one or two
/// columns it is actually about.
TasksCompanion taskRow(
  String id, {
  String title = 'Task',
  String? notes,
  LocalDate? dueDate,
  int? dueMinuteOfDay,
  bool reminderEnabled = false,
  int reminderLeadMinutes = 0,
  LocalDateTime? reminderAtLocal,
  int? notificationId,
  bool completed = false,
  DateTime? completedAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  TaskSource source = TaskSource.manual,
  String? sourceTranscript,
  String? captureId,
  int sortOrder = 0,
}) {
  final DateTime stamp = createdAt ?? kTestNowLocal.toUtc();
  return TasksCompanion(
    id: Value<String>(id),
    title: Value<String>(title),
    titleFolded: Value<String>(foldForSearch(title)),
    notes: Value<String?>(notes),
    dueDate: Value<LocalDate?>(dueDate),
    dueMinuteOfDay: Value<int?>(dueMinuteOfDay),
    reminderEnabled: Value<bool>(reminderEnabled),
    reminderLeadMinutes: Value<int>(reminderLeadMinutes),
    reminderAtLocal: Value<LocalDateTime?>(reminderAtLocal),
    notificationId: Value<int?>(notificationId),
    completed: Value<bool>(completed),
    completedAtUtcMs: Value<DateTime?>(completedAt),
    createdAtUtcMs: Value<DateTime>(stamp),
    updatedAtUtcMs: Value<DateTime>(updatedAt ?? stamp),
    source: Value<String>(source.name),
    sourceTranscript: Value<String?>(sourceTranscript),
    captureId: Value<String?>(captureId),
    sortOrder: Value<int>(sortOrder),
  );
}
