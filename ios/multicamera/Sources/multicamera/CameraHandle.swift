import AVFoundation
import AudioToolbox
import Flutter
import UIKit

class CameraHandle: NSObject {
  let direction: Camera.Direction
  let onCameraUpdated: (() -> Void)
  let onTextImage: ((CVPixelBuffer) -> Void)
  let onBarcodes: (([String]) -> Void)
  let onFace: ((Bool) -> Void)

  var size: (Int32, Int32)? {
    withState { currentSize }
  }

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

  private let stateLock = NSLock()
  private var currentSize: (Int32, Int32)?
  private var currentQuarterTurns: Int32 = 1

  private var quarterTurns: Int32 {
    withState { currentQuarterTurns }
  }

  private var deviceRequired: Bool {
    withState {
      !cameras.isEmpty || !pendingCaptureCallbacks.isEmpty
        || !pendingImmediateCaptureCallbacks.isEmpty
    }
  }

  private static let captureCompressionQuality: CGFloat = 0.8
  private static let captureTimeout: TimeInterval = 5
  private static let sessionRestartAttempts: Int = 5
  private static let sessionRestartDelay: TimeInterval = 1
  private static let stableExposureOffset: Float = 0.5

  private static let shutterSoundID: SystemSoundID = 1108

  private let output = AVCaptureVideoDataOutput()
  private let metadataOutput = AVCaptureMetadataOutput()
  private let queue: DispatchQueue
  private let recognitionQueue: DispatchQueue
  private let ciContext = CIContext()
  private var cameras: [Camera] = []
  private var pendingCaptureCallbacks: [PendingCapture] = []
  private var pendingImmediateCaptureCallbacks: [PendingCapture] = []
  private var nextCaptureID: Int64 = 0
  private var recognitionInFlight = false
  private var restartInFlight = false
  private var recognizeText = false
  private var scanBarcodes = false
  private var detectFaces = false
  private var lastFace: Bool?

  init(
    direction: Camera.Direction,
    onCameraUpdated: @escaping (() -> Void),
    onTextImage: @escaping ((CVPixelBuffer) -> Void),
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
    self.recognitionQueue = DispatchQueue(
      label: "my.alexl.multicamera.\(direction).recognition",
      qos: .default
    )
    super.init()

    if let quarterTurns = interfaceQuarterTurns() {
      currentQuarterTurns = quarterTurns
    }

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOrientationChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionInterruptionEnded),
      name: AVCaptureSession.interruptionEndedNotification,
      object: Self.session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionRuntimeError),
      name: AVCaptureSession.runtimeErrorNotification,
      object: Self.session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleApplicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    Self.sessionQueue.async { [self] in self.createDevice() }
  }

  func close() {
    let callbacks: [PendingCapture] = withState {
      cameras = []
      let callbacks = pendingImmediateCaptureCallbacks + pendingCaptureCallbacks
      pendingImmediateCaptureCallbacks = []
      pendingCaptureCallbacks = []
      return callbacks
    }
    for entry in callbacks {
      DispatchQueue.main.async { entry.callback(nil) }
    }

    Self.sessionQueue.async { [self] in
      output.setSampleBufferDelegate(nil, queue: nil)
      metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
      self.closeDevice()
    }

    NotificationCenter.default.removeObserver(self)
  }

  func setCameras(_ cameras: [Camera]) {
    withState { self.cameras = cameras }

    setupDevice()
  }

  func updateRecognition(
    recognizeText: Bool,
    scanBarcodes: Bool,
    detectFaces: Bool
  ) {
    withState {
      self.recognizeText = recognizeText
      self.scanBarcodes = scanBarcodes
      self.detectFaces = detectFaces
      self.lastFace = nil
    }
    Self.sessionQueue.async { [weak self] in self?.applyMetadataTypes() }
  }

  private func applyMetadataTypes() {
    let (hasDevice, scanBarcodes, detectFaces) = withState {
      (device != nil, self.scanBarcodes, self.detectFaces)
    }
    guard hasDevice else { return }

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
    playSound: Bool,
    _ callback: @escaping (Data?) -> Void
  ) {
    let id = withState { () -> Int64 in
      nextCaptureID += 1
      let pending = PendingCapture(
        id: nextCaptureID,
        mirror: mirror,
        playSound: playSound,
        callback: callback
      )
      if immediate {
        pendingImmediateCaptureCallbacks.append(pending)
      } else {
        pendingCaptureCallbacks.append(pending)
      }
      return pending.id
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + Self.captureTimeout
    ) { [weak self] in
      self?.expireCapture(id)
    }

    setupDevice()
  }

  private func expireCapture(_ id: Int64) {
    let expired: PendingCapture? = withState {
      if let index = pendingImmediateCaptureCallbacks.firstIndex(
        where: { $0.id == id }
      ) {
        return pendingImmediateCaptureCallbacks.remove(at: index)
      }
      if let index = pendingCaptureCallbacks.firstIndex(where: { $0.id == id }) {
        return pendingCaptureCallbacks.remove(at: index)
      }
      return nil
    }

    guard let expired = expired else { return }
    DispatchQueue.main.async { expired.callback(nil) }

    setupDevice()
  }

  private func withState<T>(_ body: () -> T) -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return body()
  }

  private func setupDevice() {
    Self.sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if self.deviceRequired {
        self.createDevice()
      } else {
        self.closeDevice()
      }
    }
  }

  private func createDevice() {
    if withState({ device != nil }) { return }
    if openDevice() { return }

    #if targetEnvironment(simulator)
      showSimulatorWarning()
    #endif
  }

  private func openDevice() -> Bool {
    guard let device = selectDevice() else { return false }

    Self.session.beginConfiguration()

    guard let input = try? AVCaptureDeviceInput(device: device),
      Self.session.canAddInput(input)
    else {
      Self.session.commitConfiguration()
      return false
    }
    Self.session.addInput(input)

    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard Self.session.canAddOutput(output) else {
      Self.session.removeInput(input)
      Self.session.commitConfiguration()
      return false
    }
    Self.session.addOutput(output)

    addMetadataOutput(for: input)

    Self.session.commitConfiguration()

    withState { self.device = device }
    Self.referenceCount += 1
    if !Self.session.isRunning {
      Self.session.startRunning()
    }

    applyMetadataTypes()

    return true
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

  private func onPixelBuffer(_ buffer: CVPixelBuffer) {
    let rotated = rotatePixelBuffer(buffer, quarterTurns: quarterTurns)
    let data = rotated ?? buffer

    for camera in withState({ cameras }) {
      camera.updateFrame(data)
    }

    updateSize(data)

    let exposureStable = exposureStable()

    let hasCapture = withState {
      !pendingImmediateCaptureCallbacks.isEmpty
        || (!pendingCaptureCallbacks.isEmpty && exposureStable)
    }

    if hasCapture, let image = convertDataToImage(data) {
      var encodedData: [Bool: Data?] = [:]
      func capturedData(mirror: Bool) -> Data? {
        if let cached = encodedData[mirror] { return cached }
        let source =
          mirror ? convertDataToImage(data, mirror: true) : image
        let imageData = source?.jpegData(
          compressionQuality: CameraHandle.captureCompressionQuality
        )
        encodedData[mirror] = imageData
        return imageData
      }

      let callbacks: [PendingCapture] = withState {
        var callbacks = pendingImmediateCaptureCallbacks
        pendingImmediateCaptureCallbacks = []
        if exposureStable {
          callbacks += pendingCaptureCallbacks
          pendingCaptureCallbacks = []
        }
        return callbacks
      }

      if callbacks.contains(where: { $0.playSound }) {
        AudioServicesPlaySystemSound(Self.shutterSoundID)
      }

      for entry in callbacks {
        let imageData = capturedData(mirror: entry.mirror)
        DispatchQueue.main.async { entry.callback(imageData) }
      }
    }

    guard let rotated = rotated else { return }

    let startRecognition = withState {
      guard recognizeText, !recognitionInFlight else { return false }
      recognitionInFlight = true
      return true
    }
    guard startRecognition else { return }

    recognitionQueue.async { [weak self] in
      guard let self = self else { return }
      self.onTextImage(rotated)
      self.withState { self.recognitionInFlight = false }
    }
  }

  private func updateSize(_ data: CVPixelBuffer) {
    let width = Int32(CVPixelBufferGetWidth(data))
    let height = Int32(CVPixelBufferGetHeight(data))

    let changed = withState {
      let changed = currentSize?.0 != width || currentSize?.1 != height
      currentSize = (width, height)
      return changed
    }

    guard changed else { return }
    DispatchQueue.main.async { [self] in onCameraUpdated() }
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
    guard let device = withState({ self.device }) else { return false }
    return !device.isAdjustingExposure
      && abs(device.exposureTargetOffset) < Self.stableExposureOffset
  }

  @objc private func handleOrientationChange() {
    DispatchQueue.main.async { [self] in
      guard let quarterTurns = interfaceQuarterTurns() else { return }

      withState { currentQuarterTurns = quarterTurns }
    }
  }

  @objc private func handleSessionInterruptionEnded() {
    beginSessionRestart()
  }

  @objc private func handleSessionRuntimeError() {
    beginSessionRestart()
  }

  @objc private func handleApplicationDidBecomeActive() {
    beginSessionRestart()
  }

  private func beginSessionRestart() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard UIApplication.shared.applicationState != .background else {
        return
      }

      let start = self.withState {
        guard !self.restartInFlight else { return false }
        self.restartInFlight = true
        return true
      }
      guard start else { return }

      Self.sessionQueue.async { [weak self] in
        self?.restartSession(attempt: 0)
      }
    }
  }

  private func restartSession(attempt: Int) {
    if deviceRequired {
      if attempt == 0 {
        Self.session.startRunning()
      } else {
        closeDevice()
        _ = openDevice()
      }

      let recovered = Self.session.isRunning && withState { device != nil }
      if !recovered, attempt + 1 < Self.sessionRestartAttempts {
        Self.sessionQueue.asyncAfter(
          deadline: .now() + Self.sessionRestartDelay
        ) { [weak self] in
          self?.restartSession(attempt: attempt + 1)
        }
        return
      }
    }

    withState { restartInFlight = false }
  }

  private func interfaceQuarterTurns() -> Int32? {
    let applicationScenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.session.role == .windowApplication }
    let windowScene =
      applicationScenes.first { $0.activationState == .foregroundActive }
      ?? applicationScenes.first

    guard let interfaceOrientation = windowScene?.interfaceOrientation
    else { return nil }

    let quarterTurns: Int32? =
      switch interfaceOrientation {
      case .landscapeRight: 0
      case .portrait: 1
      case .landscapeLeft: 2
      case .portraitUpsideDown: 3
      default: nil
      }
    guard let quarterTurns = quarterTurns else { return nil }

    let isLandscape = interfaceOrientation.isLandscape
    let adjustment: Int32 = (direction == .front && isLandscape) ? 2 : 0

    return (quarterTurns + adjustment) % 4
  }

  private func closeDevice() {
    guard let device = withState({ self.device }) else { return }

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

    withState { self.device = nil }
    Self.referenceCount -= 1
    if Self.referenceCount == 0 {
      Self.session.stopRunning()
    }
  }

  #if targetEnvironment(simulator)
    private func showSimulatorWarning() {
      if let buffer = SimulatorWarning.pixelBuffer(for: direction) {
        for camera in withState({ cameras }) {
          camera.updateFrame(buffer)
        }

        updateSize(buffer)
      }

      let callbacks: [PendingCapture] = withState {
        let callbacks =
          pendingImmediateCaptureCallbacks + pendingCaptureCallbacks
        pendingImmediateCaptureCallbacks = []
        pendingCaptureCallbacks = []
        return callbacks
      }
      guard !callbacks.isEmpty else { return }

      let data = SimulatorWarning.imageData(for: direction)
      for entry in callbacks {
        DispatchQueue.main.async { entry.callback(data) }
      }
    }
  #endif

  private struct PendingCapture {
    let id: Int64
    let mirror: Bool
    let playSound: Bool
    let callback: (Data?) -> Void
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
    let (scanBarcodes, detectFaces) = withState {
      (self.scanBarcodes, self.detectFaces)
    }

    if scanBarcodes {
      let barcodes = metadataObjects.compactMap {
        ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
      }
      onBarcodes(barcodes)
    }
    if detectFaces {
      let hasFace = metadataObjects.contains { $0.type == .face }
      let changed = withState {
        guard self.detectFaces, hasFace != lastFace else { return false }
        lastFace = hasFace
        return true
      }
      if changed { onFace(hasFace) }
    }
  }
}
