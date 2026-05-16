package io.issuetracker.issuetracker_sdk

import android.app.Application
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.issuetracker.sdk.Issuetracker

class IssuetrackerSdkPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var application: Application? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "issuetracker_sdk")
        channel.setMethodCallHandler(this)
        application = binding.applicationContext as? Application
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
        application = null
    }
}
