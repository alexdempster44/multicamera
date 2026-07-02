import AVFoundation
import Flutter
import UIKit

class CameraHandle: NSObject {
  let direction: Camera.Direction
  let onCameraUpdated: (() -> Void)
  let onTextImage: ((UIImage) -> Void)
  let onBarcodes: (([String]) -> Void)
  let onFace: ((Bool) -> Void)
  private(set) var size: (Int32, Int32) = (1, 1)
  private(set) var quarterTurns: Int32 = 1

  private static let session: AVCaptureSession = {
    if AVCaptureMultiCamSession.isMultiCamSupported {
      return AVCaptureMultiCamSession()
    }
    return AVCaptureSession()
  }()
  private static let sessionQueue = DispatchQueue(
    label: "my.alexl.multicamera.session",
    qos: .userInitiated
  )
  private static var referenceCount = 0
  private var device: AVCaptureDevice?

  private static let captureCompressionQuality: CGFloat = 0.8
  private static let recognitionThrottleInterval: TimeInterval = 0.2
  private static let stableExposureOffset: Float = 0.5

  private let output = AVCaptureVideoDataOutput()
  private let metadataOutput = AVCaptureMetadataOutput()
  private let queue: DispatchQueue
  private let ciContext = CIContext()
  private var cameras: [Camera] = []
  private var pendingCaptureCallbacks: [(mirror: Bool, callback: (Data?) -> Void)] = []
  private var pendingImmediateCaptureCallbacks: [(mirror: Bool, callback: (Data?) -> Void)] = []
  private var lastRecognitionTime: Date?
  private var recognizeText = false
  private var scanBarcodes = false
  private var detectFaces = false
  private var lastFace: Bool?

  init(
    direction: Camera.Direction,
    onCameraUpdated: @escaping (() -> Void),
    onTextImage: @escaping ((UIImage) -> Void),
    onBarcodes: @escaping (([String]) -> Void),
    onFace: @escaping ((Bool) -> Void)
  ) {
    self.direction = direction
    self.onCameraUpdated = onCameraUpdated
    self.onTextImage = onTextImage
    self.onBarcodes = onBarcodes
    self.onFace = onFace
    self.queue = DispatchQueue(
      label: "my.alexl.multicamera.\(direction)",
      qos: .userInitiated
    )
    super.init()

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOrientationChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )

    Self.sessionQueue.async { [self] in self.createDevice() }
  }

  func close() {
    output.setSampleBufferDelegate(nil, queue: nil)
    cameras = []
    for entry in pendingCaptureCallbacks {
      entry.callback(nil)
    }
    pendingCaptureCallbacks = []
    for entry in pendingImmediateCaptureCallbacks {
      entry.callback(nil)
    }
    pendingImmediateCaptureCallbacks = []

    Self.sessionQueue.async { [self] in self.closeDevice() }

    NotificationCenter.default.removeObserver(self)
  }

  func setCameras(_ cameras: [Camera]) {
    self.cameras = cameras
    setupDevice()
  }

  func updateRecognition(
    recognizeText: Bool,
    scanBarcodes: Bool,
    detectFaces: Bool
  ) {
    self.recognizeText = recognizeText
    self.scanBarcodes = scanBarcodes
    self.detectFaces = detectFaces
    self.lastFace = nil
    Self.sessionQueue.async { [weak self] in self?.applyMetadataTypes() }
  }

  private func applyMetadataTypes() {
    guard device != nil else { return }

    let available = metadataOutput.availableMetadataObjectTypes
    var types: [AVMetadataObject.ObjectType] = []
    if scanBarcodes {
      types += available.filter { $0 != .face }
    }
    if detectFaces, available.contains(.face) {
      types.append(.face)
    }
    metadataOutput.metadataObjectTypes = types
  }

  func captureImage(
    immediate: Bool,
    mirror: Bool,
    _ callback: @escaping (Data?) -> Void
  ) {
    if immediate {
      pendingImmediateCaptureCallbacks.append((mirror, callback))
    } else {
      pendingCaptureCallbacks.append((mirror, callback))
    }
    setupDevice()
  }

  private func setupDevice() {
    Self.sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if !cameras.isEmpty || !pendingCaptureCallbacks.isEmpty
        || !pendingImmediateCaptureCallbacks.isEmpty
      {
        self.createDevice()
      } else {
        self.closeDevice()
      }
    }
  }

  private func createDevice() {
    if device != nil { return }

    Self.session.beginConfiguration()

    guard let device = selectDevice() else {
      Self.session.commitConfiguration()
      return
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      Self.session.commitConfiguration()
      return
    }
    guard Self.session.canAddInput(input) else {
      Self.session.commitConfiguration()
      return
    }
    Self.session.addInput(input)

    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard Self.session.canAddOutput(output) else {
      Self.session.commitConfiguration()
      return
    }
    Self.session.addOutput(output)

    addMetadataOutput(for: input)

    Self.session.commitConfiguration()

    self.device = device
    Self.referenceCount += 1
    if Self.referenceCount == 1 {
      Self.session.startRunning()
    }

    let dimensions = device.activeFormat.formatDescription.dimensions
    size = (dimensions.width, dimensions.height)

    applyMetadataTypes()
    handleOrientationChange()
  }

  private func addMetadataOutput(for input: AVCaptureDeviceInput) {
    guard Self.session.canAddOutput(metadataOutput) else { return }
    Self.session.addOutputWithNoConnections(metadataOutput)
    metadataOutput.setMetadataObjectsDelegate(self, queue: queue)

    let ports = input.ports(
      for: .metadataObject,
      sourceDeviceType: input.device.deviceType,
      sourceDevicePosition: input.device.position
    )
    guard let port = ports.first else { return }
    let connection = AVCaptureConnection(
      inputPorts: [port],
      output: metadataOutput
    )
    guard Self.session.canAddConnection(connection) else { return }
    Self.session.addConnection(connection)
  }

  private func selectDevice() -> AVCaptureDevice? {
    let types: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera, .builtInUltraWideCamera,
      .builtInTelephotoCamera, .builtInTrueDepthCamera,
    ]
    let position: AVCaptureDevice.Position =
      switch direction {
      case .front: .front
      case .back: .back
      }
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: types,
      mediaType: .video,
      position: position
    )

    return discovery.devices.sorted {
      $0.activeFormat.formatDescription.dimensions.width
        > $1.activeFormat.formatDescription.dimensions.width
    }.first
  }

  private func onPixelBuffer(_ data: CVPixelBuffer) {
    let data = rotatePixelBuffer(data, quarterTurns: quarterTurns) ?? data

    for camera in cameras {
      camera.updateFrame(data)
    }

    let exposureStable = exposureStable()

    let hasStableCapture =
      !pendingCaptureCallbacks.isEmpty && exposureStable
    let hasImmediateCapture = !pendingImmediateCaptureCallbacks.isEmpty
    let hasCapture = hasStableCapture || hasImmediateCapture

    if hasCapture, let image = convertDataToImage(data) {
      var encodedData: [Bool: Data?] = [:]
      func capturedData(mirror: Bool) -> Data? {
        if let cached = encodedData[mirror] { return cached }
        let source = mirror ? convertDataToImage(data, mirror: true) : image
        let imageData = source?.jpegData(
          compressionQuality: CameraHandle.captureCompressionQuality
        )
        encodedData[mirror] = imageData
        return imageData
      }

      var callbacks = pendingImmediateCaptureCallbacks
      pendingImmediateCaptureCallbacks = []
      if exposureStable {
        callbacks += pendingCaptureCallbacks
        pendingCaptureCallbacks = []
      }

      for entry in callbacks {
        let imageData = capturedData(mirror: entry.mirror)
        Task { entry.callback(imageData) }
      }
    }

    guard recognizeText else { return }

    let now = Date()
    let elapsed = now.timeIntervalSince(
      lastRecognitionTime ?? Date.distantPast
    )

    if elapsed < Self.recognitionThrottleInterval { return }
    if let image = convertDataToImage(data) {
      self.lastRecognitionTime = now
      Task { onTextImage(image) }
    }
  }

  private func rotatePixelBuffer(
    _ pixelBuffer: CVPixelBuffer,
    quarterTurns: Int32,
  ) -> CVPixelBuffer? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

    let exif: Int32 =
      switch Int(((quarterTurns % 4) + 4) % 4) {
      case 0: 1
      case 1: 6
      case 2: 3
      default: 8
      }
    let rotated = ciImage.oriented(forExifOrientation: exif)

    var outputPixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(rotated.extent.width),
      Int(rotated.extent.height),
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &outputPixelBuffer
    )
    guard status == kCVReturnSuccess, let output = outputPixelBuffer else {
      return nil
    }

    ciContext.render(rotated, to: output)
    return output
  }

  private func convertDataToImage(
    _ data: CVPixelBuffer,
    mirror: Bool = false
  ) -> UIImage? {
    var ciImage = CIImage(cvPixelBuffer: data)
    if mirror {
      ciImage = ciImage.oriented(forExifOrientation: 2)
    }

    let rect = ciImage.extent.integral
    guard let cg = ciContext.createCGImage(ciImage, from: rect) else {
      return nil
    }

    return UIImage(cgImage: cg, scale: 1.0, orientation: .up)
  }

  private func exposureStable() -> Bool {
    guard let device = device else { return false }
    return !device.isAdjustingExposure
      && abs(device.exposureTargetOffset) < Self.stableExposureOffset
  }

  @objc private func handleOrientationChange() {
    DispatchQueue.main.async { [self] in
      let windowScene =
        UIApplication.shared.connectedScenes.first as? UIWindowScene

      guard let interfaceOrientation = windowScene?.interfaceOrientation
      else { return }

      let quarterTurns: Int32? =
        switch interfaceOrientation {
        case .landscapeRight: 0
        case .portrait: 1
        case .landscapeLeft: 2
        case .portraitUpsideDown: 3
        default: nil
        }
      guard let quarterTurns = quarterTurns else { return }

      let isLandscape = interfaceOrientation.isLandscape
      let adjustment: Int32 =
        (self.direction == .front && isLandscape) ? 2 : 0

      self.quarterTurns = (quarterTurns + adjustment) % 4
      self.onCameraUpdated()
    }
  }

  private func closeDevice() {
    guard let device = device else { return }

    Self.session.beginConfiguration()
    Self.session.removeOutput(output)
    if Self.session.outputs.contains(metadataOutput) {
      Self.session.removeOutput(metadataOutput)
    }

    for input in Self.session.inputs {
      guard let deviceInput = input as? AVCaptureDeviceInput else {
        continue
      }
      if deviceInput.device != device { continue }

      Self.session.removeInput(deviceInput)
    }
    Self.session.commitConfiguration()

    self.device = nil
    Self.referenceCount -= 1
    if Self.referenceCount == 0 {
      Self.session.stopRunning()
    }
  }
}

extension CameraHandle: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let data = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    onPixelBuffer(data)
  }
}

extension CameraHandle: AVCaptureMetadataOutputObjectsDelegate {
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    if scanBarcodes {
      let barcodes = metadataObjects.compactMap {
        ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
      }
      onBarcodes(barcodes)
    }
    if detectFaces {
      let hasFace = metadataObjects.contains { $0.type == .face }
      if hasFace != lastFace {
        lastFace = hasFace
        onFace(hasFace)
      }
    }
  }
}
