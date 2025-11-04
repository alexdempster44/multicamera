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
        guard let arguments = call.arguments as? [String: Any] else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Expected arguments as [String: Any]",
                    details: nil
                )
            )
            return
        }

        switch call.method {
        case "registerCamera":
            guard let rawDirection = arguments["direction"] as? Int32,
                let direction = Camera.Direction(rawValue: rawDirection),
                let paused = arguments["paused"] as? Bool,
                let recognizeText = arguments["recognizeText"] as? Bool,
                let scanBarcodes = arguments["scanBarcodes"] as? Bool,
                let detectFaces = arguments["detectFaces"] as? Bool
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid arguments for registerCamera",
                        details: nil
                    )
                )
                return
            }
            let id = registry.registerCamera(
                direction: direction,
                paused: paused,
                recognizeText: recognizeText,
                scanBarcodes: scanBarcodes,
                detectFaces: detectFaces
            )
            result(NSNumber(value: id))

        case "updateCamera":
            guard let id = arguments["id"] as? Int64,
                let rawDirection = arguments["direction"] as? Int32,
                let direction = Camera.Direction(rawValue: rawDirection),
                let paused = arguments["paused"] as? Bool,
                let recognizeText = arguments["recognizeText"] as? Bool,
                let scanBarcodes = arguments["scanBarcodes"] as? Bool,
                let detectFaces = arguments["detectFaces"] as? Bool
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid arguments for updateCamera",
                        details: nil
                    )
                )
                return
            }
            registry.updateCamera(
                id: id,
                direction: direction,
                paused: paused,
                recognizeText: recognizeText,
                scanBarcodes: scanBarcodes,
                detectFaces: detectFaces
            )
            result(nil)

        case "captureImage":
            guard let id = arguments["id"] as? Int64 else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid arguments for captureImage",
                        details: nil
                    )
                )
                return
            }
            registry.captureImage(
                id: id,
                { image in
                    if let image = image {
                        result(FlutterStandardTypedData(bytes: image))
                    } else {
                        result(nil)
                    }
                }
            )

        case "unregisterCamera":
            guard let id = arguments["id"] as? Int64 else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid arguments for unregisterCamera",
                        details: nil
                    )
                )
                return
            }
            registry.unregisterCamera(id: id)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
