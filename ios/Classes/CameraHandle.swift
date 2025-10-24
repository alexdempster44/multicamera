import AVFoundation
import Flutter
import UIKit

class CameraHandle: AVCaptureVideoDataOutput {
    let direction: Camera.Direction
    let onOrientationChanged: (() -> Void)
    let onRecognitionImage: ((UIImage) -> Void)
    let size = (1920, 1080)
    private(set) var quarterTurns: Int32 = 1

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue: DispatchQueue
    private var cameras: [Camera] = []
    private var lastFrame: CVPixelBuffer?
    private let frameSemaphore = DispatchSemaphore(value: 0)
    private var lastRecognitionTime: Date?

    init(
        direction: Camera.Direction,
        onOrientationChanged: @escaping (() -> Void),
        onRecognitionImage: @escaping ((UIImage) -> Void)
    ) {
        self.direction = direction
        self.onOrientationChanged = onOrientationChanged
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

        Task {
            do {
                try initialize()
            } catch (_) {}
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        session.stopRunning()
    }

    private func initialize() throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let device = selectDevice() else {
            session.commitConfiguration()
            return
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()

        handleOrientationChange()
    }

    func setCameras(_ cameras: [Camera]) {
        self.cameras = cameras
    }

    func captureImage() -> Data? {
        if lastFrame == nil {
            frameSemaphore.wait()
        }

        guard let pixelBuffer = lastFrame else { return nil }
        guard let image = convertDataToImage(pixelBuffer) else { return nil }

        return image.jpegData(compressionQuality: 0.9)
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
        lastFrame = data
        frameSemaphore.signal()
        for camera in cameras {
            camera.updateFrame(data)
        }

        let now = Date()
        let elapsed =
            lastRecognitionTime?.timeIntervalSince(now) ?? Double.infinity

        if abs(elapsed) < 0.2 { return }
        if let image = convertDataToImage(data, scale: 0.2) {
            self.lastRecognitionTime = now
            onRecognitionImage(image)
        }
    }

    private func convertDataToImage(
        _ data: CVPixelBuffer,
        scale: CGFloat = 1.0
    ) -> UIImage? {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let ci = CIImage(cvPixelBuffer: data).transformed(by: transform)

        let rect = ci.extent.integral
        guard let cg = CIContext().createCGImage(ci, from: rect) else {
            return nil
        }

        let turn = Int(((quarterTurns % 4) + 4) % 4)
        let orientation: UIImage.Orientation = [.up, .right, .down, .left][turn]

        return UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
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
            self.onOrientationChanged()
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
        Task { onPixelBuffer(data) }
    }
}
