import 'package:drift/drift.dart';

class Points extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get createdByDeviceId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // LOCATION | INFO | ALERT | MARKER
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get syncState => text().withDefault(const Constant('LOCAL'))();

  @override
  Set<Column> get primaryKey => {id};
}