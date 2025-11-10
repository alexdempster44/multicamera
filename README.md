# Multicamera

A Flutter plugin for managing multiple camera instances simultaneously with built-in ML kit support.

## Features

- **Multiple simultaneous cameras** - Run multiple camera instances at the same time
- **Image capture** - Capture images from any camera instance
- **Front/Back camera support** - Easy switching between camera directions
- **Text recognition** - Real-time text recognition using MLKit
- **Barcode scanning** - Detect and scan various barcode formats
- **Face detection** - Real-time face detection capabilities
- **Cross-platform** - Supports both iOS and Android

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  multicamera: ^1.3.4
```

Or install from the repository:

```yaml
dependencies:
  multicamera:
    git:
      url: https://github.com/alexdempster44/multicamera.git
```

Then run:

```bash
flutter pub get
```

## Platform Setup

### iOS

Add the following keys to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to capture photos and video</string>
```

### Android

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

## Permissions

**Important:** This plugin does not handle camera permission requests. It is the developer's responsibility to request and ensure that camera permissions have been granted before calling `camera.initialize()`.

You can use the [permission_handler](https://pub.dev/packages/permission_handler) package or platform-specific permission APIs to request camera access:

```dart
import 'package:permission_handler/permission_handler.dart';

// Request camera permission before initializing
final status = await Permission.camera.request();
if (!status.isGranted) {
  // Handle permission denied
  return;
}

await camera.initialize();
```

## Usage

### Basic Camera Setup

```dart
import 'package:multicamera/multicamera.dart';

// Create a camera instance
final camera = Camera(
  direction: CameraDirection.front,
  paused: false,
);

// Initialize the camera
await camera.initialize();
```

### Display Camera Preview

```dart
import 'package:flutter/material.dart';
import 'package:multicamera/multicamera.dart';

class CameraScreen extends StatefulWidget {
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final Camera camera;

  @override
  void initState() {
    super.initState();
    camera = Camera(direction: CameraDirection.front);
    camera.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return CameraPreview(
      camera: camera,
      mirror: true, // Mirror the preview (only affects the front camera)
      crop: false,  // Fit or crop the preview to the available space
    );
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }
}
```

### Capture Images

```dart
// Capture an image from the camera
Uint8List? imageData = await camera.captureImage();

if (imageData case final data?) {
  Image.memory(data); // Display the image
}
```

### Multiple Cameras

```dart
// Create multiple camera instances
final frontCamera = Camera(direction: CameraDirection.front);
final backCamera = Camera(direction: CameraDirection.back);

await frontCamera.initialize();
await backCamera.initialize();

// Display both previews
Row(
  children: [
    Expanded(child: CameraPreview(camera: frontCamera)),
    Expanded(child: CameraPreview(camera: backCamera)),
  ],
);
```

### Text Recognition

```dart
final camera = Camera(direction: CameraDirection.back);

// Set up text recognition callback
camera.onTextRecognized = (List<String> recognizedText) {
  print('Recognized text: $recognizedText');
};

await camera.initialize();
```

### Barcode Scanning

```dart
final camera = Camera(direction: CameraDirection.back);

// Set up barcode scanning callback
camera.onBarcodesScanned = (List<String> barcodes) {
  print('Scanned barcodes: $barcodes');
};

await camera.initialize();
```

### Face Detection

```dart
final camera = Camera(direction: CameraDirection.front);

// Set up face detection callback
camera.onFaceDetected = (bool faceDetected) {
  print('Face detected: $faceDetected');
};

await camera.initialize();
```

### Change Camera Settings

```dart
// Change camera direction
camera.direction = CameraDirection.back;

// Pause/resume camera
camera.paused = true;  // Pause
camera.paused = false; // Resume
```

## Example

See the [example](example/) directory for a complete sample application demonstrating multiple cameras, image capture, and ML features.

## License

This is free and unencumbered software released into the public domain. See the [LICENSE](LICENSE) file for details.
