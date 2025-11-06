import 'dart:async';

import 'package:flutter/foundation.dart';

import 'internal/multicamera_platform_interface.dart';

/// Callback function that is invoked when text is recognized in the camera
/// feed.
typedef TextRecognizedCallback = void Function(List<String>);

/// Callback function that is invoked when barcodes are scanned in the camera
/// feed.
typedef BarcodesScannedCallback = void Function(List<String>);

/// Callback function that is invoked when a face is detected in the camera
/// feed.
typedef FaceDetectedCallback = void Function(bool);

/// A camera instance that provides access to the underlying platform.
///
/// Example usage:
/// ```dart
/// final camera = Camera(direction: CameraDirection.front);
/// await camera.initialize();
/// // Use camera with CameraPreview widget
/// ```
class Camera extends ChangeNotifier {
  static final _instances = <int, Camera>{};

  Future<void>? _initializeLock;
  bool _initialized = false;
  bool _pendingUpdate = false;

  int? _id;
  CameraDirection _direction;
  bool _paused;
  TextRecognizedCallback? _onTextRecognized;
  BarcodesScannedCallback? _onBarcodesScanned;
  FaceDetectedCallback? _onFaceDetected;
  (int, int) _size = (1, 1);

  /// Whether the camera has been initialized and is ready to use.
  ///
  /// Returns `true` after [initialize] has completed successfully.
  bool get initialized => _initialized;

  /// A unique ID referring to this camera instance.
  ///
  /// Returns `null` if the camera has not been initialized yet.
  int? get id => _id;

  /// The direction the camera is facing.
  ///
  /// Setting this property updates the camera configuration.
  CameraDirection get direction => _direction;
  set direction(CameraDirection value) {
    _direction = value;
    unawaited(_updateCamera());
  }

  /// Whether the camera is currently paused.
  ///
  /// Setting this property updates the camera state.
  bool get paused => _paused;
  set paused(bool value) {
    _paused = value;
    unawaited(_updateCamera());
  }

  /// Callback invoked when text is recognized in the camera feed.
  ///
  /// Set this to `null` to disable text recognition for this camera instance.
  /// Setting this property updates the camera state.
  TextRecognizedCallback? get onTextRecognized => _onTextRecognized;
  set onTextRecognized(TextRecognizedCallback? value) {
    _onTextRecognized = value;
    unawaited(_updateCamera());
  }

  /// Callback invoked when barcodes are scanned in the camera feed.
  ///
  /// Set this to `null` to disable barcode scanning for this camera instance.
  /// Setting this property updates the camera state.
  BarcodesScannedCallback? get onBarcodesScanned => _onBarcodesScanned;
  set onBarcodesScanned(BarcodesScannedCallback? value) {
    _onBarcodesScanned = value;
    unawaited(_updateCamera());
  }

  /// Callback invoked when a face is detected in the camera feed.
  ///
  /// Set this to `null` to disable face detection for this camera instance.
  /// Setting this property updates the camera state.
  FaceDetectedCallback? get onFaceDetected => _onFaceDetected;
  set onFaceDetected(FaceDetectedCallback? value) {
    _onFaceDetected = value;
    unawaited(_updateCamera());
  }

  /// The size of the camera preview in pixels as `(width, height)`.
  ///
  /// Returns `(1, 1)` if the camera has not been initialized yet.
  (int, int) get size => _size;

  /// Creates a new [Camera] instance.
  ///
  /// The [direction] parameter specifies which camera to use (front or back).
  /// The [paused] parameter specifies whether the camera should start paused.
  ///
  /// Call [initialize] before using the camera.
  Camera({
    CameraDirection direction = CameraDirection.front,
    bool paused = false,
  }) : _direction = direction,
       _paused = paused;

  @internal
  static void setSize(int id, (int, int) size) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera._size = size;
    camera.notifyListeners();
  }

  @internal
  static void textRecognized(int id, List<String> text) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera.onTextRecognized?.call(text);
  }

  @internal
  static void barcodesScanned(int id, List<String> barcode) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera.onBarcodesScanned?.call(barcode);
  }

  @internal
  static void faceDetected(int id, bool face) {
    final camera = Camera._instances[id];
    if (camera == null) return;

    camera.onFaceDetected?.call(face);
  }

  /// Initializes the camera and prepares it for use.
  ///
  /// This method must be called before using the camera. It registers the
  /// camera with the platform and sets up the camera session.
  ///
  /// If the camera is already initialized, this method returns immediately.
  /// If initialization is in progress, this method waits for it to complete.
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

  /// Captures an image from the camera.
  ///
  /// Returns the image data as a [Uint8List] containing the image bytes, or
  /// `null` if the capture fails.
  ///
  /// The camera must be initialized before calling this method.
  /// If initialization is in progress, this method waits for it to complete.
  ///
  /// Throws [StateError] if the camera has not been initialized.
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

  Future<void> _updateCamera() async {
    notifyListeners();

    if (!initialized || _pendingUpdate) return;
    _pendingUpdate = true;

    if (_initializeLock case final future?) await future;

    final id = _id;
    if (id == null) {
      _pendingUpdate = false;
      return;
    }

    MulticameraPlatform.instance.updateCamera(
      id,
      _direction,
      _paused,
      _onTextRecognized != null,
      _onBarcodesScanned != null,
      _onFaceDetected != null,
    );
    _pendingUpdate = false;
  }

  /// Disposes of the camera and releases associated resources.
  ///
  /// This method unregisters the camera from the platform implementation
  /// and cleans up all resources. This instance should not be used after
  /// calling dispose.
  ///
  /// Always call this method when you're done using the camera to prevent
  /// memory leaks.
  @override
  Future<void> dispose() async {
    if (_initializeLock case final future?) await future;
    if (_id case final id?) {
      _instances.remove(id);
      await MulticameraPlatform.instance.unregisterCamera(id);
    }

    super.dispose();
  }
}

/// Specifies the direction a camera is facing.
enum CameraDirection { front, back }
