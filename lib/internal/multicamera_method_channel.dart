import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multicamera/camera.dart';

import 'multicamera_platform_interface.dart';

class MethodChannelMulticamera extends MulticameraPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('multicamera');

  MethodChannelMulticamera() {
    methodChannel.setMethodCallHandler((methodCall) async {
      try {
        switch (methodCall.method) {
          case "updateCamera":
            final arguments = methodCall.arguments as Map;
            final id = arguments['id'] as int;
            final width = arguments['width'] as int;
            final height = arguments['height'] as int;
            final quarterTurns = arguments['quarterTurns'] as int;

            Camera.setSize(id, (width, height));
            Camera.setQuarterTurns(id, quarterTurns);
        }
      } catch (_) {}
    });
  }

  @override
  Future<int?> registerCamera(CameraDirection direction, bool paused) =>
      methodChannel.invokeMethod<int>('registerCamera', {
        'direction': direction.index,
        'paused': paused,
      });

  @override
  Future<void> updateCamera(int id, CameraDirection direction, bool paused) =>
      methodChannel.invokeMethod<void>('updateCamera', {
        'id': id,
        'direction': direction.index,
        'paused': paused,
      });

  @override
  Future<Uint8List?> captureImage(int id) =>
      methodChannel.invokeMethod<Uint8List>('captureImage', {
        'id': id,
      });

  @override
  Future<void> unregisterCamera(int id) =>
      methodChannel.invokeMethod<void>('unregisterCamera', {
        'id': id,
      });
}
