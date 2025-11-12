import AVFoundation
import Flutter
import UIKit

class CameraHandle: NSObject {
    let direction: Camera.Direction
    let onCameraUpdated: (() -> Void)
    let onRecognitionImage: ((UIImage) -> Void)
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
    private static let recognitionImageScale: CGFloat = 0.2
    private static let stableExposureOffset: Float = 0.5

    private let output = AVCaptureVideoDataOutput()
    private let queue: DispatchQueue
    private let ciContext = CIContext()
    private var cameras: [Camera] = []
    private var pendingCaptureCallbacks: [(Data?) -> Void] = []
    private var lastRecognitionTime: Date?

    init(
        direction: Camera.Direction,
        onCameraUpdated: @escaping (() -> Void),
        onRecognitionImage: @escaping ((UIImage) -> Void)
    ) {
        self.direction = direction
        self.onCameraUpdated = onCameraUpdated
        self.onRecognitionImage = onRecognitionImage
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
        for callback in pendingCaptureCallbacks {
            callback(nil)
        }
        pendingCaptureCallbacks = []

        Self.sessionQueue.async { [self] in self.closeDevice() }

        NotificationCenter.default.removeObserver(self)
    }

    func setCameras(_ cameras: [Camera]) {
        self.cameras = cameras
        setupDevice()
    }

    func captureImage(_ callback: @escaping (Data?) -> Void) {
        pendingCaptureCallbacks.append(callback)
        setupDevice()
    }

    private func setupDevice() {
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !cameras.isEmpty || !pendingCaptureCallbacks.isEmpty {
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

        Self.session.commitConfiguration()

        self.device = device
        Self.referenceCount += 1
        if Self.referenceCount == 1 {
            Self.session.startRunning()
        }

        let dimensions = device.activeFormat.formatDescription.dimensions
        size = (dimensions.width, dimensions.height)

        handleOrientationChange()
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

        if !pendingCaptureCallbacks.isEmpty && exposureStable(),
            let image = convertDataToImage(data)
        {
            let imageData = image.jpegData(
                compressionQuality: CameraHandle.captureCompressionQuality
            )
            for callback in pendingCaptureCallbacks {
                Task { callback(imageData) }
            }
            pendingCaptureCallbacks = []

        }

        let now = Date()
        let elapsed = now.timeIntervalSince(
            lastRecognitionTime ?? Date.distantPast
        )

        if elapsed < Self.recognitionThrottleInterval { return }
        if let image = convertDataToImage(
            data,
            scale: Self.recognitionImageScale
        ) {
            self.lastRecognitionTime = now
            Task { onRecognitionImage(image) }
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
        scale: CGFloat = 1.0
    ) -> UIImage? {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let ciImage = CIImage(cvPixelBuffer: data).transformed(by: transform)

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
