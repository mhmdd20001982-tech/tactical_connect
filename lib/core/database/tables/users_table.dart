import 'package:drift/drift.dart';

class Users extends Table {
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get avatarPath => text().nullable()();
  BoolColumn get isSelf => boolean().withDefault(const Constant(false))();
  IntColumn get lastSeen => integer()();
  IntColumn get batteryLevel => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {deviceId};
}