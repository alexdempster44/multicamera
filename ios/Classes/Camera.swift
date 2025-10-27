import Flutter

class Camera: NSObject, FlutterTexture {
    private let plugin: MulticameraPlugin

    private(set) var id: Int64!
    var direction: Direction
    var paused: Bool
    var recognizeText: Bool
    var scanBarcodes: Bool
    var detectFaces: Bool

    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    init(
        plugin: MulticameraPlugin,
        direction: Direction,
        paused: Bool,
        recognizeText: Bool,
        scanBarcodes: Bool,
        detectFaces: Bool
    ) {
        self.plugin = plugin
        self.direction = direction
        self.paused = paused
        self.recognizeText = recognizeText
        self.scanBarcodes = scanBarcodes
        self.detectFaces = detectFaces
        super.init()

        id = plugin.textures.register(self)
    }

    deinit {
        plugin.textures.unregisterTexture(id)
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        let buffer = latestPixelBuffer
        lock.unlock()

        guard let buffer = buffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        latestPixelBuffer = pixelBuffer
        lock.unlock()

        plugin.textures.textureFrameAvailable(id)
    }

    enum Direction: Int32 {
        case front = 0
        case back = 1
    }
}

extension Camera.Direction: CaseIterable {}
