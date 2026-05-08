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

/// Public facade for the Issuetracker Flutter SDK. Wraps the native
/// iOS + Android Issuetracker SDKs — UI, screenshot capture, shake
/// detection, and crash reporting all run on the native side.
class Issuetracker {
  Issuetracker._();

  /// Call once at app start (typically from `main()` after
  /// `WidgetsFlutterBinding.ensureInitialized()`).
  static Future<void> configure({
    required String apiKey,
    required String endpoint,
    bool shakeToReport = true,
    bool longPressToReport = true,
    bool enableCrashReporting = true,
  }) {
    return IssuetrackerSdkPlatform.instance.configure(
      apiKey: apiKey,
      endpoint: endpoint,
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
