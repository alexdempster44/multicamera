import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:multicamera/internal/multicamera_platform_interface.dart';

typedef TextRecognizedCallback = void Function(List<String>);
typedef BarcodesScannedCallback = void Function(List<String>);
typedef FaceDetectedCallback = void Function(bool);

class Camera extends ChangeNotifier {
  static final _instances = <int, Camera>{};

  Future<void>? _initializeLock;
  bool _initialized = false;

  int? _id;
  CameraDirection _direction;
  bool _paused;
  TextRecognizedCallback? _onTextRecognized;
  BarcodesScannedCallback? _onBarcodesScanned;
  FaceDetectedCallback? _onFaceDetected;
  (int, int) _size = (0, 0);

  bool get initialized => _initialized;
  int? get id => _id;

  CameraDirection get direction => _direction;
  set direction(CameraDirection value) {
    _direction = value;
    _updateCamera();
  }

  bool get paused => _paused;
  set paused(bool value) {
    _paused = value;
    _updateCamera();
  }

  TextRecognizedCallback? get onTextRecognized => _onTextRecognized;
  set onTextRecognized(TextRecognizedCallback? value) {
    _onTextRecognized = value;
    _updateCamera();
  }

  BarcodesScannedCallback? get onBarcodesScanned => _onBarcodesScanned;
  set onBarcodesScanned(BarcodesScannedCallback? value) {
    _onBarcodesScanned = value;
    _updateCamera();
  }

  FaceDetectedCallback? get onFaceDetected => _onFaceDetected;
  set onFaceDetected(FaceDetectedCallback? value) {
    _onFaceDetected = value;
    _updateCamera();
  }

  (int, int) get size => _size;

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

  static void textRecognized(int id, List<String> text) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera.onTextRecognized?.call(text);
  }

  static void barcodesScanned(int id, List<String> barcode) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera.onBarcodesScanned?.call(barcode);
  }

  static void faceDetected(int id, bool face) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera.onFaceDetected?.call(face);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializeLock case final future?) return future;
    final completer = Completer<void>();
    _initializeLock = completer.future;

    final id = await MulticameraPlatform.instance.registerCamera(
      _direction,
      _paused,
      _onTextRecognized != null,
      _onBarcodesScanned != null,
      _onFaceDetected != null,
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
    await _ensureInitialized();

    final id = _id;
    if (id == null) return null;

    return await MulticameraPlatform.instance.captureImage(id);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (_initializeLock case final future?) return future;

    throw StateError('Not initialized');
  }

  void _updateCamera() {
    notifyListeners();

    if (_initializeLock != null) throw StateError('Still initializing');

    final id = _id;
    if (id == null) return;

    MulticameraPlatform.instance.updateCamera(
      id,
      _direction,
      _paused,
      _onTextRecognized != null,
      _onBarcodesScanned != null,
      _onFaceDetected != null,
    );
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
