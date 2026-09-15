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
    let camera = cameras.removeValue(forKey: id)
    reconcile()
    camera?.close()
  }

  func reset() {
    let body = { [weak self] in
      guard let self = self else { return }
      for handle in self.cameraHandles.values { handle.close() }
      self.cameraHandles.removeAll()
      for camera in self.cameras.values { camera.close() }
      self.cameras.removeAll()
    }

    if Thread.isMainThread {
      body()
    } else {
      DispatchQueue.main.async(execute: body)
    }
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
      onTextImage: { [weak self] buffer in
        self?.onTextImage(buffer, direction: direction)
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
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard let handle = self.cameraHandles[direction] else { return }
      guard let (width, height) = handle.size else { return }

      let cameras = self.cameras.values.filter {
        $0.direction == direction && !$0.paused
      }
      for camera in cameras {
        guard let id = camera.id else { continue }
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
    _ buffer: CVPixelBuffer,
    direction: Camera.Direction
  ) {
    ImageRecognition.recognizeText(
      buffer,
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
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let cameras = self.cameras.values.filter {
        $0.direction == direction && !$0.paused
      }

      for camera in cameras {
        guard let id = camera.id else { continue }
        self.plugin.channel.invokeMethod(
          "recognitionResults",
          arguments: results.merging(["id": id]) { current, _ in current }
        )
      }
    }
  }
}
