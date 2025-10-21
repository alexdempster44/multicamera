import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:multicamera/internal/multicamera_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';

class Camera extends ChangeNotifier {
  static final _instances = <int, Camera>{};

  Future<void>? _initializeLock;
  bool _initialized = false;

  int? _id;
  CameraDirection _direction;
  bool _paused;
  (int, int) _size = (0, 0);
  int _quarterTurns = 0;

  bool get initialized => _initialized;
  int? get id => _id;

  CameraDirection get direction => _direction;
  set direction(CameraDirection value) {
    _direction = value;
    notifyListeners();

    if (_id case final id?) {
      MulticameraPlatform.instance.updateCamera(id, _direction, _paused);
    }
  }

  bool get paused => _paused;
  set paused(bool value) {
    _paused = value;
    notifyListeners();

    if (_id case final id?) {
      MulticameraPlatform.instance.updateCamera(id, _direction, _paused);
    }
  }

  (int, int) get size => _size;
  int get quarterTurns => _quarterTurns;

  Camera({
    CameraDirection direction = CameraDirection.front,
    bool paused = false,
  }) : _direction = direction,
       _paused = paused;

  static void setSize(int id, (int, int) size) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera._size = size;
    camera.notifyListeners();
  }

  static void setQuarterTurns(int id, int quarterTurns) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera._quarterTurns = quarterTurns;
    camera.notifyListeners();
  }

  Future<void> initialize() async {
    if (_initializeLock != null) return;
    final completer = Completer<void>();
    _initializeLock = completer.future;

    if (!await _ensurePermissions()) {
      completer.complete();
      _initializeLock = null;
      return;
    }

    final id = await MulticameraPlatform.instance.registerCamera(
      _direction,
      _paused,
    );
    if (id == null) return;

    _id = id;
    _instances[id] = this;
    _initialized = true;
    completer.complete();
    _initializeLock = null;
    notifyListeners();
  }

  Future<Uint8List?> captureImage() async {
    if (!_initialized) throw StateError('Not initialized');

    final id = _id;
    if (id == null) return null;

    return await MulticameraPlatform.instance.captureImage(id);
  }

  Future<bool> _ensurePermissions() async {
    var cameraStatus = await Permission.camera.status;
    if (cameraStatus.isGranted) return true;

    cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted;
  }

  @override
  Future<void> dispose() async {
    if (_initializeLock case final future?) await future;
    if (_id case final id?) {
      _instances.remove(id);
      MulticameraPlatform.instance.unregisterCamera(id);
    }

    super.dispose();
  }
}

enum CameraDirection { front, back }
