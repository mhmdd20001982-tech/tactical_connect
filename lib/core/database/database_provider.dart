import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final hasIdentityProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final query = db.select(db.users)..where((u) => u.isSelf.equals(true));
  final row = await query.getSingleOrNull();
  return row != null;
});