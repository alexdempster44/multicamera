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
        Task { reconcile() }

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

        Task { reconcile() }
    }

    func captureImage(id: Int64, _ callback: @escaping (Data?) -> Void) {
        guard let camera = cameras[id] else {
            callback(nil)
            return
        }
        guard let handle = cameraHandles[camera.direction] else {
            callback(nil)
            return
        }

        handle.captureImage(callback)
    }

    func unregisterCamera(id: Int64) {
        cameras.removeValue(forKey: id)
        Task { reconcile() }
    }

    private func reconcile() {
        for direction in Camera.Direction.allCases {
            let cameras = cameras.values.filter { $0.direction == direction }
            let handleRequired = !cameras.isEmpty

            if handleRequired {
                let handle =
                    cameraHandles[direction]
                    ?? createHandle(direction: direction)

                handle.setCameras(cameras.filter { !$0.paused })
            } else {
                cameraHandles.removeValue(forKey: direction)
            }
            self.updateFlutterCameras(direction)
        }
    }

    private func createHandle(direction: Camera.Direction) -> CameraHandle {
        let handle = CameraHandle(
            direction: direction,
            onCameraUpdated: { [weak self] in
                self?.updateFlutterCameras(direction)
            },
            onRecognitionImage: { [weak self] image in
                self?.onRecognitionImage(image, direction: direction)
            }
        )

        cameraHandles[direction] = handle
        return handle
    }

    private func updateFlutterCameras(_ direction: Camera.Direction) {
        guard let handle = cameraHandles[direction] else { return }
        let cameras = cameras.values.filter { $0.direction == direction }

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

    private func onRecognitionImage(
        _ image: UIImage,
        direction: Camera.Direction
    ) {
        let cameras = cameras.values.filter {
            $0.direction == direction && !$0.paused
        }

        let recognizeText = cameras.contains { $0.recognizeText }
        let scanBarcodes = cameras.contains { $0.scanBarcodes }
        let detectFaces = cameras.contains { $0.detectFaces }

        ImageRecognition.recognizeImage(
            image,
            recognizeText: recognizeText,
            scanBarcodes: scanBarcodes,
            detectFaces: detectFaces,
            onResults: { [weak self] results in
                guard let self = self else { return }
                let cameras = self.cameras.values.filter {
                    $0.direction == direction && !$0.paused
                }

                for camera in cameras {
                    guard let id = camera.id else { continue }
                    DispatchQueue.main.async {
                        self.plugin.channel.invokeMethod(
                            "recognitionResults",
                            arguments: [
                                "id": id,
                                "text": results.text as Any,
                                "barcodes": results.barcodes as Any,
                                "face": results.face as Any,
                            ]
                        )
                    }
                }
            }
        )
    }
}
