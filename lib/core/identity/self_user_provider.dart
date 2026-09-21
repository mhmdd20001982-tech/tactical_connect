import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/database_provider.dart';

/// The local user row (isSelf = true). Its deviceId is the one identity the
/// network layer uses.
final selfUserStreamProvider = StreamProvider<User?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.users)..where((tbl) => tbl.isSelf.equals(true)))
      .watchSingleOrNull();
});
