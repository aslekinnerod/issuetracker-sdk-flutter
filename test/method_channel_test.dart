import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';
import 'package:issuetracker_sdk/issuetracker_sdk_method_channel.dart';

// Wire-level tests for the platform-channel implementation: the
// EventChannel that carries ADR-0003 Decision 9 TERMINATED signals
// from native to Dart, and the configure() payload the native plugins
// parse.
//
// The mock binary messenger plays the role of the iOS / Android
// plugin, so what is under test here is the real decoding path:
// StandardMethodCodec envelope -> raw String -> SdkErrorReason.

const String _eventChannelName = 'issuetracker_sdk/configuration_error';
const MethodCodec _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelIssuetrackerSdk platform;
  late List<MethodCall> methodLog;
  late List<MethodCall> streamLog;

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Simulates the native side pushing one event onto the EventChannel.
  Future<void> emitFromNative(Object? payload) async {
    await messenger.handlePlatformMessage(
      _eventChannelName,
      _codec.encodeSuccessEnvelope(payload),
      (ByteData? _) {},
    );
  }

  setUp(() {
    platform = MethodChannelIssuetrackerSdk();
    methodLog = <MethodCall>[];
    streamLog = <MethodCall>[];

    messenger.setMockMethodCallHandler(platform.methodChannel, (
      MethodCall call,
    ) async {
      methodLog.add(call);
      return null;
    });
    // The EventChannel sends listen/cancel over a MethodChannel of the
    // same name; without a handler those would surface as
    // MissingPluginException.
    messenger.setMockMethodCallHandler(const MethodChannel(_eventChannelName), (
      MethodCall call,
    ) async {
      streamLog.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platform.methodChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannelName),
      null,
    );
  });

  group('configurationErrorEvents', () {
    test('every canonical reason survives the round trip', () async {
      final received = <SdkErrorReason>[];
      final sub = platform.configurationErrorEvents.listen(received.add);
      await null; // let the listen message flush

      for (final reason in SdkErrorReason.values) {
        await emitFromNative(reason.rawValue);
      }
      await sub.cancel();

      expect(received, equals(SdkErrorReason.values));
    });

    test('the five terminal reasons arrive typed and terminal', () async {
      final received = <SdkErrorReason>[];
      final sub = platform.configurationErrorEvents.listen(received.add);
      await null;

      await emitFromNative('project_deleted');
      await emitFromNative('project_not_found');
      await emitFromNative('api_key_revoked');
      await emitFromNative('workspace_suspended');
      await emitFromNative('invalid_api_key');
      await sub.cancel();

      expect(received.length, 5);
      expect(received.every((r) => r.isTerminal), isTrue);
      expect(received.first, SdkErrorReason.projectDeleted);
    });

    test('unrecognised payloads never reach the host', () async {
      // The native SDKs already filter on the same enum; this is the
      // last line of defence if an event-bridge regression leaks an
      // arbitrary value. Silently dropping is the safe direction: the
      // native side has still terminated.
      final received = <SdkErrorReason>[];
      final sub = platform.configurationErrorEvents.listen(received.add);
      await null;

      await emitFromNative('workspace_deleted'); // misnomer, never a wire value
      await emitFromNative('PROJECT_DELETED'); // wrong casing
      await emitFromNative(''); // empty
      await emitFromNative(null); // no payload
      await emitFromNative(42); // wrong type
      await emitFromNative(<String, Object?>{'error': 'project_deleted'});
      await emitFromNative(<String>['project_deleted']);
      await sub.cancel();

      expect(received, isEmpty);
    });

    test('stream is cached, so one EventChannel listen serves all', () async {
      final a = platform.configurationErrorEvents;
      final b = platform.configurationErrorEvents;
      expect(identical(a, b), isTrue);

      final first = <SdkErrorReason>[];
      final second = <SdkErrorReason>[];
      final subA = a.listen(first.add);
      final subB = b.listen(second.add);
      await null;

      await emitFromNative('api_key_revoked');
      await subA.cancel();
      await subB.cancel();

      expect(first, equals(<SdkErrorReason>[SdkErrorReason.apiKeyRevoked]));
      expect(second, equals(<SdkErrorReason>[SdkErrorReason.apiKeyRevoked]));
      expect(
        streamLog.where((c) => c.method == 'listen').length,
        1,
        reason: 'a second EventChannel listen would clobber the native sink',
      );
    });

    test('cancel/re-listen re-arms the native sink', () async {
      final received = <SdkErrorReason>[];
      var sub = platform.configurationErrorEvents.listen(received.add);
      await null;
      await sub.cancel();

      sub = platform.configurationErrorEvents.listen(received.add);
      await null;
      await emitFromNative('project_deleted');
      await sub.cancel();

      expect(received, equals(<SdkErrorReason>[SdkErrorReason.projectDeleted]));
      expect(
        streamLog.map((c) => c.method).toList(),
        equals(<String>['listen', 'cancel', 'listen', 'cancel']),
      );
    });
  });

  group('configure payload', () {
    test('sends the flags the native plugins read', () async {
      await platform.configure(
        apiKey: 'it_staging_abc',
        shakeToReport: false,
        longPressToReport: true,
        accessibilityAction: true,
        showReportButton: true,
        enableCrashReporting: false,
        showOnboarding: true,
      );

      expect(methodLog.single.method, 'configure');
      final args = methodLog.single.arguments as Map<Object?, Object?>;
      expect(args['apiKey'], 'it_staging_abc');
      expect(args['shakeToReport'], isFalse);
      expect(args['longPressToReport'], isTrue);
      expect(args['accessibilityAction'], isTrue);
      expect(args['showReportButton'], isTrue);
      expect(args['enableCrashReporting'], isFalse);
      expect(args['showOnboarding'], isTrue);
      expect(
        args['terminatedUI'],
        isNull,
        reason: 'null means "keep the native English defaults"',
      );
    });

    test('terminatedUI overrides travel as a nested map', () async {
      await platform.configure(
        apiKey: 'it_abc',
        shakeToReport: true,
        longPressToReport: true,
        accessibilityAction: false,
        showReportButton: false,
        enableCrashReporting: true,
        showOnboarding: false,
        terminatedUI: const TerminatedUiStrings(
          title: 'Feilrapportering er ikke lenger tilgjengelig.',
          subtitle: 'Kontakt teamet ditt.',
          closeLabel: 'Lukk',
        ),
      );

      final args = methodLog.single.arguments as Map<Object?, Object?>;
      final ui = args['terminatedUI'] as Map<Object?, Object?>;
      expect(ui['title'], 'Feilrapportering er ikke lenger tilgjengelig.');
      expect(ui['subtitle'], 'Kontakt teamet ditt.');
      expect(ui['closeLabel'], 'Lukk');
    });

    test(
      'partially overridden terminatedUI keeps the unset fields null',
      () async {
        await platform.configure(
          apiKey: 'it_abc',
          shakeToReport: true,
          longPressToReport: true,
          accessibilityAction: false,
          showReportButton: false,
          enableCrashReporting: true,
          showOnboarding: false,
          terminatedUI: const TerminatedUiStrings(closeLabel: 'Lukk'),
        );

        final args = methodLog.single.arguments as Map<Object?, Object?>;
        final ui = args['terminatedUI'] as Map<Object?, Object?>;
        expect(ui['title'], isNull);
        expect(ui['subtitle'], isNull);
        expect(ui['closeLabel'], 'Lukk');
      },
    );
  });
}
