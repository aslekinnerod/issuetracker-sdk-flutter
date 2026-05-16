import Flutter
import UIKit
import IssuetrackerSDK

public class IssuetrackerSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    // EventChannel sink for ADR-0003 Decision 9 onConfigurationError
    // forwarding. nil before the Dart side has subscribed and after
    // they cancel; emitting against a nil sink is a no-op.
    private var configurationErrorSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "issuetracker_sdk",
            binaryMessenger: registrar.messenger(),
        )
        let eventChannel = FlutterEventChannel(
            name: "issuetracker_sdk/configuration_error",
            binaryMessenger: registrar.messenger(),
        )
        let instance = IssuetrackerSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        configurationErrorSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        configurationErrorSink = nil
        return nil
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
            DispatchQueue.main.async { [weak self] in
                Issuetracker.configure(
                    apiKey: apiKey,
                    shakeToReport: shake,
                    longPressToReport: longPress,
                    enableCrashReporting: crash,
                    onConfigurationError: { reason in
                        // EventSink must be invoked on the platform
                        // thread (main on iOS) per Flutter contract.
                        DispatchQueue.main.async {
                            self?.configurationErrorSink?(reason.rawValue)
                        }
                    },
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
