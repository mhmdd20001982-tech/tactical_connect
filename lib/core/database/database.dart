import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/users_table.dart';
import 'tables/teams_table.dart';
import 'tables/team_members_table.dart';
import 'tables/messages_table.dart';
import 'tables/locations_table.dart';
import 'tables/points_table.dart';
import 'tables/sos_events_table.dart';
import 'tables/events_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Users,
  Teams,
  TeamMembers,
  Messages,
  Locations,
  Points,
  SosEvents,
  Events,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'tactical_connect.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}