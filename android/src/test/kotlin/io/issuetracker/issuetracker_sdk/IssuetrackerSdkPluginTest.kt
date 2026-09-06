package io.issuetracker.issuetracker_sdk

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoMoreInteractions

/*
 * JVM unit tests for the plugin's method-channel dispatch layer.
 *
 * Scope: the branches that decode arguments and answer the Dart side
 * *without* reaching into the native SDK. Everything past those guards
 * calls `no.issuetracker.sdk.Issuetracker`, which needs a real Android
 * runtime — those paths belong in instrumentation tests on a device,
 * not here, and pretending otherwise would produce a test that passes
 * because it never ran the code.
 *
 * Run from example/android:
 *   ./gradlew :issuetracker_sdk:testDebugUnitTest
 * CI runs exactly that — see .github/workflows/ci.yml.
 */
internal class IssuetrackerSdkPluginTest {

    private fun result() = mock(MethodChannel.Result::class.java)

    /**
     * `getPlatformVersion` was removed when the plugin was rewritten
     * around configure/report/identify/setTesterToken. Anything the Dart
     * side asks for that the handler does not know must come back as
     * notImplemented, never as a silent success.
     */
    @Test
    fun unknownMethodIsReportedAsNotImplemented() {
        val result = result()

        IssuetrackerSdkPlugin().onMethodCall(MethodCall("getPlatformVersion", null), result)

        verify(result).notImplemented()
        verifyNoMoreInteractions(result)
    }

    @Test
    fun configureWithoutAnApiKeyFailsInsteadOfConfiguring() {
        val result = result()

        IssuetrackerSdkPlugin().onMethodCall(
            MethodCall("configure", mapOf("shakeToReport" to true)),
            result,
        )

        verify(result).error("invalid-arguments", "configure requires apiKey", null)
        verifyNoMoreInteractions(result)
    }

    /**
     * A plugin instance that has not been attached to an engine has no
     * Application to hand the native SDK. It must report that, rather
     * than call into `Issuetracker.configure` with a null context.
     */
    @Test
    fun configureBeforeAttachFailsInsteadOfConfiguring() {
        val result = result()

        IssuetrackerSdkPlugin().onMethodCall(
            MethodCall("configure", mapOf("apiKey" to "it_dev_test")),
            result,
        )

        verify(result).error("invalid-arguments", "configure requires apiKey", null)
        verifyNoMoreInteractions(result)
    }

    /**
     * The three handlers whose native call is guarded by a required
     * argument: with the argument missing they must answer success and
     * touch nothing, so a host app calling them defensively is a no-op
     * rather than a crash.
     */
    @Test
    fun identifyWithoutANameIsANoOp() {
        val result = result()

        IssuetrackerSdkPlugin().onMethodCall(MethodCall("identify", emptyMap<String, Any?>()), result)

        verify(result).success(null)
        verifyNoMoreInteractions(result)
    }

    @Test
    fun recordActionWithoutAnActionIsANoOp() {
        val result = result()

        IssuetrackerSdkPlugin().onMethodCall(
            MethodCall("recordAction", mapOf("metadata" to mapOf("k" to "v"))),
            result,
        )

        verify(result).success(null)
        verifyNoMoreInteractions(result)
    }

    @Test
    fun setTesterTokenWithoutATokenIsANoOp() {
        val result = result()

        IssuetrackerSdkPlugin().onMethodCall(
            MethodCall("setTesterToken", mapOf("expiresAtMillis" to 1_700_000_000_000L)),
            result,
        )

        verify(result).success(null)
        verifyNoMoreInteractions(result)
    }
}
