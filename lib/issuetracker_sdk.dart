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
  transient('transient'),
  testerAttestationRequired('tester_attestation_required'),
  testerTokenInvalid('tester_token_invalid');

  const SdkErrorReason(this.rawValue);
  final String rawValue;

  bool get isRecoverable =>
      this == SdkErrorReason.quotaExceeded || this == SdkErrorReason.transient;

  /// Whether this reason must flip the SDK into one-way TERMINATED.
  /// Tester-gating rejections (ADR-0005) are non-recoverable —
  /// retrying the same request cannot succeed — but NOT terminal:
  /// the project is alive and the key is valid; only this install
  /// lacks (valid) attestation.
  bool get isTerminal => switch (this) {
    SdkErrorReason.quotaExceeded ||
    SdkErrorReason.transient ||
    SdkErrorReason.testerAttestationRequired ||
    SdkErrorReason.testerTokenInvalid => false,
    SdkErrorReason.projectDeleted ||
    SdkErrorReason.projectNotFound ||
    SdkErrorReason.apiKeyRevoked ||
    SdkErrorReason.workspaceSuspended ||
    SdkErrorReason.invalidApiKey => true,
  };

  static SdkErrorReason? fromRawValue(String? raw) {
    if (raw == null) return null;
    for (final r in SdkErrorReason.values) {
      if (r.rawValue == raw) return r;
    }
    return null;
  }
}

/// Strings shown when the underlying native SDK has been terminated
/// and a test-cohort user opens the reporting surface. ADR-0003
/// Decision 9 mandates a localised terminal message; English is the
/// built-in default on the native side, and host apps may inject
/// translations via [Issuetracker.configure].
///
/// Each field is optional — fields the host doesn't override fall
/// back to English. A missing instance falls back to all-English.
class TerminatedUiStrings {
  /// Big headline. Default: `"Bug reporting is no longer available."`
  final String? title;

  /// One-line follow-up. Default: `"Contact your team."`
  final String? subtitle;

  /// Close-button label. Default: `"Close"`.
  final String? closeLabel;

  const TerminatedUiStrings({this.title, this.subtitle, this.closeLabel});
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
  ///
  /// If [showOnboarding] is `true`, presents a one-time popover on
  /// first launch teaching the user which gestures trigger the
  /// reporter — only the gestures currently enabled are shown.
  /// Persisted per install by the underlying native iOS / Android
  /// SDKs, so the popover never appears twice unless [showOnboarding]
  /// (the method) is called explicitly. With both [shakeToReport] and
  /// [longPressToReport] disabled the popover is silently skipped.
  /// Defaults to `false`.
  ///
  /// If [accessibilityAction] is `true`, the underlying native SDK
  /// registers a screen-reader custom action ("Report a bug") while
  /// VoiceOver / TalkBack is running, giving screen-reader users a
  /// gesture-free path to the reporter (the OS screen reader typically
  /// claims the shake and multi-finger gestures). See ADR-0008
  /// Decision 2. Defaults to `false`.
  ///
  /// If [showReportButton] is `true`, the underlying native SDK
  /// renders a small floating "Report a bug" button — a one-line path
  /// to a visible, WCAG-conformant entry point for hosts that don't
  /// wire their own control to [report]. See ADR-0008 Decision 3.
  /// Defaults to `false`.
  static Future<void> configure({
    required String apiKey,
    bool shakeToReport = true,
    bool longPressToReport = true,
    bool accessibilityAction = false,
    bool showReportButton = false,
    bool enableCrashReporting = true,
    void Function(SdkErrorReason reason)? onConfigurationError,
    bool showOnboarding = false,
    TerminatedUiStrings? terminatedUI,
  }) async {
    // Swap the subscription synchronously — claim the slot and hand
    // over the old subscription in the same turn of the event loop —
    // so a re-configure() with a different callback doesn't end up
    // firing both. Subsequent configure() calls are uncommon but the
    // SDK doesn't forbid them, and two overlapping un-awaited calls
    // (app start-up + a settings toggle) must not each install a
    // listener. Awaiting the cancel first would yield between read and
    // write and leak the earlier subscription. ADR-0003 Decision 9.
    final StreamSubscription<SdkErrorReason>? previous = _configErrorSub;
    _configErrorSub =
        onConfigurationError == null
            ? null
            : IssuetrackerSdkPlatform.instance.configurationErrorEvents.listen(
              onConfigurationError,
            );
    // StreamSubscription.cancel() detaches the listener synchronously;
    // the future only completes the platform-side teardown, so no
    // event can reach both callbacks in between.
    await previous?.cancel();

    await IssuetrackerSdkPlatform.instance.configure(
      apiKey: apiKey,
      shakeToReport: shakeToReport,
      longPressToReport: longPressToReport,
      accessibilityAction: accessibilityAction,
      showReportButton: showReportButton,
      enableCrashReporting: enableCrashReporting,
      showOnboarding: showOnboarding,
      terminatedUI: terminatedUI,
    );
  }

  /// Programmatic trigger — for an in-app "Report a bug" button.
  static Future<void> report() => IssuetrackerSdkPlatform.instance.report();

  /// Re-presents the onboarding popover regardless of whether it has
  /// been shown before on this install. Intended for a "Show
  /// introduction again"-style entry in the host app's settings.
  /// No-op if no gestures are enabled.
  static Future<void> showOnboarding() =>
      IssuetrackerSdkPlatform.instance.showOnboarding();

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
    return IssuetrackerSdkPlatform.instance.recordAction(
      action,
      metadata: metadata,
    );
  }

  /// Stores a tester attestation token (ADR-0005). On projects in
  /// testers-only mode this is what unlocks the report triggers and
  /// gets reports past the server; in open mode it stamps reports
  /// with the tester's identity. The token will normally arrive from
  /// the native companion-app transports; this API is the manual
  /// injection point until those ship (and for integration tests).
  static Future<void> setTesterToken(String token, {int? expiresAtMillis}) {
    return IssuetrackerSdkPlatform.instance.setTesterToken(
      token,
      expiresAtMillis: expiresAtMillis,
    );
  }

  /// Removes the stored tester token. On testers-only projects the
  /// gesture triggers go inert again from the next gesture.
  static Future<void> clearTesterToken() =>
      IssuetrackerSdkPlatform.instance.clearTesterToken();

  /// Throws inside the native layer. SDK integration testing only.
  static Future<void> testCrash() =>
      IssuetrackerSdkPlatform.instance.testCrash();
}
