import 'dart:typed_data';

import 'package:multicamera/camera.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'multicamera_method_channel.dart';

abstract class MulticameraPlatform extends PlatformInterface {
  MulticameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static MulticameraPlatform _instance = MethodChannelMulticamera();

  static MulticameraPlatform get instance => _instance;

  static set instance(MulticameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int?> registerCamera(CameraDirection direction, bool paused) =>
      throw UnimplementedError();

  Future<void> updateCamera(int id, CameraDirection direction, bool paused) =>
      throw UnimplementedError();

  Future<Uint8List?> captureImage(int id) => throw UnimplementedError();

  Future<void> unregisterCamera(int id) => throw UnimplementedError();
}
