import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'issuetracker_sdk.dart';
import 'issuetracker_sdk_platform_interface.dart';

/// MethodChannel implementation. The channel name `issuetracker_sdk`
/// must match the one registered on the native side.
class MethodChannelIssuetrackerSdk extends IssuetrackerSdkPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('issuetracker_sdk');

  // EventChannel for ADR-0003 Decision 9 onConfigurationError forwarding.
  // Native side sends the SdkErrorReason rawValue as a String when the
  // underlying SDK transitions to TERMINATED.
  @visibleForTesting
  final eventChannel =
      const EventChannel('issuetracker_sdk/configuration_error');

  Stream<SdkErrorReason>? _configurationErrorEvents;

  @override
  Stream<SdkErrorReason> get configurationErrorEvents {
    return _configurationErrorEvents ??= eventChannel
        .receiveBroadcastStream()
        .map<SdkErrorReason?>((dynamic raw) {
          if (raw is String) return SdkErrorReason.fromRawValue(raw);
          return null;
        })
        .where((r) => r != null)
        .cast<SdkErrorReason>();
  }

  @override
  Future<void> configure({
    required String apiKey,
    required bool shakeToReport,
    required bool longPressToReport,
    required bool enableCrashReporting,
  }) async {
    await methodChannel.invokeMethod<void>('configure', <String, dynamic>{
      'apiKey': apiKey,
      'shakeToReport': shakeToReport,
      'longPressToReport': longPressToReport,
      'enableCrashReporting': enableCrashReporting,
    });
  }

  @override
  Future<void> report() async {
    await methodChannel.invokeMethod<void>('report');
  }

  @override
  Future<void> identify(String name) async {
    await methodChannel.invokeMethod<void>('identify', <String, dynamic>{
      'name': name,
    });
  }

  @override
  Future<void> clearIdentity() async {
    await methodChannel.invokeMethod<void>('clearIdentity');
  }

  @override
  Future<void> recordAction(String action, {Map<String, String>? metadata}) async {
    await methodChannel.invokeMethod<void>('recordAction', <String, dynamic>{
      'action': action,
      'metadata': metadata,
    });
  }

  @override
  Future<void> testCrash() async {
    await methodChannel.invokeMethod<void>('testCrash');
  }
}
