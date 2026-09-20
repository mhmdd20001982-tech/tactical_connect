import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class DeviceIdProvider {
  DeviceIdProvider._();

  static String? _cachedId;

  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'device_id.txt'));

    if (await file.exists()) {
      final id = (await file.readAsString()).trim();
      if (id.isNotEmpty) {
        _cachedId = id;
        return id;
      }
    }

    final newId = const Uuid().v4();
    await file.writeAsString(newId);
    _cachedId = newId;
    return newId;
  }
}