import 'package:flutter/material.dart';
import 'package:multicamera/src/camera.dart';

class CameraPreview extends StatefulWidget {
  final Camera camera;
  final bool mirror;
  final bool crop;

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
