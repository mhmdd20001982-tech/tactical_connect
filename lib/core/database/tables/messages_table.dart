import 'package:drift/drift.dart';

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get senderDeviceId => text()();
  TextColumn get type => text()(); // 'text' | 'location_share' | 'point_share'
  TextColumn get content => text().nullable()();
  TextColumn get sharedLocationId => text().nullable()();
  TextColumn get sharedPointId => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get syncState => text().withDefault(const Constant('LOCAL'))();

  @override
  Set<Column> get primaryKey => {id};
}