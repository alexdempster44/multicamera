import UIKit

class Registry {
    private let plugin: MulticameraPlugin

    private(set) var cameras: [Int64: Camera] = [:]
    private(set) var cameraHandles: [Camera.Direction: CameraHandle] = [:]

    init(plugin: MulticameraPlugin) {
        self.plugin = plugin
    }

    func registerCamera(direction: Camera.Direction, paused: Bool) -> Int64 {
        let camera = Camera(
            plugin: plugin,
            direction: direction,
            paused: paused
        )

        cameras[camera.id] = camera
        reconcile()

        return camera.id
    }

    func updateCamera(id: Int64, direction: Camera.Direction, paused: Bool) {
        guard let camera = cameras[id] else { return }

        camera.direction = direction
        camera.paused = paused

        reconcile()
    }

    func captureImage(id: Int64) -> Data? {
        guard let camera = cameras[id] else { return nil }
        guard let handle = cameraHandles[camera.direction] else { return nil }

        return handle.captureImage()
    }

    func unregisterCamera(id: Int64) {
        cameras.removeValue(forKey: id)
        reconcile()
    }

    private func reconcile() {
        for direction in Camera.Direction.allCases {
            let cameras = self.cameras.values.filter {
                $0.direction == direction
            }
            let handleRequired = !cameras.isEmpty

            if handleRequired {
                let handle =
                    cameraHandles[direction]
                    ?? {
                        let newHandle = CameraHandle(
                            direction: direction,
                            onOrientationChanged: { [weak self] in
                                self?.updateFlutterCameras(direction)
                            }
                        )

                        cameraHandles[direction] = newHandle
                        return newHandle
                    }()

                handle.setCameras(cameras.filter { !$0.paused })
            } else {
                cameraHandles.removeValue(forKey: direction)
            }
            self.updateFlutterCameras(direction)
        }
    }

    private func updateFlutterCameras(_ direction: Camera.Direction) {
        guard let handle = cameraHandles[direction] else { return }
        let cameras = self.cameras.values.filter { $0.direction == direction }

        for camera in cameras {
            guard let id = camera.id else { continue }
            DispatchQueue.main.async {
                self.plugin.channel.invokeMethod(
                    "updateCamera",
                    arguments: [
                        "id": id,
                        "width": handle.size.0,
                        "height": handle.size.1,
                        "quarterTurns": handle.quarterTurns,
                    ]
                )
            }
        }
    }
}
