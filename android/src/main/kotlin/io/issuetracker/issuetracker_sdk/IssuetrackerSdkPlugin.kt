package io.issuetracker.issuetracker_sdk

import android.app.Application
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.issuetracker.sdk.Issuetracker

class IssuetrackerSdkPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var application: Application? = null

    // EventSink for ADR-0003 Decision 9 onConfigurationError forwarding.
    // null before the Dart side has subscribed and after they cancel;
    // emitting against a null sink is a no-op.
    @Volatile
    private var configurationErrorSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "issuetracker_sdk")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "issuetracker_sdk/configuration_error")
        eventChannel.setStreamHandler(this)
        application = binding.applicationContext as? Application
    }

    // EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        configurationErrorSink = events
    }

    override fun onCancel(arguments: Any?) {
        configurationErrorSink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> {
                val app = application
                val apiKey = call.argument<String>("apiKey")
                if (app == null || apiKey == null) {
                    result.error("invalid-arguments", "configure requires apiKey", null)
                    return
                }
                val shake = call.argument<Boolean>("shakeToReport") ?: true
                val longPress = call.argument<Boolean>("longPressToReport") ?: true
                val crash = call.argument<Boolean>("enableCrashReporting") ?: true
                Issuetracker.configure(
                    application = app,
                    apiKey = apiKey,
                    shakeToReport = shake,
                    longPressToReport = longPress,
                    enableCrashReporting = crash,
                    onConfigurationError = { reason ->
                        // EventSink must be invoked on the platform
                        // thread (main on Android) per Flutter contract.
                        val sink = configurationErrorSink
                        if (sink != null) {
                            mainHandler.post { sink.success(reason.rawValue) }
                        }
                    },
                )
                result.success(null)
            }

            "report" -> {
                Issuetracker.report()
                result.success(null)
            }

            "identify" -> {
                call.argument<String>("name")?.let { Issuetracker.identify(it) }
                result.success(null)
            }

            "clearIdentity" -> {
                Issuetracker.clearIdentity()
                result.success(null)
            }

            "recordAction" -> {
                val action = call.argument<String>("action")
                if (action != null) {
                    @Suppress("UNCHECKED_CAST")
                    val metadata = call.argument<Map<String, String>>("metadata")
                    Issuetracker.recordAction(action, metadata)
                }
                result.success(null)
            }

            "testCrash" -> {
                // Throws — process dies before result.success would be sent.
                Issuetracker.testCrash()
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        configurationErrorSink = null
        application = null
    }
}
