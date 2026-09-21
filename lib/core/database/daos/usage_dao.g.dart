// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usage_dao.dart';

// ignore_for_file: type=lint
mixin _$UsageDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsageDaysTable get usageDays => attachedDatabase.usageDays;
  UsageDaoManager get managers => UsageDaoManager(this);
}

class UsageDaoManager {
  final _$UsageDaoMixin _db;
  UsageDaoManager(this._db);
  $$UsageDaysTableTableManager get usageDays =>
      $$UsageDaysTableTableManager(_db.attachedDatabase, _db.usageDays);
}
