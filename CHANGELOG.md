## v1.11.0

- Add a `playSound` option to `Camera.captureImage` to play the system shutter sound when capturing

## v1.10.0

- (iOS) Render a debug placeholder frame on the simulator, which has no camera hardware, instead of attempting to open the camera stream

## v1.9.0

- (iOS) Use camera output metadata for barcode and face detection for improved efficiency
- (Android) Use camera stream configuration maps to scale recognition coordinates when available

## v1.8.0

- (iOS) Replace Google MLKit with Apple's on-device Vision framework for text recognition, barcode scanning, and face detection, removing all third-party ML dependencies
- (iOS) Add Swift Package Manager support
- (iOS) Lower minimum platform version to 13.0

## v1.7.0

- Add `mirror` option to `Camera.captureImage` to horizontally flip the captured image for front-facing person photos

## v1.6.0

- Require Flutter 3.44.0+ / Dart 3.12.0+
- (Android) Migrate to built-in Kotlin: Android Gradle Plugin 9, Gradle 9.1, Kotlin 2.3.20, Java 17
- Update dependencies

## v1.5.1

- (Android) Use activity display rotation for preview orientation when available

## v1.5.0

- Reset registry on hot restart

## v1.4.2

- (Android) Fix preview rotation on portrait-locked devices

## v1.4.1

- (Android) Handle camera open race conditions on synchronous failure and close

## v1.4.0

- Require Flutter 3.41.0+ / Dart 3.11.0+
- Fix race where camera direction/state changes during initialization were dropped

## v1.3.12

- (Android) Reopen errored camera handles

## v1.3.11

- Add optional `immediate` flag to `captureImage` to skip exposure levelling
- (Android) Correct matrix calculation for previews
- (Android) Increase minimum API level to 26
- (Android) Update dependencies

## v1.3.10

- (Android) Catch and ignore exceptions when running image recognition

## v1.3.9

- (Android) Initialize EGL synchronously to prevent race conditions on slower devices
- (Android) Handle errors when creating EGL surfaces

## v1.3.8

- (iOS) Prevent disposing already disposed flutter textures from backgrounding

## v1.3.7

- (Android) Lower `minSdk` to 21

## v1.3.6

- (Android) Wait for exposure to level before capturing
- (Android) Add EXIF rotation data to captures
- (iOS) Close camera handle outputs immediately

## v1.3.5

- (iOS) Fallback if multicamera sessions are not supported

## v1.3.4

- (Android) Handle exceptions when opening camera handle device

## v1.3.3

- (iOS) Adjust session management to prevent dangling devices
- (iOS) Wait for exposure to stabilize before capturing images

## v1.3.2

- (Android) Adjust image acquire technique to avoid warnings

## v1.3.1+1

- Adjust file structure to hide internal dart files

## v1.3.1

- (iOS) Lower minimum platform version to 15.5

## v1.3.0

- (Dart) Add dartdocs to public API
- Improve code readability

## v1.2.1

- (Android) Fix immediate capture not returning image

## v1.2.0

- Stop camera session when paused to turn off system camera indicator
- (Android) Fix recognition pipeline getting blocked when no callbacks setup

## v1.1.0

- Adjust file structure to avoid importing source files: use `import 'package:multicamera/multicamera.dart';`
- Allow setting camera callbacks to null

## v1.0.0

Initial release! 🎉
