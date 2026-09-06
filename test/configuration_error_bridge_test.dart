import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';
import 'package:issuetracker_sdk/issuetracker_sdk_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Bridge-level contract tests for ADR-0003 Decision 9 on Flutter.
//
// What this file covers: the Dart half of the event bridge — that a
// TERMINATED signal raised by the native SDK actually reaches the host
// app's `onConfigurationError`, for every wire reason, and that the
// subscription bookkeeping in `Issuetracker.configure()` neither drops
// nor duplicates the callback across re-configure().
//
// What it deliberately does NOT cover: the lifecycle itself
// (persistence, queue purge, trigger teardown) lives in sdk-ios /
// sdk-android. The Dart-visible consequences of that lifecycle are
// exercised in terminated_lifecycle_contract_test.dart.
//
// Mirrors sdk-react-native's facade tests (same bridge shape, JS side).

class _FakePlatform extends IssuetrackerSdkPlatform
    with MockPlatformInterfaceMixin {
  final StreamController<SdkErrorReason> _controller =
      StreamController<SdkErrorReason>.broadcast();

  int configureCalls = 0;
  final List<String> apiKeys = <String>[];

  /// Invoked synchronously inside [configure], i.e. while the native
  /// side would be initialising. Used to prove the Dart subscription
  /// is armed *before* native configure runs.
  void Function()? duringConfigure;

  bool get hasListener => _controller.hasListener;

  void emitFromNative(SdkErrorReason reason) => _controller.add(reason);

  @override
  Stream<SdkErrorReason> get configurationErrorEvents => _controller.stream;

  @override
  Future<void> configure({
    required String apiKey,
    required bool shakeToReport,
    required bool longPressToReport,
    required bool accessibilityAction,
    required bool showReportButton,
    required bool enableCrashReporting,
    required bool showOnboarding,
    TerminatedUiStrings? terminatedUI,
  }) async {
    configureCalls++;
    apiKeys.add(apiKey);
    duringConfigure?.call();
  }

  Future<void> dispose() => _controller.close();
}

/// Lets pending stream events and microtasks drain.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    IssuetrackerSdkPlatform.instance = platform;
  });

  tearDown(() async {
    // The facade holds a static subscription; drop it so it does not
    // leak into the next test against a closed controller.
    await Issuetracker.configure(apiKey: 'it_test_teardown');
    await platform.dispose();
  });

  group('onConfigurationError reaches Dart', () {
    test('every terminal reason is delivered to the host callback', () async {
      // ADR-0003 Decision 9 point 4: identical callback surface on all
      // five SDKs, with these five reasons.
      const terminal = <SdkErrorReason>[
        SdkErrorReason.projectDeleted,
        SdkErrorReason.projectNotFound,
        SdkErrorReason.apiKeyRevoked,
        SdkErrorReason.workspaceSuspended,
        SdkErrorReason.invalidApiKey,
      ];

      for (final reason in terminal) {
        final seen = <SdkErrorReason>[];
        await Issuetracker.configure(
          apiKey: 'it_test_key',
          onConfigurationError: seen.add,
        );
        platform.emitFromNative(reason);
        await _pump();

        expect(
          seen,
          equals(<SdkErrorReason>[reason]),
          reason: '${reason.rawValue} did not reach the Dart callback',
        );
        expect(reason.isTerminal, isTrue);
      }
    });

    test(
      'recoverable reasons reach the callback but are not terminal',
      () async {
        // quota_exceeded is recoverable (ADR-0003 Decision 9 point 2):
        // the host must not tear anything down on it. The bridge still
        // forwards it if native chooses to emit it, so hosts have to be
        // able to tell the two apart from the reason alone.
        final seen = <SdkErrorReason>[];
        await Issuetracker.configure(
          apiKey: 'it_test_key',
          onConfigurationError: seen.add,
        );

        platform.emitFromNative(SdkErrorReason.quotaExceeded);
        platform.emitFromNative(SdkErrorReason.transient);
        await _pump();

        expect(
          seen,
          equals(<SdkErrorReason>[
            SdkErrorReason.quotaExceeded,
            SdkErrorReason.transient,
          ]),
        );
        expect(seen.every((r) => r.isTerminal), isFalse);
        expect(seen.every((r) => r.isRecoverable), isTrue);
      },
    );

    test('subscription is armed before native configure runs', () async {
      // A termination raised while the native side is still inside
      // configure() (e.g. a cached tester-attestation refusal) must
      // not be dropped on the floor.
      final seen = <SdkErrorReason>[];
      platform.duringConfigure =
          () => platform.emitFromNative(SdkErrorReason.apiKeyRevoked);

      await Issuetracker.configure(
        apiKey: 'it_test_key',
        onConfigurationError: seen.add,
      );
      await _pump();

      expect(seen, equals(<SdkErrorReason>[SdkErrorReason.apiKeyRevoked]));
    });

    test('no callback fires before configure() is called', () async {
      platform.emitFromNative(SdkErrorReason.projectDeleted);
      await _pump();
      expect(platform.hasListener, isFalse);
    });
  });

  group('re-configure does not leak subscriptions', () {
    test('only the most recent callback fires', () async {
      final first = <SdkErrorReason>[];
      final second = <SdkErrorReason>[];

      await Issuetracker.configure(
        apiKey: 'it_test_key',
        onConfigurationError: first.add,
      );
      await Issuetracker.configure(
        apiKey: 'it_test_key',
        shakeToReport: false,
        onConfigurationError: second.add,
      );

      platform.emitFromNative(SdkErrorReason.projectDeleted);
      await _pump();

      expect(first, isEmpty, reason: 'stale subscription leaked');
      expect(second, equals(<SdkErrorReason>[SdkErrorReason.projectDeleted]));
      expect(platform.configureCalls, 2);
    });

    test('many re-configures leave exactly one live subscription', () async {
      final counts = <int, int>{};
      for (var i = 0; i < 10; i++) {
        await Issuetracker.configure(
          apiKey: 'it_test_key_$i',
          onConfigurationError: (_) => counts[i] = (counts[i] ?? 0) + 1,
        );
      }

      platform.emitFromNative(SdkErrorReason.workspaceSuspended);
      await _pump();

      expect(
        counts,
        equals(<int, int>{9: 1}),
        reason: 'exactly one — the newest — callback may fire',
      );
    });

    test(
      'overlapping (un-awaited) configure calls do not double-fire',
      () async {
        // A host settings screen that fires configure() without awaiting
        // while app start-up is still inside its own configure() is the
        // realistic way two calls interleave. Both must not end up
        // subscribed. (Regression: the tear-down used to happen after an
        // `await`, so two in-flight calls each installed a subscription
        // and the first one was never cancelled.)
        final first = <SdkErrorReason>[];
        final second = <SdkErrorReason>[];

        final a = Issuetracker.configure(
          apiKey: 'it_test_a',
          onConfigurationError: first.add,
        );
        final b = Issuetracker.configure(
          apiKey: 'it_test_b',
          onConfigurationError: second.add,
        );
        await Future.wait(<Future<void>>[a, b]);

        platform.emitFromNative(SdkErrorReason.invalidApiKey);
        await _pump();

        expect(
          first.length + second.length,
          1,
          reason: 'the reason must be delivered exactly once',
        );
      },
    );

    test('re-configure without a callback detaches the previous one', () async {
      // Documented consequence, not a bug in itself: options replace
      // rather than merge. Hosts that re-configure from a settings
      // screen (README: "call configure() again with shakeToReport:
      // false") must pass onConfigurationError again or they go blind
      // for the rest of the process — the native SDK keeps terminating
      // either way.
      final seen = <SdkErrorReason>[];
      await Issuetracker.configure(
        apiKey: 'it_test_key',
        onConfigurationError: seen.add,
      );
      await Issuetracker.configure(apiKey: 'it_test_key', shakeToReport: false);

      platform.emitFromNative(SdkErrorReason.projectDeleted);
      await _pump();

      expect(seen, isEmpty);
      expect(
        platform.hasListener,
        isFalse,
        reason: 'the EventChannel subscription must be released',
      );
    });
  });
}
