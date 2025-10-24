import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multicamera/camera.dart';
import 'package:multicamera/internal/utilities.dart';

import 'multicamera_platform_interface.dart';

class MethodChannelMulticamera extends MulticameraPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('multicamera');

  MethodChannelMulticamera() {
    methodChannel.setMethodCallHandler((call) async {
      try {
        return await _handleMethodCall(call);
      } catch (_) {}
    });
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments as Map;
    switch (call.method) {
      case "updateCamera":
        final id = arguments['id'] as int;
        final width = arguments['width'] as int;
        final height = arguments['height'] as int;
        final quarterTurns = arguments['quarterTurns'] as int;

        Camera.setSize(id, (width, height));
        Camera.setQuarterTurns(id, quarterTurns);
      case "recognitionResults":
        final id = arguments['id'] as int;
        final text = arguments['text'] as List?;
        final barcodes = arguments['barcodes'] as List?;
        final face = arguments['face'] as bool?;

        if (text != null) Camera.textRecognized(id, text.toStrings());
        if (barcodes != null) Camera.barcodesScanned(id, barcodes.toStrings());
        if (face != null) Camera.faceDetected(id, face);
    }
  }

  @override
  Future<int?> registerCamera(
    CameraDirection direction,
    bool paused,
    bool recognizeText,
    bool scanBarcodes,
    bool detectFaces,
  ) => methodChannel.invokeMethod<int>('registerCamera', {
    'direction': direction.index,
    'paused': paused,
    'recognizeText': recognizeText,
    'scanBarcodes': scanBarcodes,
    'detectFaces': detectFaces,
  });

  @override
  Future<void> updateCamera(
    int id,
    CameraDirection direction,
    bool paused,
    bool recognizeText,
    bool scanBarcodes,
    bool detectFaces,
  ) => methodChannel.invokeMethod<void>('updateCamera', {
    'id': id,
    'direction': direction.index,
    'paused': paused,
    'recognizeText': recognizeText,
    'scanBarcodes': scanBarcodes,
    'detectFaces': detectFaces,
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
