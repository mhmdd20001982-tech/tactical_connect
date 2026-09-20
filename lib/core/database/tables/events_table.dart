import 'package:drift/drift.dart';

class Events extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text().nullable()();
  TextColumn get deviceId => text()();
  TextColumn get eventType => text()();
  TextColumn get payload => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}