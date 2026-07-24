import UIKit

class Registry {
  private let plugin: MulticameraPlugin

  private(set) var cameras: [Int64: Camera] = [:]
  private(set) var cameraHandles: [Camera.Direction: CameraHandle] = [:]

  init(plugin: MulticameraPlugin) {
    self.plugin = plugin
  }

  func registerCamera(
    direction: Camera.Direction,
    paused: Bool,
    recognizeText: Bool,
    scanBarcodes: Bool,
    detectFaces: Bool
  ) -> Int64 {
    let camera = Camera(
      plugin: plugin,
      direction: direction,
      paused: paused,
      recognizeText: recognizeText,
      scanBarcodes: scanBarcodes,
      detectFaces: detectFaces
    )

    cameras[camera.id] = camera
    reconcile()

    return camera.id
  }

  func updateCamera(
    id: Int64,
    direction: Camera.Direction,
    paused: Bool,
    recognizeText: Bool,
    scanBarcodes: Bool,
    detectFaces: Bool
  ) {
    guard let camera = cameras[id] else { return }

    camera.direction = direction
    camera.paused = paused
    camera.recognizeText = recognizeText
    camera.scanBarcodes = scanBarcodes
    camera.detectFaces = detectFaces

    reconcile()
  }

  func captureImage(
    id: Int64,
    immediate: Bool,
    mirror: Bool,
    playSound: Bool,
    _ callback: @escaping (Data?) -> Void
  ) {
    guard let camera = cameras[id] else {
      callback(nil)
      return
    }
    guard let handle = cameraHandles[camera.direction] else {
      callback(nil)
      return
    }

    handle.captureImage(
      immediate: immediate,
      mirror: mirror,
      playSound: playSound,
      callback
    )
  }

  func unregisterCamera(id: Int64) {
    cameras.removeValue(forKey: id)?.close()
    reconcile()
  }

  func reset() {
    for camera in cameras.values { camera.close() }
    cameras.removeAll()
    for handle in cameraHandles.values { handle.close() }
    cameraHandles.removeAll()
  }

  private func reconcile() {
    for direction in Camera.Direction.allCases {
      let cameras = cameras.values.filter { $0.direction == direction }
      guard cameras.isEmpty else { continue }

      cameraHandles.removeValue(forKey: direction)?.close()
    }

    for direction in Camera.Direction.allCases {
      let cameras = cameras.values.filter { $0.direction == direction }
      guard !cameras.isEmpty else { continue }

      let active = cameras.filter { !$0.paused }
      let handle =
        cameraHandles[direction] ?? createHandle(direction: direction)
      handle.setCameras(active)
      handle.updateRecognition(
        recognizeText: active.contains { $0.recognizeText },
        scanBarcodes: active.contains { $0.scanBarcodes },
        detectFaces: active.contains { $0.detectFaces }
      )
    }

    for direction in Camera.Direction.allCases {
      self.updateFlutterCameras(direction)
    }
  }

  private func createHandle(direction: Camera.Direction) -> CameraHandle {
    let handle = CameraHandle(
      direction: direction,
      onCameraUpdated: { [weak self] in
        self?.updateFlutterCameras(direction)
      },
      onTextImage: { [weak self] image in
        self?.onTextImage(image, direction: direction)
      },
      onBarcodes: { [weak self] barcodes in
        self?.sendRecognitionResults(direction, ["barcodes": barcodes])
      },
      onFace: { [weak self] face in
        self?.sendRecognitionResults(direction, ["face": face])
      }
    )

    cameraHandles[direction] = handle
    return handle
  }

  private func updateFlutterCameras(_ direction: Camera.Direction) {
    guard let handle = cameraHandles[direction] else { return }
    let cameras = cameras.values.filter {
      $0.direction == direction && !$0.paused
    }

    var width = handle.size.0
    var height = handle.size.1
    if handle.quarterTurns % 2 == 1 {
      swap(&width, &height)
    }

    for camera in cameras {
      guard let id = camera.id else { continue }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
        self.plugin.channel.invokeMethod(
          "updateCamera",
          arguments: [
            "id": id,
            "width": width,
            "height": height,
          ]
        )
      }
    }
  }

  private func onTextImage(
    _ image: UIImage,
    direction: Camera.Direction
  ) {
    ImageRecognition.recognizeText(
      image,
      onResult: { [weak self] text in
        guard let text = text else { return }
        self?.sendRecognitionResults(direction, ["text": text])
      }
    )
  }

  private func sendRecognitionResults(
    _ direction: Camera.Direction,
    _ results: [String: Any]
  ) {
    let cameras = cameras.values.filter {
      $0.direction == direction && !$0.paused
    }

    for camera in cameras {
      guard let id = camera.id else { continue }
      DispatchQueue.main.async {
        self.plugin.channel.invokeMethod(
          "recognitionResults",
          arguments: results.merging(["id": id]) { current, _ in current }
        )
      }
    }
  }
}
