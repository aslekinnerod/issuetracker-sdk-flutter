import Flutter
import UIKit
import XCTest

@testable import issuetracker_sdk

// Unit tests for the plugin's method-channel dispatch layer, mirroring
// android/src/test/kotlin/.../IssuetrackerSdkPluginTest.kt.
//
// Scope: the branches that decode arguments and answer the Dart side
// *without* reaching into the native SDK. Everything past those guards
// calls `IssuetrackerSDK`, which needs a running app — those paths
// belong in UI/integration tests, not here.
//
// Run from example/ios:
//   xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
//     -destination 'platform=iOS Simulator,name=iPhone 16'
// CI runs exactly that — see .github/workflows/ci.yml.
class RunnerTests: XCTestCase {

  /// `getPlatformVersion` was removed when the plugin was rewritten
  /// around configure/report/identify/setTesterToken. Anything the Dart
  /// side asks for that the handler does not know must come back as
  /// notImplemented, never as a silent success.
  func testUnknownMethodIsReportedAsNotImplemented() {
    let plugin = IssuetrackerSdkPlugin()
    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue((result as AnyObject) === FlutterMethodNotImplemented)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testConfigureWithoutAnApiKeyFailsInsteadOfConfiguring() {
    let plugin = IssuetrackerSdkPlugin()
    let call = FlutterMethodCall(
      methodName: "configure",
      arguments: ["shakeToReport": true]
    )

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "invalid-arguments")
      XCTAssertEqual(error?.message, "configure requires apiKey")
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  /// The handlers whose native call is guarded by a required argument:
  /// with the argument missing they must answer success and touch
  /// nothing, so a host app calling them defensively is a no-op rather
  /// than a crash.
  func testIdentifyWithoutANameIsANoOp() {
    let plugin = IssuetrackerSdkPlugin()
    let call = FlutterMethodCall(methodName: "identify", arguments: [String: Any]())

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertNil(result)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testRecordActionWithoutAnActionIsANoOp() {
    let plugin = IssuetrackerSdkPlugin()
    let call = FlutterMethodCall(
      methodName: "recordAction",
      arguments: ["metadata": ["k": "v"]]
    )

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertNil(result)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testSetTesterTokenWithoutATokenIsANoOp() {
    let plugin = IssuetrackerSdkPlugin()
    let call = FlutterMethodCall(
      methodName: "setTesterToken",
      arguments: ["expiresAtMillis": NSNumber(value: 1_700_000_000_000)]
    )

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertNil(result)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
