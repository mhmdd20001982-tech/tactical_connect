import 'package:drift/drift.dart';

class SosEvents extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get deviceId => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get batteryLevel => integer().nullable()();
  TextColumn get status => text()(); // ACTIVE | CANCELLED
  IntColumn get startedAt => integer()();
  IntColumn get cancelledAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}