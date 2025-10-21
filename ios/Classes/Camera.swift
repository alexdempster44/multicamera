import Flutter

class Camera: NSObject, FlutterTexture {
    private let plugin: MulticameraPlugin

    private(set) var id: Int64!
    var direction: Direction
    var paused: Bool

    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    init(
        plugin: MulticameraPlugin,
        direction: Direction,
        paused: Bool
    ) {
        self.plugin = plugin
        self.direction = direction
        self.paused = paused
        super.init()

        id = plugin.textures.register(self)
    }

    deinit {
        plugin.textures.unregisterTexture(id)
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }

        guard let pb = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(pb)
    }

    func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        defer { lock.unlock() }

        latestPixelBuffer = pixelBuffer
        plugin.textures.textureFrameAvailable(id)
    }

    enum Direction: Int32 {
        case front = 0
        case back = 1
    }
}

extension Camera.Direction: CaseIterable {}
