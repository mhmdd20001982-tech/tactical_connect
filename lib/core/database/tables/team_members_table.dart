import 'package:drift/drift.dart';

class TeamMembers extends Table {
  TextColumn get teamId => text()();
  TextColumn get deviceId => text()();
  TextColumn get role => text()(); // 'host' | 'peer'
  IntColumn get joinedAt => integer()();
  TextColumn get status => text().withDefault(const Constant('offline'))(); // 'online' | 'offline'

  @override
  Set<Column> get primaryKey => {teamId, deviceId};
}