import 'package:drift/drift.dart';

class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get deviceId => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get accuracy => real().nullable()();
  RealColumn get speed => real().nullable()();
  RealColumn get bearing => real().nullable()();
  IntColumn get recordedAt => integer()();
  IntColumn get receivedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {teamId, deviceId},
      ];
}