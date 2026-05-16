import 'dart:async';

import 'issuetracker_sdk_platform_interface.dart';

/// Issue classification sent to the server.
enum IssueReportType {
  bug,
  task,
  story;

  String get wireValue => switch (this) {
        IssueReportType.bug => 'bug',
        IssueReportType.task => 'task',
        IssueReportType.story => 'story',
      };
}

/// Machine-readable reason for an SDK-callable failure. The `rawValue`
/// strings match the server-side `SdkErrorReasonSchema` in
/// `@issuetracker/shared` byte-for-byte — they are the wire contract
/// across all five SDKs. See ADR-0003 Decision 9.
///
/// Recoverable reasons ([SdkErrorReason.quotaExceeded],
/// [SdkErrorReason.transient]) keep the SDK in the OK state. Non-
/// recoverable reasons transition the underlying native SDK to a
/// one-way TERMINATED state — recovery requires a fresh
/// [Issuetracker.configure] call (in practice an app relaunch).
enum SdkErrorReason {
  projectDeleted('project_deleted'),
  projectNotFound('project_not_found'),
  apiKeyRevoked('api_key_revoked'),
  workspaceSuspended('workspace_suspended'),
  invalidApiKey('invalid_api_key'),
  quotaExceeded('quota_exceeded'),
  transient('transient');

  const SdkErrorReason(this.rawValue);
  final String rawValue;

  bool get isRecoverable =>
      this == SdkErrorReason.quotaExceeded || this == SdkErrorReason.transient;

  static SdkErrorReason? fromRawValue(String? raw) {
    if (raw == null) return null;
    for (final r in SdkErrorReason.values) {
      if (r.rawValue == raw) return r;
    }
    return null;
  }
}

/// Public facade for the Issuetracker Flutter SDK. Wraps the native
/// iOS + Android Issuetracker SDKs — UI, screenshot capture, shake
/// detection, and crash reporting all run on the native side.
class Issuetracker {
  Issuetracker._();

  static StreamSubscription<SdkErrorReason>? _configErrorSub;

  /// Call once at app start (typically from `main()` after
  /// `WidgetsFlutterBinding.ensureInitialized()`). Environment
  /// (production vs. staging) is derived from the key prefix —
  /// there is no endpoint to configure.
  ///
  /// [onConfigurationError] is invoked once when the underlying native
  /// SDK transitions to the terminated state because the server
  /// signalled a non-recoverable failure (project deleted, API key
  /// revoked, workspace suspended, etc.). Default behaviour is silent;
  /// host apps may forward this to their own telemetry. Once invoked,
  /// the SDK will not call the report endpoint again for the lifetime
  /// of this install — recovery requires a fresh [configure] call.
  /// See ADR-0003 Decision 9.
  static Future<void> configure({
    required String apiKey,
    bool shakeToReport = true,
    bool longPressToReport = true,
    bool enableCrashReporting = true,
    void Function(SdkErrorReason reason)? onConfigurationError,
  }) async {
    // Tear down any prior subscription so a re-configure() with a
    // different callback doesn't end up firing both. Subsequent
    // configure() calls are uncommon but the SDK doesn't forbid them.
    await _configErrorSub?.cancel();
    _configErrorSub = null;

    if (onConfigurationError != null) {
      _configErrorSub = IssuetrackerSdkPlatform.instance
          .configurationErrorEvents
          .listen(onConfigurationError);
    }

    await IssuetrackerSdkPlatform.instance.configure(
      apiKey: apiKey,
      shakeToReport: shakeToReport,
      longPressToReport: longPressToReport,
      enableCrashReporting: enableCrashReporting,
    );
  }

  /// Programmatic trigger — for an in-app "Report a bug" button.
  static Future<void> report() => IssuetrackerSdkPlatform.instance.report();

  /// Skip the "What should we call you?" prompt.
  static Future<void> identify(String name) =>
      IssuetrackerSdkPlatform.instance.identify(name);

  static Future<void> clearIdentity() =>
      IssuetrackerSdkPlatform.instance.clearIdentity();

  /// Record one user action (max 5 retained, attached to next report).
  static Future<void> recordAction(
    String action, {
    Map<String, String>? metadata,
  }) {
    return IssuetrackerSdkPlatform.instance
        .recordAction(action, metadata: metadata);
  }

  /// Throws inside the native layer. SDK integration testing only.
  static Future<void> testCrash() =>
      IssuetrackerSdkPlatform.instance.testCrash();
}
