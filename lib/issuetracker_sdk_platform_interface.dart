import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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
    required String endpoint,
    required bool shakeToReport,
    required bool longPressToReport,
    required bool enableCrashReporting,
  }) {
    throw UnimplementedError('configure() has not been implemented.');
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

  Future<void> testCrash() {
    throw UnimplementedError('testCrash() has not been implemented.');
  }
}
