import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

final class Permissions {
  static Future<bool>? _lock;

  static Future<bool> ensure() async {
    if (_lock case final future?) return future;
    final completer = Completer<bool>();
    _lock = completer.future;

    var cameraStatus = await Permission.camera.status;
    if (cameraStatus.isGranted) return true;

    cameraStatus = await Permission.camera.request();
    final success = cameraStatus.isGranted;

    completer.complete(success);
    _lock = null;
    return success;
  }
}
