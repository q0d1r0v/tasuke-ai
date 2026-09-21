// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleFoldedMeta = const VerificationMeta(
    'titleFolded',
  );
  @override
  late final GeneratedColumn<String> titleFolded = GeneratedColumn<String>(
    'title_folded',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDate?, String> dueDate =
      GeneratedColumn<String>(
        'due_date',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<LocalDate?>($TasksTable.$converterdueDaten);
  static const VerificationMeta _dueMinuteOfDayMeta = const VerificationMeta(
    'dueMinuteOfDay',
  );
  @override
  late final GeneratedColumn<int> dueMinuteOfDay = GeneratedColumn<int>(
    'due_minute_of_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reminderEnabledMeta = const VerificationMeta(
    'reminderEnabled',
  );
  @override
  late final GeneratedColumn<bool> reminderEnabled = GeneratedColumn<bool>(
    'reminder_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reminder_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant<bool>(false),
  );
  static const VerificationMeta _reminderLeadMinutesMeta =
      const VerificationMeta('reminderLeadMinutes');
  @override
  late final GeneratedColumn<int> reminderLeadMinutes = GeneratedColumn<int>(
    'reminder_lead_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalDateTime?, String>
  reminderAtLocal = GeneratedColumn<String>(
    'reminder_at_local',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<LocalDateTime?>($TasksTable.$converterreminderAtLocaln);
  static const VerificationMeta _notificationIdMeta = const VerificationMeta(
    'notificationId',
  );
  @override
  late final GeneratedColumn<int> notificationId = GeneratedColumn<int>(
    'notification_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant<bool>(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> completedAtUtcMs =
      GeneratedColumn<int>(
        'completed_at_utc_ms',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TasksTable.$convertercompletedAtUtcMsn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAtUtcMs =
      GeneratedColumn<int>(
        'created_at_utc_ms',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TasksTable.$convertercreatedAtUtcMs);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAtUtcMs =
      GeneratedColumn<int>(
        'updated_at_utc_ms',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TasksTable.$converterupdatedAtUtcMs);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTranscriptMeta = const VerificationMeta(
    'sourceTranscript',
  );
  @override
  late final GeneratedColumn<String> sourceTranscript = GeneratedColumn<String>(
    'source_transcript',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captureIdMeta = const VerificationMeta(
    'captureId',
  );
  @override
  late final GeneratedColumn<String> captureId = GeneratedColumn<String>(
    'capture_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    titleFolded,
    notes,
    dueDate,
    dueMinuteOfDay,
    reminderEnabled,
    reminderLeadMinutes,
    reminderAtLocal,
    notificationId,
    completed,
    completedAtUtcMs,
    createdAtUtcMs,
    updatedAtUtcMs,
    source,
    sourceTranscript,
    captureId,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('title_folded')) {
      context.handle(
        _titleFoldedMeta,
        titleFolded.isAcceptableOrUnknown(
          data['title_folded']!,
          _titleFoldedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_titleFoldedMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('due_minute_of_day')) {
      context.handle(
        _dueMinuteOfDayMeta,
        dueMinuteOfDay.isAcceptableOrUnknown(
          data['due_minute_of_day']!,
          _dueMinuteOfDayMeta,
        ),
      );
    }
    if (data.containsKey('reminder_enabled')) {
      context.handle(
        _reminderEnabledMeta,
        reminderEnabled.isAcceptableOrUnknown(
          data['reminder_enabled']!,
          _reminderEnabledMeta,
        ),
      );
    }
    if (data.containsKey('reminder_lead_minutes')) {
      context.handle(
        _reminderLeadMinutesMeta,
        reminderLeadMinutes.isAcceptableOrUnknown(
          data['reminder_lead_minutes']!,
          _reminderLeadMinutesMeta,
        ),
      );
    }
    if (data.containsKey('notification_id')) {
      context.handle(
        _notificationIdMeta,
        notificationId.isAcceptableOrUnknown(
          data['notification_id']!,
          _notificationIdMeta,
        ),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('source_transcript')) {
      context.handle(
        _sourceTranscriptMeta,
        sourceTranscript.isAcceptableOrUnknown(
          data['source_transcript']!,
          _sourceTranscriptMeta,
        ),
      );
    }
    if (data.containsKey('capture_id')) {
      context.handle(
        _captureIdMeta,
        captureId.isAcceptableOrUnknown(data['capture_id']!, _captureIdMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleFolded: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_folded'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      dueDate: $TasksTable.$converterdueDaten.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}due_date'],
        ),
      ),
      dueMinuteOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_minute_of_day'],
      ),
      reminderEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reminder_enabled'],
      )!,
      reminderLeadMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_lead_minutes'],
      )!,
      reminderAtLocal: $TasksTable.$converterreminderAtLocaln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}reminder_at_local'],
        ),
      ),
      notificationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notification_id'],
      ),
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      completedAtUtcMs: $TasksTable.$convertercompletedAtUtcMsn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}completed_at_utc_ms'],
        ),
      ),
      createdAtUtcMs: $TasksTable.$convertercreatedAtUtcMs.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at_utc_ms'],
        )!,
      ),
      updatedAtUtcMs: $TasksTable.$converterupdatedAtUtcMs.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at_utc_ms'],
        )!,
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      sourceTranscript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_transcript'],
      ),
      captureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_id'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static TypeConverter<LocalDate, String> $converterdueDate =
      const LocalDateConverter();
  static TypeConverter<LocalDate?, String?> $converterdueDaten =
      NullAwareTypeConverter.wrap($converterdueDate);
  static TypeConverter<LocalDateTime, String> $converterreminderAtLocal =
      const LocalDateTimeConverter();
  static TypeConverter<LocalDateTime?, String?> $converterreminderAtLocaln =
      NullAwareTypeConverter.wrap($converterreminderAtLocal);
  static TypeConverter<DateTime, int> $convertercompletedAtUtcMs =
      const UtcInstantConverter();
  static TypeConverter<DateTime?, int?> $convertercompletedAtUtcMsn =
      NullAwareTypeConverter.wrap($convertercompletedAtUtcMs);
  static TypeConverter<DateTime, int> $convertercreatedAtUtcMs =
      const UtcInstantConverter();
  static TypeConverter<DateTime, int> $converterupdatedAtUtcMs =
      const UtcInstantConverter();
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  /// A client-generated uuid v4. Not an autoincrement integer: ids are minted
  /// on the Confirm screen before anything is written, so the drafts the user
  /// is editing already carry the identity the rows will have.
  final String id;
  final String title;

  /// [title] lowercased with diacritics stripped, written on every save.
  ///
  /// Search is `LIKE '%needle%'` against this column rather than against
  /// [title], because SQLite's `LIKE` is only case-insensitive for ASCII and
  /// knows nothing about diacritics — "Café" would not match "cafe". Folding
  /// once at write time is also the only way the comparison stays cheap.
  final String titleFolded;
  final String? notes;

  /// Local civil date, `'YYYY-MM-DD'`. Null means the task has no due date at
  /// all, which is a different thing from an all-day task — see
  /// [dueMinuteOfDay].
  final LocalDate? dueDate;

  /// Minutes since local midnight, 0..1439. Null means all-day.
  final int? dueMinuteOfDay;
  final bool reminderEnabled;

  /// Minutes *before* the due time the reminder fires. 0 = at the time.
  final int reminderLeadMinutes;

  /// The resolved civil moment, `'YYYY-MM-DDTHH:MM'`. Denormalised on purpose:
  /// the scheduler's hot query is "the next 64 reminders at or after now",
  /// and one indexed string comparison answers it without recomputing
  /// date + time - lead for every row in the table.
  final LocalDateTime? reminderAtLocal;

  /// The OS alarm slot this task owns.
  ///
  /// ⚠️ Stable for the life of the task. Editing a task must retarget the same
  /// slot, otherwise cancel-then-schedule leaks an alarm and the user gets two
  /// notifications for one task.
  final int? notificationId;
  final bool completed;

  /// UTC epoch ms. Null iff [completed] is false.
  final DateTime? completedAtUtcMs;
  final DateTime createdAtUtcMs;
  final DateTime updatedAtUtcMs;

  /// `TaskSource.name` — `voice` or `manual`. Stored as the enum's name rather
  /// than its index so that reordering the enum cannot silently rewrite
  /// history.
  final String source;

  /// ⚠️ What the user actually said. This is the most sensitive column in the
  /// database: it never leaves the device, never reaches a log (pass it through
  /// `Log.redact`), and never appears in an error message.
  final String? sourceTranscript;

  /// Groups every task produced by one utterance, so "discard all" and a
  /// future undo can act on the batch rather than on rows one at a time.
  final String? captureId;
  final int sortOrder;
  const TaskRow({
    required this.id,
    required this.title,
    required this.titleFolded,
    this.notes,
    this.dueDate,
    this.dueMinuteOfDay,
    required this.reminderEnabled,
    required this.reminderLeadMinutes,
    this.reminderAtLocal,
    this.notificationId,
    required this.completed,
    this.completedAtUtcMs,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
    required this.source,
    this.sourceTranscript,
    this.captureId,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['title_folded'] = Variable<String>(titleFolded);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(
        $TasksTable.$converterdueDaten.toSql(dueDate),
      );
    }
    if (!nullToAbsent || dueMinuteOfDay != null) {
      map['due_minute_of_day'] = Variable<int>(dueMinuteOfDay);
    }
    map['reminder_enabled'] = Variable<bool>(reminderEnabled);
    map['reminder_lead_minutes'] = Variable<int>(reminderLeadMinutes);
    if (!nullToAbsent || reminderAtLocal != null) {
      map['reminder_at_local'] = Variable<String>(
        $TasksTable.$converterreminderAtLocaln.toSql(reminderAtLocal),
      );
    }
    if (!nullToAbsent || notificationId != null) {
      map['notification_id'] = Variable<int>(notificationId);
    }
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || completedAtUtcMs != null) {
      map['completed_at_utc_ms'] = Variable<int>(
        $TasksTable.$convertercompletedAtUtcMsn.toSql(completedAtUtcMs),
      );
    }
    {
      map['created_at_utc_ms'] = Variable<int>(
        $TasksTable.$convertercreatedAtUtcMs.toSql(createdAtUtcMs),
      );
    }
    {
      map['updated_at_utc_ms'] = Variable<int>(
        $TasksTable.$converterupdatedAtUtcMs.toSql(updatedAtUtcMs),
      );
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || sourceTranscript != null) {
      map['source_transcript'] = Variable<String>(sourceTranscript);
    }
    if (!nullToAbsent || captureId != null) {
      map['capture_id'] = Variable<String>(captureId);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      title: Value(title),
      titleFolded: Value(titleFolded),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      dueMinuteOfDay: dueMinuteOfDay == null && nullToAbsent
          ? const Value.absent()
          : Value(dueMinuteOfDay),
      reminderEnabled: Value(reminderEnabled),
      reminderLeadMinutes: Value(reminderLeadMinutes),
      reminderAtLocal: reminderAtLocal == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderAtLocal),
      notificationId: notificationId == null && nullToAbsent
          ? const Value.absent()
          : Value(notificationId),
      completed: Value(completed),
      completedAtUtcMs: completedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtcMs),
      createdAtUtcMs: Value(createdAtUtcMs),
      updatedAtUtcMs: Value(updatedAtUtcMs),
      source: Value(source),
      sourceTranscript: sourceTranscript == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceTranscript),
      captureId: captureId == null && nullToAbsent
          ? const Value.absent()
          : Value(captureId),
      sortOrder: Value(sortOrder),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      titleFolded: serializer.fromJson<String>(json['titleFolded']),
      notes: serializer.fromJson<String?>(json['notes']),
      dueDate: serializer.fromJson<LocalDate?>(json['dueDate']),
      dueMinuteOfDay: serializer.fromJson<int?>(json['dueMinuteOfDay']),
      reminderEnabled: serializer.fromJson<bool>(json['reminderEnabled']),
      reminderLeadMinutes: serializer.fromJson<int>(
        json['reminderLeadMinutes'],
      ),
      reminderAtLocal: serializer.fromJson<LocalDateTime?>(
        json['reminderAtLocal'],
      ),
      notificationId: serializer.fromJson<int?>(json['notificationId']),
      completed: serializer.fromJson<bool>(json['completed']),
      completedAtUtcMs: serializer.fromJson<DateTime?>(
        json['completedAtUtcMs'],
      ),
      createdAtUtcMs: serializer.fromJson<DateTime>(json['createdAtUtcMs']),
      updatedAtUtcMs: serializer.fromJson<DateTime>(json['updatedAtUtcMs']),
      source: serializer.fromJson<String>(json['source']),
      sourceTranscript: serializer.fromJson<String?>(json['sourceTranscript']),
      captureId: serializer.fromJson<String?>(json['captureId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'titleFolded': serializer.toJson<String>(titleFolded),
      'notes': serializer.toJson<String?>(notes),
      'dueDate': serializer.toJson<LocalDate?>(dueDate),
      'dueMinuteOfDay': serializer.toJson<int?>(dueMinuteOfDay),
      'reminderEnabled': serializer.toJson<bool>(reminderEnabled),
      'reminderLeadMinutes': serializer.toJson<int>(reminderLeadMinutes),
      'reminderAtLocal': serializer.toJson<LocalDateTime?>(reminderAtLocal),
      'notificationId': serializer.toJson<int?>(notificationId),
      'completed': serializer.toJson<bool>(completed),
      'completedAtUtcMs': serializer.toJson<DateTime?>(completedAtUtcMs),
      'createdAtUtcMs': serializer.toJson<DateTime>(createdAtUtcMs),
      'updatedAtUtcMs': serializer.toJson<DateTime>(updatedAtUtcMs),
      'source': serializer.toJson<String>(source),
      'sourceTranscript': serializer.toJson<String?>(sourceTranscript),
      'captureId': serializer.toJson<String?>(captureId),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  TaskRow copyWith({
    String? id,
    String? title,
    String? titleFolded,
    Value<String?> notes = const Value.absent(),
    Value<LocalDate?> dueDate = const Value.absent(),
    Value<int?> dueMinuteOfDay = const Value.absent(),
    bool? reminderEnabled,
    int? reminderLeadMinutes,
    Value<LocalDateTime?> reminderAtLocal = const Value.absent(),
    Value<int?> notificationId = const Value.absent(),
    bool? completed,
    Value<DateTime?> completedAtUtcMs = const Value.absent(),
    DateTime? createdAtUtcMs,
    DateTime? updatedAtUtcMs,
    String? source,
    Value<String?> sourceTranscript = const Value.absent(),
    Value<String?> captureId = const Value.absent(),
    int? sortOrder,
  }) => TaskRow(
    id: id ?? this.id,
    title: title ?? this.title,
    titleFolded: titleFolded ?? this.titleFolded,
    notes: notes.present ? notes.value : this.notes,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    dueMinuteOfDay: dueMinuteOfDay.present
        ? dueMinuteOfDay.value
        : this.dueMinuteOfDay,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
    reminderAtLocal: reminderAtLocal.present
        ? reminderAtLocal.value
        : this.reminderAtLocal,
    notificationId: notificationId.present
        ? notificationId.value
        : this.notificationId,
    completed: completed ?? this.completed,
    completedAtUtcMs: completedAtUtcMs.present
        ? completedAtUtcMs.value
        : this.completedAtUtcMs,
    createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
    source: source ?? this.source,
    sourceTranscript: sourceTranscript.present
        ? sourceTranscript.value
        : this.sourceTranscript,
    captureId: captureId.present ? captureId.value : this.captureId,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      titleFolded: data.titleFolded.present
          ? data.titleFolded.value
          : this.titleFolded,
      notes: data.notes.present ? data.notes.value : this.notes,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      dueMinuteOfDay: data.dueMinuteOfDay.present
          ? data.dueMinuteOfDay.value
          : this.dueMinuteOfDay,
      reminderEnabled: data.reminderEnabled.present
          ? data.reminderEnabled.value
          : this.reminderEnabled,
      reminderLeadMinutes: data.reminderLeadMinutes.present
          ? data.reminderLeadMinutes.value
          : this.reminderLeadMinutes,
      reminderAtLocal: data.reminderAtLocal.present
          ? data.reminderAtLocal.value
          : this.reminderAtLocal,
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      completed: data.completed.present ? data.completed.value : this.completed,
      completedAtUtcMs: data.completedAtUtcMs.present
          ? data.completedAtUtcMs.value
          : this.completedAtUtcMs,
      createdAtUtcMs: data.createdAtUtcMs.present
          ? data.createdAtUtcMs.value
          : this.createdAtUtcMs,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
      source: data.source.present ? data.source.value : this.source,
      sourceTranscript: data.sourceTranscript.present
          ? data.sourceTranscript.value
          : this.sourceTranscript,
      captureId: data.captureId.present ? data.captureId.value : this.captureId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('titleFolded: $titleFolded, ')
          ..write('notes: $notes, ')
          ..write('dueDate: $dueDate, ')
          ..write('dueMinuteOfDay: $dueMinuteOfDay, ')
          ..write('reminderEnabled: $reminderEnabled, ')
          ..write('reminderLeadMinutes: $reminderLeadMinutes, ')
          ..write('reminderAtLocal: $reminderAtLocal, ')
          ..write('notificationId: $notificationId, ')
          ..write('completed: $completed, ')
          ..write('completedAtUtcMs: $completedAtUtcMs, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('source: $source, ')
          ..write('sourceTranscript: $sourceTranscript, ')
          ..write('captureId: $captureId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    titleFolded,
    notes,
    dueDate,
    dueMinuteOfDay,
    reminderEnabled,
    reminderLeadMinutes,
    reminderAtLocal,
    notificationId,
    completed,
    completedAtUtcMs,
    createdAtUtcMs,
    updatedAtUtcMs,
    source,
    sourceTranscript,
    captureId,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.titleFolded == this.titleFolded &&
          other.notes == this.notes &&
          other.dueDate == this.dueDate &&
          other.dueMinuteOfDay == this.dueMinuteOfDay &&
          other.reminderEnabled == this.reminderEnabled &&
          other.reminderLeadMinutes == this.reminderLeadMinutes &&
          other.reminderAtLocal == this.reminderAtLocal &&
          other.notificationId == this.notificationId &&
          other.completed == this.completed &&
          other.completedAtUtcMs == this.completedAtUtcMs &&
          other.createdAtUtcMs == this.createdAtUtcMs &&
          other.updatedAtUtcMs == this.updatedAtUtcMs &&
          other.source == this.source &&
          other.sourceTranscript == this.sourceTranscript &&
          other.captureId == this.captureId &&
          other.sortOrder == this.sortOrder);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> titleFolded;
  final Value<String?> notes;
  final Value<LocalDate?> dueDate;
  final Value<int?> dueMinuteOfDay;
  final Value<bool> reminderEnabled;
  final Value<int> reminderLeadMinutes;
  final Value<LocalDateTime?> reminderAtLocal;
  final Value<int?> notificationId;
  final Value<bool> completed;
  final Value<DateTime?> completedAtUtcMs;
  final Value<DateTime> createdAtUtcMs;
  final Value<DateTime> updatedAtUtcMs;
  final Value<String> source;
  final Value<String?> sourceTranscript;
  final Value<String?> captureId;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.titleFolded = const Value.absent(),
    this.notes = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.dueMinuteOfDay = const Value.absent(),
    this.reminderEnabled = const Value.absent(),
    this.reminderLeadMinutes = const Value.absent(),
    this.reminderAtLocal = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.completed = const Value.absent(),
    this.completedAtUtcMs = const Value.absent(),
    this.createdAtUtcMs = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceTranscript = const Value.absent(),
    this.captureId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String title,
    required String titleFolded,
    this.notes = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.dueMinuteOfDay = const Value.absent(),
    this.reminderEnabled = const Value.absent(),
    this.reminderLeadMinutes = const Value.absent(),
    this.reminderAtLocal = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.completed = const Value.absent(),
    this.completedAtUtcMs = const Value.absent(),
    required DateTime createdAtUtcMs,
    required DateTime updatedAtUtcMs,
    required String source,
    this.sourceTranscript = const Value.absent(),
    this.captureId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       titleFolded = Value(titleFolded),
       createdAtUtcMs = Value(createdAtUtcMs),
       updatedAtUtcMs = Value(updatedAtUtcMs),
       source = Value(source);
  static Insertable<TaskRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? titleFolded,
    Expression<String>? notes,
    Expression<String>? dueDate,
    Expression<int>? dueMinuteOfDay,
    Expression<bool>? reminderEnabled,
    Expression<int>? reminderLeadMinutes,
    Expression<String>? reminderAtLocal,
    Expression<int>? notificationId,
    Expression<bool>? completed,
    Expression<int>? completedAtUtcMs,
    Expression<int>? createdAtUtcMs,
    Expression<int>? updatedAtUtcMs,
    Expression<String>? source,
    Expression<String>? sourceTranscript,
    Expression<String>? captureId,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (titleFolded != null) 'title_folded': titleFolded,
      if (notes != null) 'notes': notes,
      if (dueDate != null) 'due_date': dueDate,
      if (dueMinuteOfDay != null) 'due_minute_of_day': dueMinuteOfDay,
      if (reminderEnabled != null) 'reminder_enabled': reminderEnabled,
      if (reminderLeadMinutes != null)
        'reminder_lead_minutes': reminderLeadMinutes,
      if (reminderAtLocal != null) 'reminder_at_local': reminderAtLocal,
      if (notificationId != null) 'notification_id': notificationId,
      if (completed != null) 'completed': completed,
      if (completedAtUtcMs != null) 'completed_at_utc_ms': completedAtUtcMs,
      if (createdAtUtcMs != null) 'created_at_utc_ms': createdAtUtcMs,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (source != null) 'source': source,
      if (sourceTranscript != null) 'source_transcript': sourceTranscript,
      if (captureId != null) 'capture_id': captureId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? titleFolded,
    Value<String?>? notes,
    Value<LocalDate?>? dueDate,
    Value<int?>? dueMinuteOfDay,
    Value<bool>? reminderEnabled,
    Value<int>? reminderLeadMinutes,
    Value<LocalDateTime?>? reminderAtLocal,
    Value<int?>? notificationId,
    Value<bool>? completed,
    Value<DateTime?>? completedAtUtcMs,
    Value<DateTime>? createdAtUtcMs,
    Value<DateTime>? updatedAtUtcMs,
    Value<String>? source,
    Value<String?>? sourceTranscript,
    Value<String?>? captureId,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      titleFolded: titleFolded ?? this.titleFolded,
      notes: notes ?? this.notes,
      dueDate: dueDate ?? this.dueDate,
      dueMinuteOfDay: dueMinuteOfDay ?? this.dueMinuteOfDay,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
      reminderAtLocal: reminderAtLocal ?? this.reminderAtLocal,
      notificationId: notificationId ?? this.notificationId,
      completed: completed ?? this.completed,
      completedAtUtcMs: completedAtUtcMs ?? this.completedAtUtcMs,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      source: source ?? this.source,
      sourceTranscript: sourceTranscript ?? this.sourceTranscript,
      captureId: captureId ?? this.captureId,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleFolded.present) {
      map['title_folded'] = Variable<String>(titleFolded.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(
        $TasksTable.$converterdueDaten.toSql(dueDate.value),
      );
    }
    if (dueMinuteOfDay.present) {
      map['due_minute_of_day'] = Variable<int>(dueMinuteOfDay.value);
    }
    if (reminderEnabled.present) {
      map['reminder_enabled'] = Variable<bool>(reminderEnabled.value);
    }
    if (reminderLeadMinutes.present) {
      map['reminder_lead_minutes'] = Variable<int>(reminderLeadMinutes.value);
    }
    if (reminderAtLocal.present) {
      map['reminder_at_local'] = Variable<String>(
        $TasksTable.$converterreminderAtLocaln.toSql(reminderAtLocal.value),
      );
    }
    if (notificationId.present) {
      map['notification_id'] = Variable<int>(notificationId.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (completedAtUtcMs.present) {
      map['completed_at_utc_ms'] = Variable<int>(
        $TasksTable.$convertercompletedAtUtcMsn.toSql(completedAtUtcMs.value),
      );
    }
    if (createdAtUtcMs.present) {
      map['created_at_utc_ms'] = Variable<int>(
        $TasksTable.$convertercreatedAtUtcMs.toSql(createdAtUtcMs.value),
      );
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(
        $TasksTable.$converterupdatedAtUtcMs.toSql(updatedAtUtcMs.value),
      );
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceTranscript.present) {
      map['source_transcript'] = Variable<String>(sourceTranscript.value);
    }
    if (captureId.present) {
      map['capture_id'] = Variable<String>(captureId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('titleFolded: $titleFolded, ')
          ..write('notes: $notes, ')
          ..write('dueDate: $dueDate, ')
          ..write('dueMinuteOfDay: $dueMinuteOfDay, ')
          ..write('reminderEnabled: $reminderEnabled, ')
          ..write('reminderLeadMinutes: $reminderLeadMinutes, ')
          ..write('reminderAtLocal: $reminderAtLocal, ')
          ..write('notificationId: $notificationId, ')
          ..write('completed: $completed, ')
          ..write('completedAtUtcMs: $completedAtUtcMs, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('source: $source, ')
          ..write('sourceTranscript: $sourceTranscript, ')
          ..write('captureId: $captureId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsEntriesTable extends SettingsEntries
    with TableInfo<$SettingsEntriesTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAtUtcMs =
      GeneratedColumn<int>(
        'updated_at_utc_ms',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SettingsEntriesTable.$converterupdatedAtUtcMs);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtUtcMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtUtcMs: $SettingsEntriesTable.$converterupdatedAtUtcMs.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at_utc_ms'],
        )!,
      ),
    );
  }

  @override
  $SettingsEntriesTable createAlias(String alias) {
    return $SettingsEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterupdatedAtUtcMs =
      const UtcInstantConverter();
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;

  /// A JSON-encoded scalar — `true`, `540`, `"en"`. JSON rather than a bare
  /// string so that `false` and `"false"` stay distinguishable.
  final String value;
  final DateTime updatedAtUtcMs;
  const SettingRow({
    required this.key,
    required this.value,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    {
      map['updated_at_utc_ms'] = Variable<int>(
        $SettingsEntriesTable.$converterupdatedAtUtcMs.toSql(updatedAtUtcMs),
      );
    }
    return map;
  }

  SettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return SettingsEntriesCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtUtcMs: serializer.fromJson<DateTime>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAtUtcMs': serializer.toJson<DateTime>(updatedAtUtcMs),
    };
  }

  SettingRow copyWith({String? key, String? value, DateTime? updatedAtUtcMs}) =>
      SettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      );
  SettingRow copyWithCompanion(SettingsEntriesCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class SettingsEntriesCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAtUtcMs;
  final Value<int> rowid;
  const SettingsEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsEntriesCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAtUtcMs,
    Value<int>? rowid,
  }) {
    return SettingsEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(
        $SettingsEntriesTable.$converterupdatedAtUtcMs.toSql(
          updatedAtUtcMs.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsageDaysTable extends UsageDays
    with TableInfo<$UsageDaysTable, UsageDayRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsageDaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captureCountMeta = const VerificationMeta(
    'captureCount',
  );
  @override
  late final GeneratedColumn<int> captureCount = GeneratedColumn<int>(
    'capture_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  static const VerificationMeta _taskCountMeta = const VerificationMeta(
    'taskCount',
  );
  @override
  late final GeneratedColumn<int> taskCount = GeneratedColumn<int>(
    'task_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  @override
  List<GeneratedColumn> get $columns => [day, captureCount, taskCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'usage_days';
  @override
  VerificationContext validateIntegrity(
    Insertable<UsageDayRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('capture_count')) {
      context.handle(
        _captureCountMeta,
        captureCount.isAcceptableOrUnknown(
          data['capture_count']!,
          _captureCountMeta,
        ),
      );
    }
    if (data.containsKey('task_count')) {
      context.handle(
        _taskCountMeta,
        taskCount.isAcceptableOrUnknown(data['task_count']!, _taskCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day};
  @override
  UsageDayRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsageDayRow(
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      captureCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capture_count'],
      )!,
      taskCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}task_count'],
      )!,
    );
  }

  @override
  $UsageDaysTable createAlias(String alias) {
    return $UsageDaysTable(attachedDatabase, alias);
  }
}

class UsageDayRow extends DataClass implements Insertable<UsageDayRow> {
  /// `'YYYY-MM-DD'`, local.
  final String day;

  /// ⚠️ Only **successful** captures are counted. A capture that hit silence
  /// or failed to transcribe must not consume quota — charging for those is
  /// the complaint users actually file.
  final int captureCount;
  final int taskCount;
  const UsageDayRow({
    required this.day,
    required this.captureCount,
    required this.taskCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['capture_count'] = Variable<int>(captureCount);
    map['task_count'] = Variable<int>(taskCount);
    return map;
  }

  UsageDaysCompanion toCompanion(bool nullToAbsent) {
    return UsageDaysCompanion(
      day: Value(day),
      captureCount: Value(captureCount),
      taskCount: Value(taskCount),
    );
  }

  factory UsageDayRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsageDayRow(
      day: serializer.fromJson<String>(json['day']),
      captureCount: serializer.fromJson<int>(json['captureCount']),
      taskCount: serializer.fromJson<int>(json['taskCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'captureCount': serializer.toJson<int>(captureCount),
      'taskCount': serializer.toJson<int>(taskCount),
    };
  }

  UsageDayRow copyWith({String? day, int? captureCount, int? taskCount}) =>
      UsageDayRow(
        day: day ?? this.day,
        captureCount: captureCount ?? this.captureCount,
        taskCount: taskCount ?? this.taskCount,
      );
  UsageDayRow copyWithCompanion(UsageDaysCompanion data) {
    return UsageDayRow(
      day: data.day.present ? data.day.value : this.day,
      captureCount: data.captureCount.present
          ? data.captureCount.value
          : this.captureCount,
      taskCount: data.taskCount.present ? data.taskCount.value : this.taskCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsageDayRow(')
          ..write('day: $day, ')
          ..write('captureCount: $captureCount, ')
          ..write('taskCount: $taskCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, captureCount, taskCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsageDayRow &&
          other.day == this.day &&
          other.captureCount == this.captureCount &&
          other.taskCount == this.taskCount);
}

class UsageDaysCompanion extends UpdateCompanion<UsageDayRow> {
  final Value<String> day;
  final Value<int> captureCount;
  final Value<int> taskCount;
  final Value<int> rowid;
  const UsageDaysCompanion({
    this.day = const Value.absent(),
    this.captureCount = const Value.absent(),
    this.taskCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsageDaysCompanion.insert({
    required String day,
    this.captureCount = const Value.absent(),
    this.taskCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : day = Value(day);
  static Insertable<UsageDayRow> custom({
    Expression<String>? day,
    Expression<int>? captureCount,
    Expression<int>? taskCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (captureCount != null) 'capture_count': captureCount,
      if (taskCount != null) 'task_count': taskCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsageDaysCompanion copyWith({
    Value<String>? day,
    Value<int>? captureCount,
    Value<int>? taskCount,
    Value<int>? rowid,
  }) {
    return UsageDaysCompanion(
      day: day ?? this.day,
      captureCount: captureCount ?? this.captureCount,
      taskCount: taskCount ?? this.taskCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (captureCount.present) {
      map['capture_count'] = Variable<int>(captureCount.value);
    }
    if (taskCount.present) {
      map['task_count'] = Variable<int>(taskCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsageDaysCompanion(')
          ..write('day: $day, ')
          ..write('captureCount: $captureCount, ')
          ..write('taskCount: $taskCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $SettingsEntriesTable settingsEntries = $SettingsEntriesTable(
    this,
  );
  late final $UsageDaysTable usageDays = $UsageDaysTable(this);
  late final Index tasksPendingDue = Index(
    'tasks_pending_due',
    'CREATE INDEX tasks_pending_due ON tasks (completed, due_date, due_minute_of_day)',
  );
  late final Index tasksDueDate = Index(
    'tasks_due_date',
    'CREATE INDEX tasks_due_date ON tasks (due_date)',
  );
  late final Index tasksReminderAt = Index(
    'tasks_reminder_at',
    'CREATE INDEX tasks_reminder_at ON tasks (completed, reminder_enabled, reminder_at_local)',
  );
  late final Index tasksCompletedAt = Index(
    'tasks_completed_at',
    'CREATE INDEX tasks_completed_at ON tasks (completed_at_utc_ms)',
  );
  late final TasksDao tasksDao = TasksDao(this as AppDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  late final UsageDao usageDao = UsageDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tasks,
    settingsEntries,
    usageDays,
    tasksPendingDue,
    tasksDueDate,
    tasksReminderAt,
    tasksCompletedAt,
  ];
}

typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  required String title,
  required String titleFolded,
  Value<String?> notes,
  Value<LocalDate?> dueDate,
  Value<int?> dueMinuteOfDay,
  Value<bool> reminderEnabled,
  Value<int> reminderLeadMinutes,
  Value<LocalDateTime?> reminderAtLocal,
  Value<int?> notificationId,
  Value<bool> completed,
  Value<DateTime?> completedAtUtcMs,
  required DateTime createdAtUtcMs,
  required DateTime updatedAtUtcMs,
  required String source,
  Value<String?> sourceTranscript,
  Value<String?> captureId,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> titleFolded,
  Value<String?> notes,
  Value<LocalDate?> dueDate,
  Value<int?> dueMinuteOfDay,
  Value<bool> reminderEnabled,
  Value<int> reminderLeadMinutes,
  Value<LocalDateTime?> reminderAtLocal,
  Value<int?> notificationId,
  Value<bool> completed,
  Value<DateTime?> completedAtUtcMs,
  Value<DateTime> createdAtUtcMs,
  Value<DateTime> updatedAtUtcMs,
  Value<String> source,
  Value<String?> sourceTranscript,
  Value<String?> captureId,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleFolded => $composableBuilder(
    column: $table.titleFolded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDate?, LocalDate, String> get dueDate =>
      $composableBuilder(
        column: $table.dueDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get dueMinuteOfDay => $composableBuilder(
    column: $table.dueMinuteOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reminderEnabled => $composableBuilder(
    column: $table.reminderEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderLeadMinutes => $composableBuilder(
    column: $table.reminderLeadMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalDateTime?, LocalDateTime, String>
  get reminderAtLocal => $composableBuilder(
    column: $table.reminderAtLocal,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get completedAtUtcMs => $composableBuilder(
    column: $table.completedAtUtcMs,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAtUtcMs =>
      $composableBuilder(
        column: $table.createdAtUtcMs,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAtUtcMs =>
      $composableBuilder(
        column: $table.updatedAtUtcMs,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceTranscript => $composableBuilder(
    column: $table.sourceTranscript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureId => $composableBuilder(
    column: $table.captureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleFolded => $composableBuilder(
    column: $table.titleFolded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueMinuteOfDay => $composableBuilder(
    column: $table.dueMinuteOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reminderEnabled => $composableBuilder(
    column: $table.reminderEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderLeadMinutes => $composableBuilder(
    column: $table.reminderLeadMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminderAtLocal => $composableBuilder(
    column: $table.reminderAtLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtUtcMs => $composableBuilder(
    column: $table.completedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceTranscript => $composableBuilder(
    column: $table.sourceTranscript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureId => $composableBuilder(
    column: $table.captureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleFolded => $composableBuilder(
    column: $table.titleFolded,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalDate?, String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<int> get dueMinuteOfDay => $composableBuilder(
    column: $table.dueMinuteOfDay,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reminderEnabled => $composableBuilder(
    column: $table.reminderEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderLeadMinutes => $composableBuilder(
    column: $table.reminderLeadMinutes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<LocalDateTime?, String>
  get reminderAtLocal => $composableBuilder(
    column: $table.reminderAtLocal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get completedAtUtcMs =>
      $composableBuilder(
        column: $table.completedAtUtcMs,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAtUtcMs =>
      $composableBuilder(
        column: $table.createdAtUtcMs,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAtUtcMs =>
      $composableBuilder(
        column: $table.updatedAtUtcMs,
        builder: (column) => column,
      );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceTranscript => $composableBuilder(
    column: $table.sourceTranscript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get captureId =>
      $composableBuilder(column: $table.captureId, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, BaseReferences<_$AppDatabase, $TasksTable, TaskRow>),
          TaskRow,
          PrefetchHooks Function()
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleFolded = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<LocalDate?> dueDate = const Value.absent(),
                Value<int?> dueMinuteOfDay = const Value.absent(),
                Value<bool> reminderEnabled = const Value.absent(),
                Value<int> reminderLeadMinutes = const Value.absent(),
                Value<LocalDateTime?> reminderAtLocal = const Value.absent(),
                Value<int?> notificationId = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime?> completedAtUtcMs = const Value.absent(),
                Value<DateTime> createdAtUtcMs = const Value.absent(),
                Value<DateTime> updatedAtUtcMs = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceTranscript = const Value.absent(),
                Value<String?> captureId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                title: title,
                titleFolded: titleFolded,
                notes: notes,
                dueDate: dueDate,
                dueMinuteOfDay: dueMinuteOfDay,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: reminderLeadMinutes,
                reminderAtLocal: reminderAtLocal,
                notificationId: notificationId,
                completed: completed,
                completedAtUtcMs: completedAtUtcMs,
                createdAtUtcMs: createdAtUtcMs,
                updatedAtUtcMs: updatedAtUtcMs,
                source: source,
                sourceTranscript: sourceTranscript,
                captureId: captureId,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String titleFolded,
                Value<String?> notes = const Value.absent(),
                Value<LocalDate?> dueDate = const Value.absent(),
                Value<int?> dueMinuteOfDay = const Value.absent(),
                Value<bool> reminderEnabled = const Value.absent(),
                Value<int> reminderLeadMinutes = const Value.absent(),
                Value<LocalDateTime?> reminderAtLocal = const Value.absent(),
                Value<int?> notificationId = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime?> completedAtUtcMs = const Value.absent(),
                required DateTime createdAtUtcMs,
                required DateTime updatedAtUtcMs,
                required String source,
                Value<String?> sourceTranscript = const Value.absent(),
                Value<String?> captureId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                title: title,
                titleFolded: titleFolded,
                notes: notes,
                dueDate: dueDate,
                dueMinuteOfDay: dueMinuteOfDay,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: reminderLeadMinutes,
                reminderAtLocal: reminderAtLocal,
                notificationId: notificationId,
                completed: completed,
                completedAtUtcMs: completedAtUtcMs,
                createdAtUtcMs: createdAtUtcMs,
                updatedAtUtcMs: updatedAtUtcMs,
                source: source,
                sourceTranscript: sourceTranscript,
                captureId: captureId,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, TaskRow>(table),
                  BaseReferences<_$AppDatabase, $TasksTable, TaskRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, BaseReferences<_$AppDatabase, $TasksTable, TaskRow>),
      TaskRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsEntriesTableCreateCompanionBuilder =
    SettingsEntriesCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAtUtcMs,
      Value<int> rowid,
    });
typedef $$SettingsEntriesTableUpdateCompanionBuilder =
    SettingsEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAtUtcMs,
      Value<int> rowid,
    });

class $$SettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsEntriesTable> {
  $$SettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAtUtcMs =>
      $composableBuilder(
        column: $table.updatedAtUtcMs,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsEntriesTable> {
  $$SettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsEntriesTable> {
  $$SettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAtUtcMs =>
      $composableBuilder(
        column: $table.updatedAtUtcMs,
        builder: (column) => column,
      );
}

class $$SettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsEntriesTable,
          SettingRow,
          $$SettingsEntriesTableFilterComposer,
          $$SettingsEntriesTableOrderingComposer,
          $$SettingsEntriesTableAnnotationComposer,
          $$SettingsEntriesTableCreateCompanionBuilder,
          $$SettingsEntriesTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsEntriesTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsEntriesTableTableManager(
    _$AppDatabase db,
    $SettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsEntriesCompanion(
                key: key,
                value: value,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => SettingsEntriesCompanion.insert(
                key: key,
                value: value,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsEntriesTable, SettingRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SettingsEntriesTable,
                    SettingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsEntriesTable,
      SettingRow,
      $$SettingsEntriesTableFilterComposer,
      $$SettingsEntriesTableOrderingComposer,
      $$SettingsEntriesTableAnnotationComposer,
      $$SettingsEntriesTableCreateCompanionBuilder,
      $$SettingsEntriesTableUpdateCompanionBuilder,
      (
        SettingRow,
        BaseReferences<_$AppDatabase, $SettingsEntriesTable, SettingRow>,
      ),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$UsageDaysTableCreateCompanionBuilder = UsageDaysCompanion Function({
  required String day,
  Value<int> captureCount,
  Value<int> taskCount,
  Value<int> rowid,
});
typedef $$UsageDaysTableUpdateCompanionBuilder = UsageDaysCompanion Function({
  Value<String> day,
  Value<int> captureCount,
  Value<int> taskCount,
  Value<int> rowid,
});

class $$UsageDaysTableFilterComposer
    extends Composer<_$AppDatabase, $UsageDaysTable> {
  $$UsageDaysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get captureCount => $composableBuilder(
    column: $table.captureCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taskCount => $composableBuilder(
    column: $table.taskCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsageDaysTableOrderingComposer
    extends Composer<_$AppDatabase, $UsageDaysTable> {
  $$UsageDaysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get captureCount => $composableBuilder(
    column: $table.captureCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taskCount => $composableBuilder(
    column: $table.taskCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsageDaysTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsageDaysTable> {
  $$UsageDaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get captureCount => $composableBuilder(
    column: $table.captureCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taskCount =>
      $composableBuilder(column: $table.taskCount, builder: (column) => column);
}

class $$UsageDaysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsageDaysTable,
          UsageDayRow,
          $$UsageDaysTableFilterComposer,
          $$UsageDaysTableOrderingComposer,
          $$UsageDaysTableAnnotationComposer,
          $$UsageDaysTableCreateCompanionBuilder,
          $$UsageDaysTableUpdateCompanionBuilder,
          (
            UsageDayRow,
            BaseReferences<_$AppDatabase, $UsageDaysTable, UsageDayRow>,
          ),
          UsageDayRow,
          PrefetchHooks Function()
        > {
  $$UsageDaysTableTableManager(_$AppDatabase db, $UsageDaysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsageDaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsageDaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsageDaysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<int> captureCount = const Value.absent(),
                Value<int> taskCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsageDaysCompanion(
                day: day,
                captureCount: captureCount,
                taskCount: taskCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                Value<int> captureCount = const Value.absent(),
                Value<int> taskCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsageDaysCompanion.insert(
                day: day,
                captureCount: captureCount,
                taskCount: taskCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UsageDaysTable, UsageDayRow>(table),
                  BaseReferences<_$AppDatabase, $UsageDaysTable, UsageDayRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsageDaysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsageDaysTable,
      UsageDayRow,
      $$UsageDaysTableFilterComposer,
      $$UsageDaysTableOrderingComposer,
      $$UsageDaysTableAnnotationComposer,
      $$UsageDaysTableCreateCompanionBuilder,
      $$UsageDaysTableUpdateCompanionBuilder,
      (
        UsageDayRow,
        BaseReferences<_$AppDatabase, $UsageDaysTable, UsageDayRow>,
      ),
      UsageDayRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$SettingsEntriesTableTableManager get settingsEntries =>
      $$SettingsEntriesTableTableManager(_db, _db.settingsEntries);
  $$UsageDaysTableTableManager get usageDays =>
      $$UsageDaysTableTableManager(_db, _db.usageDays);
}
