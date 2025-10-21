import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multicamera/multicamera.dart';
import 'package:multicamera_example/camera_view.dart';

void main() => runApp(MaterialApp(home: Home()));

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _viewCount = 0;
  final _captures = <Uint8List>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Row(
              children: [
                IconButton.filled(
                  icon: Icon(Icons.remove),
                  onPressed: () => setState(() => _viewCount--),
                ),
                IconButton.filled(
                  icon: Icon(Icons.add),
                  onPressed: () => setState(() => _viewCount++),
                ),
                const SizedBox(width: 16),
                IconButton.outlined(
                  icon: Icon(Icons.face),
                  onPressed: () async {
                    final camera = Camera(direction: CameraDirection.front);
                    await camera.initialize();
                    final image = await camera.captureImage();
                    camera.dispose();
                    if (!mounted || image == null) return;

                    setState(() => _captures.add(image));
                  },
                ),
                IconButton.outlined(
                  icon: Icon(Icons.person),
                  onPressed: () async {
                    final camera = Camera(direction: CameraDirection.back);
                    await camera.initialize();
                    final image = await camera.captureImage();
                    camera.dispose();
                    if (!mounted || image == null) return;

                    setState(() => _captures.add(image));
                  },
                ),
              ],
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all()),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _CameraViewList(
                    length: _viewCount,
                    onCapture: (image) => setState(() => _captures.add(image)),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _captures.length,
                itemBuilder: (_, index) {
                  final image = _captures[index];
                  return Stack(
                    children: [
                      Image.memory(image),
                      Positioned(
                        width: 32,
                        height: 32,
                        top: 4,
                        right: 4,
                        child: FittedBox(
                          child: IconButton.filledTonal(
                            icon: Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _captures.remove(image)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(width: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraViewList extends StatelessWidget {
  final int length;
  final void Function(Uint8List) onCapture;

  const _CameraViewList({required this.length, required this.onCapture});

  static const _crossAxisCount = 4;

  @override
  Widget build(BuildContext context) {
    if (length < 0) {
      return Center(
        child: Text('No views setup'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = min(length, _crossAxisCount);
        final rows = ((length - 1) ~/ _crossAxisCount) + 1;
        final itemWidth = (constraints.maxWidth / columns) - 8;
        final itemHeight = (constraints.maxHeight / rows) - 8;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            length,
            (i) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: itemWidth,
                maxHeight: itemHeight,
              ),
              child: CameraView(
                key: ValueKey(i),
                onCapture: onCapture,
              ),
            ),
          ),
        );
      },
    );
  }
}
