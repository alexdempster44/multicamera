import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multicamera/camera.dart';
import 'package:multicamera/camera_preview.dart';

class CameraView extends StatefulWidget {
  final void Function(Uint8List) onCapture;

  const CameraView({
    super.key,
    required this.onCapture,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  late final Camera camera;

  @override
  void initState() {
    super.initState();

    camera = Camera();
    camera.addListener(() => setState(() {}));

    camera.initialize();
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all()),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (_, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(border: Border.all()),
                  child: CameraPreview(camera: camera),
                ),
              ),
              const SizedBox(height: 8),
              IconButton.filled(
                icon: Icon(Icons.camera),
                onPressed: () async {
                  final image = await camera.captureImage();
                  if (!mounted || image == null) return;

                  widget.onCapture(image);
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  Text(
                    'Paused:',
                    style: TextStyle(fontSize: 20),
                  ),
                  Switch(
                    value: camera.paused,
                    onChanged: (value) => camera.paused = value,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: CameraDirection.values
                    .map(
                      (direction) => camera.direction == direction
                          ? FilledButton(
                              child: Text(direction.name),
                              onPressed: () => camera.direction = direction,
                            )
                          : OutlinedButton(
                              child: Text(direction.name),
                              onPressed: () => camera.direction = direction,
                            ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
