import Flutter
import UIKit
import IssuetrackerSDK

public class IssuetrackerSdkPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "issuetracker_sdk",
            binaryMessenger: registrar.messenger(),
        )
        let instance = IssuetrackerSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let apiKey = args["apiKey"] as? String else {
                result(FlutterError(
                    code: "invalid-arguments",
                    message: "configure requires apiKey",
                    details: nil,
                ))
                return
            }
            let shake = args["shakeToReport"] as? Bool ?? true
            let longPress = args["longPressToReport"] as? Bool ?? true
            let crash = args["enableCrashReporting"] as? Bool ?? true
            DispatchQueue.main.async {
                Issuetracker.configure(
                    apiKey: apiKey,
                    shakeToReport: shake,
                    longPressToReport: longPress,
                    enableCrashReporting: crash,
                )
                result(nil)
            }

        case "report":
            DispatchQueue.main.async {
                Issuetracker.report()
                result(nil)
            }

        case "identify":
            let args = call.arguments as? [String: Any] ?? [:]
            if let name = args["name"] as? String {
                Issuetracker.identify(name: name)
            }
            result(nil)

        case "clearIdentity":
            Issuetracker.clearIdentity()
            result(nil)

        case "recordAction":
            let args = call.arguments as? [String: Any] ?? [:]
            if let action = args["action"] as? String {
                let metadata = args["metadata"] as? [String: String]
                Issuetracker.recordAction(action, metadata: metadata)
            }
            result(nil)

        case "testCrash":
            // Returns Never; result(nil) never reached.
            Issuetracker._testCrash()

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
