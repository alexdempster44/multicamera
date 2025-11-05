import 'package:flutter/material.dart';

import 'camera.dart';

/// A widget that displays a live camera preview.
///
/// The [CameraPreview] widget shows the camera feed from a [Camera] instance.
/// It automatically handles mirroring for front-facing cameras and provides
/// options to crop or contain the preview.
///
/// Example usage:
/// ```dart
/// final camera = Camera(direction: CameraDirection.front);
/// await camera.initialize();
///
/// CameraPreview(
///   camera: camera,
///   mirror: true,
///   crop: false,
/// )
/// ```
class CameraPreview extends StatefulWidget {
  /// The camera instance to display.
  final Camera camera;

  /// Whether to mirror the preview horizontally for front-facing cameras.
  ///
  /// When `true`, the front camera preview is mirrored to match the user's
  /// expectation (like looking in a mirror).
  final bool mirror;

  /// Whether to crop the preview to fill the available space.
  ///
  /// When `true`, the preview will cover the available space, potentially
  /// cropping the preview. When `false`, the preview will scale to fit all its
  /// contents within the available space.
  final bool crop;

  /// Creates a camera preview widget.
  ///
  /// The [camera] parameter is required and must be initialized before
  /// the preview can display.
  ///
  /// The [mirror] parameter controls horizontal mirroring for front cameras
  /// and defaults to `true`.
  ///
  /// The [crop] parameter controls whether the preview fills the space
  /// and defaults to `false`.
  const CameraPreview({
    super.key,
    required this.camera,
    this.mirror = true,
    this.crop = false,
  });

  @override
  State<CameraPreview> createState() => _CameraPreviewState();
}

class _CameraPreviewState extends State<CameraPreview> {
  @override
  void initState() {
    super.initState();
    widget.camera.addListener(listener);
  }

  @override
  void didUpdateWidget(covariant CameraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    oldWidget.camera.removeListener(listener);
    widget.camera.addListener(listener);
  }

  @override
  void dispose() {
    widget.camera.removeListener(listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialized = widget.camera.initialized;
    if (!initialized) return const Center(child: CircularProgressIndicator());

    final id = widget.camera.id;
    if (id == null) return const Icon(Icons.warning);

    final frontCamera = widget.camera.direction == CameraDirection.front;

    return ClipRect(
      child: FittedBox(
        fit: widget.crop ? BoxFit.cover : BoxFit.contain,
        child: Transform.flip(
          flipX: frontCamera && widget.mirror,
          child: SizedBox(
            width: widget.camera.size.$1.toDouble(),
            height: widget.camera.size.$2.toDouble(),
            child: Texture(textureId: id),
          ),
        ),
      ),
    );
  }

  void listener() => setState(() {});
}
