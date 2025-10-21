import Flutter
import UIKit

public class MulticameraPlugin: NSObject, FlutterPlugin {
    let channel: FlutterMethodChannel
    let textures: FlutterTextureRegistry
    private(set) var registry: Registry!

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MulticameraPlugin(
            channel: FlutterMethodChannel(
                name: "multicamera",
                binaryMessenger: registrar.messenger()
            ),
            textures: registrar.textures()
        )
        registrar.addMethodCallDelegate(instance, channel: instance.channel)
    }

    init(channel: FlutterMethodChannel, textures: FlutterTextureRegistry) {
        self.channel = channel
        self.textures = textures
        super.init()

        self.registry = Registry(plugin: self)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let arguments = call.arguments as! [String: Any]

        switch call.method {
        case "registerCamera":
            let rawDirection = arguments["direction"] as! Int32
            let id = registry.registerCamera(
                direction: Camera.Direction(rawValue: rawDirection)!,
                paused: arguments["paused"] as! Bool
            )
            result(NSNumber(value: id))

        case "updateCamera":
            let rawDirection = arguments["direction"] as! Int32
            registry.updateCamera(
                id: arguments["id"] as! Int64,
                direction: Camera.Direction(rawValue: rawDirection)!,
                paused: arguments["paused"] as! Bool
            )
            result(nil)

        case "captureImage":
            let id = arguments["id"] as! Int64
            if let image = registry.captureImage(id: id) {
                result(FlutterStandardTypedData(bytes: image))
            } else {
                result(nil)
            }

        case "unregisterCamera":
            registry.unregisterCamera(id: arguments["id"] as! Int64)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
