import 'package:drift/drift.dart';

class Teams extends Table {
  TextColumn get id => text()();
  TextColumn get teamCode => text().unique()();
  TextColumn get name => text()();
  TextColumn get hostDeviceId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}