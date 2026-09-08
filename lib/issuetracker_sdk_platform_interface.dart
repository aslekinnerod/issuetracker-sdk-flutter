import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'issuetracker_sdk.dart';
import 'issuetracker_sdk_method_channel.dart';

abstract class IssuetrackerSdkPlatform extends PlatformInterface {
  IssuetrackerSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static IssuetrackerSdkPlatform _instance = MethodChannelIssuetrackerSdk();

  static IssuetrackerSdkPlatform get instance => _instance;

  static set instance(IssuetrackerSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> configure({
    required String apiKey,
    required bool shakeToReport,
    required bool longPressToReport,
    required bool accessibilityAction,
    required bool showReportButton,
    required bool enableCrashReporting,
    required bool showOnboarding,
    TerminatedUiStrings? terminatedUI,
  }) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Future<void> showOnboarding() {
    throw UnimplementedError('showOnboarding() has not been implemented.');
  }

  /// Raw transport for the native SDK's configuration-error events:
  /// whatever reason the native side emits, decoded to
  /// [SdkErrorReason]. In practice the native SDKs raise it only on
  /// the one-way OK -> TERMINATED transition, so it emits at most once
  /// for the lifetime of a deployed install — but this getter does not
  /// enforce that. The terminal gate ([SdkErrorReason.isTerminal])
  /// lives in [Issuetracker.configure], which is the surface host apps
  /// subscribe through; anything reading this stream directly gets the
  /// unfiltered feed and owns the same classification decision. See
  /// ADR-0003 Decision 9.
  ///
  /// The implementation backs onto an EventChannel; subscribers are
  /// responsible for cancelling when they're done (the
  /// [Issuetracker.configure] facade manages its own subscription).
  Stream<SdkErrorReason> get configurationErrorEvents {
    throw UnimplementedError(
      'configurationErrorEvents has not been implemented.',
    );
  }

  Future<void> report() {
    throw UnimplementedError('report() has not been implemented.');
  }

  Future<void> identify(String name) {
    throw UnimplementedError('identify() has not been implemented.');
  }

  Future<void> clearIdentity() {
    throw UnimplementedError('clearIdentity() has not been implemented.');
  }

  Future<void> recordAction(String action, {Map<String, String>? metadata}) {
    throw UnimplementedError('recordAction() has not been implemented.');
  }

  Future<void> setTesterToken(String token, {int? expiresAtMillis}) {
    throw UnimplementedError('setTesterToken() has not been implemented.');
  }

  Future<void> clearTesterToken() {
    throw UnimplementedError('clearTesterToken() has not been implemented.');
  }

  Future<void> testCrash() {
    throw UnimplementedError('testCrash() has not been implemented.');
  }
}
