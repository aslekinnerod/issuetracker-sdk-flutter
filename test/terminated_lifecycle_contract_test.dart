import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';
import 'package:issuetracker_sdk/issuetracker_sdk_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ADR-0003 Decision 9 lifecycle conformance for the Flutter SDK.
//
// SCOPE — read this before trusting a green run.
//
// The TERMINATED lifecycle itself (SharedPreferences / UserDefaults
// persistence, queue purge, trigger teardown, terminal UI) lives in
// sdk-android and sdk-ios; a Dart unit test cannot reach it. What this
// file does is run a fake native SDK that makes every lifecycle
// decision through THIS package's public classification API —
// [SdkErrorReason.fromRawValue], [SdkErrorReason.isTerminal],
// [SdkErrorReason.isRecoverable] — over the real
// [Issuetracker.configure] bridge.
//
// So the suite is a regression net on two things that are genuinely
// ours:
//   1. the Dart-side dispatch table (flip `isTerminal` for any reason
//      and these tests go red), and
//   2. the bridge — that the resulting signal reaches the host's
//      `onConfigurationError` in Dart.
// The fake native SDK is otherwise an executable statement of what
// sdk-ios / sdk-android are contracted to do. It is NOT evidence that
// they do it; that needs the native suites plus an integration test
// against the live callable.
//
// Every response fixture below carries BOTH the callable code / HTTP
// status AND the structured `details`, and the fake native SDK reads
// only `details.error`. Tests deliberately pair a "terminal-looking"
// status with recoverable details and vice versa — a dispatcher that
// keyed off the status would fail them.

/// One `createIssueFromSdk` failure exactly as ADR-0003 Decision 9
/// specifies it on the wire.
class CallableError {
  const CallableError({
    required this.code,
    required this.httpStatus,
    required this.details,
  });

  final String code;
  final int httpStatus;
  final Map<String, Object?> details;

  String? get wireReason => details['error'] as String?;
}

const projectDeleted = CallableError(
  code: 'not-found',
  httpStatus: 404,
  details: <String, Object?>{
    'error': 'project_deleted',
    'recoverable': false,
    'deletedAt': '2026-08-01T09:00:00.000Z',
  },
);
const projectNotFound = CallableError(
  code: 'not-found',
  httpStatus: 404,
  details: <String, Object?>{
    'error': 'project_not_found',
    'recoverable': false,
  },
);
const apiKeyRevoked = CallableError(
  code: 'permission-denied',
  httpStatus: 403,
  details: <String, Object?>{'error': 'api_key_revoked', 'recoverable': false},
);
const workspaceSuspended = CallableError(
  code: 'permission-denied',
  httpStatus: 403,
  details: <String, Object?>{
    'error': 'workspace_suspended',
    'recoverable': false,
  },
);
const invalidApiKey = CallableError(
  code: 'unauthenticated',
  httpStatus: 401,
  details: <String, Object?>{'error': 'invalid_api_key', 'recoverable': false},
);
const quotaExceeded = CallableError(
  code: 'resource-exhausted',
  httpStatus: 429,
  details: <String, Object?>{
    'error': 'quota_exceeded',
    'recoverable': true,
    'retryAfterSeconds': 30,
  },
);
const transientFailure = CallableError(
  code: 'unavailable',
  httpStatus: 503,
  details: <String, Object?>{'error': 'transient', 'recoverable': true},
);
const testerAttestationRequired = CallableError(
  code: 'permission-denied',
  httpStatus: 403,
  details: <String, Object?>{
    'error': 'tester_attestation_required',
    'recoverable': false,
  },
);

const nonRecoverable = <String, CallableError>{
  'project_deleted': projectDeleted,
  'project_not_found': projectNotFound,
  'api_key_revoked': apiKeyRevoked,
  'workspace_suspended': workspaceSuspended,
  'invalid_api_key': invalidApiKey,
};

enum SubmitOutcome {
  /// Server accepted the report.
  accepted,

  /// Non-recoverable: the SDK is now TERMINATED.
  terminated,

  /// Recoverable: kept on the local queue for a later attempt.
  queued,

  /// Non-recoverable but non-terminal (ADR-0005 tester gating).
  rejected,

  /// Pre-flight gate: already TERMINATED, nothing left the device.
  refusedTerminated,

  /// A reason string this SDK version does not know.
  unclassified,
}

enum ReporterSurface { reportForm, terminalMessage }

/// Stands in for SharedPreferences / UserDefaults plus the SDK's own
/// on-disk stores: the only state that outlives a process restart.
class FakeDisk {
  String? terminatedReason;
  int? terminatedAtMillis;

  /// The report queue. On disk because Decision 9 point 6 requires
  /// queued reports to survive a relaunch while the SDK is OK or
  /// SUSPENDED — which is also what makes "purged on TERMINATED" a
  /// claim worth testing rather than a side effect of the process
  /// ending.
  final List<String> queue = <String>[];

  /// The pending-crash store (sdk-ios `PendingCrashStore`, the crash
  /// file sdk-android's `CrashReporter` drains). Written by the crash
  /// handler at crash time, uploaded on a later launch — so it is
  /// queue state under Decision 9 point 6, and is purged with the
  /// queue on the first terminal signal.
  final List<String> pendingCrashes = <String>[];
}

/// A fake sdk-android / sdk-ios instance. Decisions are made with this
/// package's public [SdkErrorReason] API — see the scope note above.
class FakeNativeSdk {
  FakeNativeSdk(this.disk, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final FakeDisk disk;
  DateTime Function() _clock;

  final StreamController<SdkErrorReason> events =
      StreamController<SdkErrorReason>.broadcast();

  List<String> get queue => disk.queue;
  bool shakeEnabled = false;
  bool longPressEnabled = false;
  bool floatingButtonEnabled = false;
  bool crashHandlerInstalled = false;
  String? apiKey;

  /// Counts calls that actually reached the network. A TERMINATED SDK
  /// must never increment this again.
  int serverCalls = 0;

  /// The two launch-path background calls, counted separately because
  /// they are the ones no manual test exercises — they run before the
  /// first frame and after the process that crashed is already gone
  /// (ITD-164).
  int configFetches = 0;
  int crashUploads = 0;

  /// What the server answers those two calls with on this launch;
  /// `null` means HTTP 200.
  CallableError? nextConfigError;
  CallableError? nextCrashUploadError;

  set clock(DateTime Function() value) => _clock = value;

  bool get isTerminated => disk.terminatedReason != null;
  SdkErrorReason? get terminatedReason =>
      SdkErrorReason.fromRawValue(disk.terminatedReason);
  bool get anyTriggerEnabled =>
      shakeEnabled || longPressEnabled || floatingButtonEnabled;

  /// The native `configure(...)` entry point. Rehydrating the terminal
  /// state from disk happens here, before triggers are wired, so the
  /// pre-flight gate is authoritative from the first gesture.
  void nativeConfigure({
    required String apiKey,
    required bool shakeToReport,
    required bool longPressToReport,
    required bool showReportButton,
  }) {
    this.apiKey = apiKey;
    if (isTerminated) {
      // One-way: a fresh configure() — including the one every Flutter
      // app runs from main() on each launch — must not resurrect the
      // SDK, and must not re-arm triggers or resurrect a queue.
      queue.clear();
      disk.pendingCrashes.clear();
      shakeEnabled = false;
      longPressEnabled = false;
      floatingButtonEnabled = false;
      crashHandlerInstalled = false;
      // ...and, critically, must not run either launch-path background
      // call. Both are below this return on purpose: ITD-164 is exactly
      // the case where they sat above one.
      return;
    }
    shakeEnabled = shakeToReport;
    longPressEnabled = longPressToReport;
    floatingButtonEnabled = showReportButton;
    crashHandlerInstalled = true;
    refreshRemoteConfig();
    reportCrashIfAny();
  }

  /// Launch-path background call #1 — the remote-config / tester-
  /// attestation refresh both native SDKs run from `configure()`, on
  /// every single launch, forever. Nobody watches a POST that happens
  /// before the first frame, so the guard needs a test rather than a
  /// manual pass.
  SubmitOutcome? refreshRemoteConfig() {
    if (isTerminated) return null;
    serverCalls++;
    configFetches++;
    final error = nextConfigError;
    return error == null ? null : _dispatch(error);
  }

  /// Launch-path background call #2 — draining the crash store the
  /// native crash handler wrote. Delivery lands 0-24h after the crash
  /// itself, on some later launch, which is why a terminal answer here
  /// is the one a human never sees.
  SubmitOutcome? reportCrashIfAny() {
    if (isTerminated) return null;
    if (disk.pendingCrashes.isEmpty) return null;
    serverCalls++;
    crashUploads++;
    final error = nextCrashUploadError;
    if (error == null) {
      disk.pendingCrashes.clear(); // delivered
      return SubmitOutcome.accepted;
    }
    // The crash path dispatches like every other path. Swallowing the
    // error here — sdk-android's `catch (_: Exception) { }`, sdk-ios's
    // silent `sendConfirmedCrash` failure — leaves the SDK live against
    // a project that is gone.
    return _dispatch(error);
  }

  /// The native crash handler writing one crash to disk at crash time.
  /// A TERMINATED install has no handler installed, so nothing can
  /// repopulate the store behind the purge.
  void recordCrash(String crash) {
    if (!crashHandlerInstalled) return;
    disk.pendingCrashes.add(crash);
  }

  /// What the test-cohort user sees when they open the reporting
  /// surface (shake / long-press / programmatic).
  ReporterSurface openReporter() =>
      isTerminated
          ? ReporterSurface.terminalMessage
          : ReporterSurface.reportForm;

  /// Submits one report. [error] is what the server answers with;
  /// `null` means HTTP 200.
  SubmitOutcome submit(String body, {CallableError? error}) {
    if (isTerminated) return SubmitOutcome.refusedTerminated;

    serverCalls++;
    if (error == null) return SubmitOutcome.accepted;

    final outcome = _dispatch(error);
    if (outcome == SubmitOutcome.queued) queue.add(body);
    return outcome;
  }

  /// THE dispatch — the one every network path funnels through: submit,
  /// the launch-time config refresh, and the crash upload. Two rules,
  /// and both are cross-platform findings:
  ///
  /// - ITD-164: no path may swallow a terminal answer. A background
  ///   path that catches and drops it keeps a dead install alive.
  /// - ITD-163: one predicate, `SdkErrorReason.isTerminal`, read off
  ///   `details.error`. Never a path-local variant, never
  ///   `!isRecoverable` (which would swallow the ADR-0005 tester pair
  ///   into TERMINATED), and never the HTTP status — `error.code` and
  ///   `error.httpStatus` are deliberately never read here.
  SubmitOutcome _dispatch(CallableError error) {
    final reason = SdkErrorReason.fromRawValue(error.wireReason);
    if (reason == null) return SubmitOutcome.unclassified;

    if (reason.isTerminal) {
      _terminate(reason);
      return SubmitOutcome.terminated;
    }
    if (reason.isRecoverable) return SubmitOutcome.queued;
    return SubmitOutcome.rejected;
  }

  void _terminate(SdkErrorReason reason) {
    // Idempotent: the first non-recoverable failure is authoritative.
    if (isTerminated) return;
    disk.terminatedReason = reason.rawValue;
    disk.terminatedAtMillis = _clock().millisecondsSinceEpoch;
    // Decision 9 point 6: drop the queue atomically, on disk, in the
    // same step as the marker — including the crash store, which is
    // queue state too. Everything in there was addressed to a project
    // that no longer accepts it; there is no other project it could be
    // delivered to.
    queue.clear();
    disk.pendingCrashes.clear();
    shakeEnabled = false;
    longPressEnabled = false;
    floatingButtonEnabled = false;
    crashHandlerInstalled = false;
    events.add(reason);
  }

  Future<void> dispose() => events.close();
}

/// Platform-interface shim wiring the fake native SDK to the real
/// [Issuetracker] facade.
class FakeNativePlatform extends IssuetrackerSdkPlatform
    with MockPlatformInterfaceMixin {
  FakeNativePlatform(this.native);

  final FakeNativeSdk native;

  ReporterSurface? lastReporterSurface;

  @override
  Stream<SdkErrorReason> get configurationErrorEvents => native.events.stream;

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
    native.nativeConfigure(
      apiKey: apiKey,
      shakeToReport: shakeToReport,
      longPressToReport: longPressToReport,
      showReportButton: showReportButton,
    );
  }

  @override
  Future<void> report() async {
    lastReporterSurface = native.openReporter();
  }
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeDisk disk;
  late FakeNativeSdk native;
  late FakeNativePlatform platform;
  late List<SdkErrorReason> hostCallbacks;

  /// Boots the SDK the way a Flutter host app's `main()` does.
  Future<void> boot({String apiKey = 'it_test_key'}) async {
    platform = FakeNativePlatform(native);
    IssuetrackerSdkPlatform.instance = platform;
    hostCallbacks = <SdkErrorReason>[];
    await Issuetracker.configure(
      apiKey: apiKey,
      shakeToReport: true,
      longPressToReport: true,
      showReportButton: true,
      onConfigurationError: hostCallbacks.add,
    );
  }

  /// Kills the process and starts a new one: fresh native SDK, fresh
  /// bridge, same disk. [configError] / [crashUploadError] are what the
  /// server answers this launch's two background calls with.
  Future<void> restart({
    String apiKey = 'it_test_key',
    CallableError? configError,
    CallableError? crashUploadError,
  }) async {
    await native.dispose();
    native =
        FakeNativeSdk(disk)
          ..nextConfigError = configError
          ..nextCrashUploadError = crashUploadError;
    await boot(apiKey: apiKey);
  }

  setUp(() async {
    disk = FakeDisk();
    native = FakeNativeSdk(disk);
    await boot();
  });

  tearDown(() async {
    await Issuetracker.configure(apiKey: 'it_test_teardown');
    await native.dispose();
  });

  group('dispatch is on details.error, never the HTTP status', () {
    test('404 + recoverable details does NOT terminate', () async {
      // A dispatcher keyed on "404 means gone" would terminate here.
      const misleading = CallableError(
        code: 'not-found',
        httpStatus: 404,
        details: <String, Object?>{
          'error': 'quota_exceeded',
          'recoverable': true,
        },
      );

      expect(native.submit('report', error: misleading), SubmitOutcome.queued);
      await _pump();

      expect(native.isTerminated, isFalse);
      expect(hostCallbacks, isEmpty);
      expect(native.anyTriggerEnabled, isTrue);
    });

    test('429 + non-recoverable details DOES terminate', () async {
      // And a dispatcher keyed on "429 means back off" would keep
      // hammering a dead project here.
      const misleading = CallableError(
        code: 'resource-exhausted',
        httpStatus: 429,
        details: <String, Object?>{
          'error': 'project_deleted',
          'recoverable': false,
        },
      );

      expect(
        native.submit('report', error: misleading),
        SubmitOutcome.terminated,
      );
      await _pump();

      expect(native.isTerminated, isTrue);
      expect(
        hostCallbacks,
        equals(<SdkErrorReason>[SdkErrorReason.projectDeleted]),
      );
    });

    test('an unknown reason string does not terminate the SDK', () async {
      const unknown = CallableError(
        code: 'not-found',
        httpStatus: 404,
        details: <String, Object?>{
          'error': 'workspace_deleted', // never a wire value
          'recoverable': false,
        },
      );

      expect(
        native.submit('report', error: unknown),
        SubmitOutcome.unclassified,
      );
      await _pump();

      expect(native.isTerminated, isFalse);
      expect(hostCallbacks, isEmpty);
    });
  });

  group('every non-recoverable reason terminates', () {
    for (final entry in nonRecoverable.entries) {
      test('${entry.key} terminates, purges, disables and notifies', () async {
        // Something is queued and all triggers are live beforehand.
        expect(
          native.submit('queued-1', error: transientFailure),
          SubmitOutcome.queued,
        );
        expect(
          native.submit('queued-2', error: transientFailure),
          SubmitOutcome.queued,
        );
        expect(native.queue, hasLength(2));
        expect(native.shakeEnabled, isTrue);
        expect(native.longPressEnabled, isTrue);
        expect(native.floatingButtonEnabled, isTrue);

        expect(
          native.submit('doomed', error: entry.value),
          SubmitOutcome.terminated,
        );
        await _pump();

        // TERMINATED
        expect(native.isTerminated, isTrue);
        expect(native.terminatedReason?.rawValue, entry.key);
        expect(
          disk.terminatedReason,
          entry.key,
          reason: 'the terminal state must be written to disk immediately',
        );
        expect(disk.terminatedAtMillis, isNotNull);

        // Queue purged, not paused.
        expect(native.queue, isEmpty);

        // Triggers disabled: shake, long-press, floating button.
        expect(native.shakeEnabled, isFalse);
        expect(native.longPressEnabled, isFalse);
        expect(native.floatingButtonEnabled, isFalse);

        // Callback reached Dart, exactly once, with the right reason.
        expect(
          hostCallbacks,
          equals(<SdkErrorReason>[SdkErrorReason.fromRawValue(entry.key)!]),
        );

        // The reporting surface shows the terminal message instead of
        // the form when the test-cohort user opens it.
        await Issuetracker.report();
        expect(platform.lastReporterSurface, ReporterSurface.terminalMessage);
      });
    }
  });

  group('recoverable reasons do NOT terminate', () {
    test('quota_exceeded keeps the SDK usable and the report queued', () async {
      expect(
        native.submit('report', error: quotaExceeded),
        SubmitOutcome.queued,
      );
      await _pump();

      expect(native.isTerminated, isFalse);
      expect(disk.terminatedReason, isNull);
      expect(native.queue, equals(<String>['report']));
      expect(native.shakeEnabled, isTrue);
      expect(native.longPressEnabled, isTrue);
      expect(native.floatingButtonEnabled, isTrue);
      expect(hostCallbacks, isEmpty);

      await Issuetracker.report();
      expect(platform.lastReporterSurface, ReporterSurface.reportForm);

      // And it still recovers: the next attempt goes to the server.
      expect(native.submit('report'), SubmitOutcome.accepted);
    });

    test('transient keeps the SDK usable', () async {
      expect(
        native.submit('report', error: transientFailure),
        SubmitOutcome.queued,
      );
      await _pump();

      expect(native.isTerminated, isFalse);
      expect(native.anyTriggerEnabled, isTrue);
      expect(hostCallbacks, isEmpty);
    });

    test(
      'tester gating is non-recoverable but non-terminal (ADR-0005)',
      () async {
        expect(
          native.submit('report', error: testerAttestationRequired),
          SubmitOutcome.rejected,
        );
        await _pump();

        expect(
          native.isTerminated,
          isFalse,
          reason: 'the project is alive and the key is valid',
        );
        expect(disk.terminatedReason, isNull);
        expect(native.anyTriggerEnabled, isTrue);
        expect(native.queue, isEmpty, reason: 'retrying cannot help');
      },
    );
  });

  group('TERMINATED survives a process restart', () {
    test('state, purge and trigger teardown all rehydrate', () async {
      native.submit('report', error: projectDeleted);
      await _pump();
      expect(native.isTerminated, isTrue);

      await restart();

      expect(
        native.isTerminated,
        isTrue,
        reason: 'a relaunch must not clear the terminal state',
      );
      expect(native.terminatedReason, SdkErrorReason.projectDeleted);
      expect(native.queue, isEmpty);
      expect(native.shakeEnabled, isFalse);
      expect(native.longPressEnabled, isFalse);
      expect(
        native.floatingButtonEnabled,
        isFalse,
        reason: 'configure() asked for the triggers and must be refused',
      );
    });

    test('no traffic leaves the device after a restart', () async {
      native.submit('report', error: apiKeyRevoked);
      await _pump();

      await restart();
      final callsAfterBoot = native.serverCalls;

      expect(native.submit('after-restart'), SubmitOutcome.refusedTerminated);
      expect(
        native.serverCalls,
        callsAfterBoot,
        reason: 'a TERMINATED SDK must never reach the network again',
      );
    });

    test('surviving ten restarts still shows the terminal UI', () async {
      native.submit('report', error: workspaceSuspended);
      await _pump();

      for (var i = 0; i < 10; i++) {
        await restart();
      }

      expect(native.isTerminated, isTrue);
      await Issuetracker.report();
      expect(platform.lastReporterSurface, ReporterSurface.terminalMessage);
    });
  });

  group('TERMINATED is one-way', () {
    test('a later successful-looking call cannot revive it', () async {
      native.submit('report', error: projectDeleted);
      await _pump();
      final callsBefore = native.serverCalls;

      // Even a 200 OK from the server can't bring it back — the
      // pre-flight gate means the request never happens.
      expect(native.submit('later'), SubmitOutcome.refusedTerminated);
      expect(native.serverCalls, callsBefore);
      expect(native.isTerminated, isTrue);
    });

    test('re-configure() does not revive it', () async {
      native.submit('report', error: invalidApiKey);
      await _pump();

      await Issuetracker.configure(
        apiKey: 'it_test_key',
        shakeToReport: true,
        longPressToReport: true,
        showReportButton: true,
        onConfigurationError: hostCallbacks.add,
      );

      expect(native.isTerminated, isTrue);
      expect(native.anyTriggerEnabled, isFalse);
    });

    test('a different API key does not revive it', () async {
      // Rotating the key in the host app is the most plausible
      // accidental "reset" — it must not be one.
      native.submit('report', error: apiKeyRevoked);
      await _pump();

      await restart(apiKey: 'it_a_completely_different_key');

      expect(native.isTerminated, isTrue);
      expect(native.apiKey, 'it_a_completely_different_key');
      expect(native.anyTriggerEnabled, isFalse);
      expect(native.submit('report'), SubmitOutcome.refusedTerminated);
    });

    test('a clock change does not revive it', () async {
      native.submit('report', error: projectDeleted);
      await _pump();

      // Device clock jumps a year back — the terminal marker is a
      // fact, not a TTL.
      await restart();
      native.clock = () => DateTime(2020, 1, 1);

      expect(native.isTerminated, isTrue);
      expect(native.submit('report'), SubmitOutcome.refusedTerminated);

      // ...and a year forward.
      native.clock = () => DateTime(2099, 1, 1);
      expect(native.isTerminated, isTrue);
      expect(native.submit('report'), SubmitOutcome.refusedTerminated);
    });

    test('the first reason wins and the callback fires once', () async {
      native.submit('report', error: projectDeleted);
      await _pump();
      // A second non-recoverable answer (only reachable if a pre-flight
      // check missed) must not overwrite the reason or re-notify.
      native._terminate(SdkErrorReason.apiKeyRevoked);
      await _pump();

      expect(native.terminatedReason, SdkErrorReason.projectDeleted);
      expect(
        hostCallbacks,
        equals(<SdkErrorReason>[SdkErrorReason.projectDeleted]),
      );
    });
  });

  group('local queue invariants', () {
    test(
      'the queue is purged, not paused, on the first terminal signal',
      () async {
        for (var i = 0; i < 5; i++) {
          native.submit('queued-$i', error: transientFailure);
        }
        expect(native.queue, hasLength(5));

        native.submit('doomed', error: projectNotFound);
        await _pump();

        expect(native.queue, isEmpty);
        // And nothing re-appears after a restart.
        await restart();
        expect(native.queue, isEmpty);
      },
    );

    test('a terminated SDK never enqueues again', () async {
      native.submit('report', error: projectDeleted);
      await _pump();

      native.submit('after-1');
      native.submit('after-2', error: transientFailure);

      expect(native.queue, isEmpty);
    });

    test('a queued report survives a restart while the SDK is alive', () async {
      // The purge is a TERMINATED-only action. A report queued behind a
      // transient failure is still deliverable to a project that is
      // still there, so dropping it would lose a report for nothing —
      // the SUSPENDED half of Decision 9 point 6.
      expect(
        native.submit('queued-1', error: transientFailure),
        SubmitOutcome.queued,
      );

      await restart();

      expect(native.isTerminated, isFalse);
      expect(native.queue, equals(<String>['queued-1']));
    });
  });

  group('background paths respect TERMINATED (ITD-164)', () {
    test('a healthy install still refreshes config and drains crashes', () {
      // The guard is on TERMINATED, not on everything. If this test
      // fails, the fix for ITD-164 broke the legitimate path: a live
      // SDK must fetch its config on launch and must upload the crash
      // it recorded last run.
      expect(native.configFetches, 1, reason: 'setUp booted one process');
      expect(native.crashHandlerInstalled, isTrue);
    });

    test(
      'a crash recorded before a restart is uploaded on the next launch',
      () async {
        native.recordCrash('crash-1');
        expect(disk.pendingCrashes, hasLength(1));

        await restart();

        expect(native.crashUploads, 1);
        expect(native.configFetches, 1);
        expect(disk.pendingCrashes, isEmpty, reason: 'delivered, then cleared');
        expect(native.isTerminated, isFalse);
      },
    );

    test('a terminated install never fetches config again', () async {
      native.submit('report', error: projectDeleted);
      await _pump();

      for (var launch = 1; launch <= 10; launch++) {
        await restart();
        expect(
          native.configFetches,
          0,
          reason: 'launch $launch still POSTed getSdkConfig',
        );
        expect(
          native.serverCalls,
          0,
          reason: 'launch $launch reached the network at all',
        );
      }
    });

    test(
      'a terminated install never uploads a crash, and the store stays purged',
      () async {
        native.recordCrash('crash-before');
        expect(disk.pendingCrashes, hasLength(1));

        native.submit('report', error: apiKeyRevoked);
        await _pump();

        // Purged with the queue, in the same step as the marker.
        expect(disk.pendingCrashes, isEmpty);

        // The crash handler is uninstalled, so nothing repopulates it...
        native.recordCrash('crash-after');
        expect(disk.pendingCrashes, isEmpty);

        // ...and no later launch re-attempts delivery.
        await restart();
        expect(native.crashUploads, 0);
        expect(native.crashHandlerInstalled, isFalse);
        expect(disk.pendingCrashes, isEmpty);

        // Belt and braces: a crash file that survived the purge — one
        // written by an older SDK version before the app upgraded, say
        // — must still not be uploaded. The purge and the launch-time
        // guard are two independent halves of Decision 9 point 6, and
        // an install that only has one of them still POSTs to a dead
        // project.
        disk.pendingCrashes.add('crash-from-an-older-build');
        await restart();
        expect(native.crashUploads, 0);
        expect(native.serverCalls, 0);
      },
    );

    test(
      'a terminal answer on the crash upload terminates, it is not swallowed',
      () async {
        native.recordCrash('crash-1');
        expect(
          native.submit('queued-1', error: transientFailure),
          SubmitOutcome.queued,
        );

        // Next launch: the crash upload is the first thing that talks to
        // the server, and the project is gone. Nobody is watching.
        await restart(crashUploadError: projectDeleted);
        await _pump();

        expect(native.isTerminated, isTrue);
        expect(native.terminatedReason, SdkErrorReason.projectDeleted);
        expect(
          hostCallbacks,
          equals(<SdkErrorReason>[SdkErrorReason.projectDeleted]),
          reason: 'the host learns about it from the background path too',
        );
        expect(native.queue, isEmpty);
        expect(disk.pendingCrashes, isEmpty);
        expect(native.anyTriggerEnabled, isFalse);
        expect(native.crashHandlerInstalled, isFalse);
      },
    );

    test('a recoverable answer on the crash upload keeps the crash', () async {
      native.recordCrash('crash-1');

      await restart(crashUploadError: transientFailure);
      await _pump();

      expect(native.isTerminated, isFalse);
      expect(
        disk.pendingCrashes,
        equals(<String>['crash-1']),
        reason: 'a transient failure must not lose the crash',
      );
      expect(native.anyTriggerEnabled, isTrue);
      expect(hostCallbacks, isEmpty);
    });

    test('a terminal answer on the launch config refresh terminates', () async {
      native.recordCrash('crash-1');

      await restart(configError: workspaceSuspended);
      await _pump();

      expect(native.isTerminated, isTrue);
      expect(
        hostCallbacks,
        equals(<SdkErrorReason>[SdkErrorReason.workspaceSuspended]),
      );
      expect(native.anyTriggerEnabled, isFalse);
      expect(
        native.crashUploads,
        0,
        reason: 'the crash drain must not run once the refresh terminated it',
      );
      expect(disk.pendingCrashes, isEmpty);
    });

    test('tester gating on a background path changes no state', () async {
      // ITD-163 on the background paths: a non-recoverable-but-non-
      // terminal answer must leave a live SDK live. Dispatching on
      // `!recoverable` here would kill the install permanently.
      await restart(configError: testerAttestationRequired);
      await _pump();

      expect(native.isTerminated, isFalse);
      expect(native.anyTriggerEnabled, isTrue);
      expect(native.crashHandlerInstalled, isTrue);
      expect(hostCallbacks, isEmpty);
    });
  });
}
