import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';
import 'package:issuetracker_sdk/issuetracker_sdk_method_channel.dart';
import 'package:issuetracker_sdk/issuetracker_sdk_platform_interface.dart';

// ITD-163 — one termination predicate per platform.
//
// The fleet rule: every path that decides "is this failure terminal?"
// asks the same question, by the same name, over the same wire values.
// On Dart that predicate is `SdkErrorReason.isTerminal`
// (`isSdkErrorTerminal` in sdk-web / sdk-react-native, `isTerminal` in
// sdk-android / sdk-ios). `!isRecoverable` is NOT a synonym: the
// ADR-0005 tester-gating reasons are non-recoverable and deliberately
// non-terminal, so a path that substitutes one for the other kills an
// install the other four SDKs keep alive.
//
// Flutter has two paths a reason travels:
//   1. the transport — EventChannel envelope -> String -> SdkErrorReason
//      (MethodChannelIssuetrackerSdk.configurationErrorEvents), and
//   2. the facade — Issuetracker.configure()'s onConfigurationError gate.
// This file drives raw native payloads through BOTH, unmocked, and
// pins that what the host ends up seeing is exactly the set for which
// `isTerminal` is true — no more (a false "your project is gone") and
// no less (a swallowed termination).

const String _eventChannelName = 'issuetracker_sdk/configuration_error';
const MethodCodec _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelIssuetrackerSdk platform;

  /// Pushes one payload onto the EventChannel exactly as the iOS /
  /// Android plugin does (`sink.success(reason.rawValue)`).
  Future<void> emitFromNative(Object? payload) async {
    await messenger.handlePlatformMessage(
      _eventChannelName,
      _codec.encodeSuccessEnvelope(payload),
      (ByteData? _) {},
    );
  }

  setUp(() {
    platform = MethodChannelIssuetrackerSdk();
    IssuetrackerSdkPlatform.instance = platform;
    messenger.setMockMethodCallHandler(
      platform.methodChannel,
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannelName),
      (MethodCall call) async => null,
    );
  });

  tearDown(() async {
    // Drop the facade's static subscription before the next test.
    await Issuetracker.configure(apiKey: 'it_test_teardown');
    messenger.setMockMethodCallHandler(platform.methodChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannelName),
      null,
    );
  });

  test('the host sees exactly the terminal reasons, end to end', () async {
    final seen = <SdkErrorReason>[];
    await Issuetracker.configure(
      apiKey: 'it_test_key',
      onConfigurationError: seen.add,
    );
    await null; // let the EventChannel `listen` flush

    // Every canonical wire value, as the server spells it.
    for (final reason in SdkErrorReason.values) {
      await emitFromNative(reason.rawValue);
    }

    expect(
      seen.toSet(),
      equals(SdkErrorReason.values.where((r) => r.isTerminal).toSet()),
    );
    expect(
      seen,
      equals(<SdkErrorReason>[
        SdkErrorReason.projectDeleted,
        SdkErrorReason.projectNotFound,
        SdkErrorReason.apiKeyRevoked,
        SdkErrorReason.workspaceSuspended,
        SdkErrorReason.invalidApiKey,
      ]),
      reason: 'ADR-0003 Decision 9 point 4 — these five, in wire order',
    );
  });

  test('a non-terminal reason on the wire reaches nobody', () async {
    final seen = <SdkErrorReason>[];
    await Issuetracker.configure(
      apiKey: 'it_test_key',
      onConfigurationError: seen.add,
    );
    await null;

    // Recoverable, and non-recoverable-but-non-terminal. Neither means
    // the project is gone, so neither may be reported as such.
    await emitFromNative('quota_exceeded');
    await emitFromNative('transient');
    await emitFromNative('tester_attestation_required');
    await emitFromNative('tester_token_invalid');

    expect(seen, isEmpty);
  });

  test('an unknown reason string is dropped, never guessed at', () async {
    final seen = <SdkErrorReason>[];
    await Issuetracker.configure(
      apiKey: 'it_test_key',
      onConfigurationError: seen.add,
    );
    await null;

    await emitFromNative('workspace_deleted'); // never a wire value
    await emitFromNative('PROJECT_DELETED'); // wrong casing
    await emitFromNative(null);
    await emitFromNative(42);

    expect(seen, isEmpty);
  });

  test('the transport itself stays unfiltered', () async {
    // The gate belongs to the facade, deliberately: the platform
    // interface is a transport, and a platform implementation (or a
    // future in-Dart lifecycle consumer) must be able to see every
    // reason the native side emitted. If the gate ever moves down
    // here, move this expectation with it — what must never happen is
    // BOTH layers claiming the other one filters.
    final raw = <SdkErrorReason>[];
    final sub = platform.configurationErrorEvents.listen(raw.add);
    await null;

    await emitFromNative('quota_exceeded');
    await emitFromNative('project_deleted');
    await sub.cancel();

    expect(
      raw,
      equals(<SdkErrorReason>[
        SdkErrorReason.quotaExceeded,
        SdkErrorReason.projectDeleted,
      ]),
    );
  });
}
