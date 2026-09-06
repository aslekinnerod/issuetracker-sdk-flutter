import 'package:flutter_test/flutter_test.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';

// Contract tests for the SDK error wire format. The rawValue strings
// here MUST match @issuetracker/shared SdkErrorReasonSchema byte-for-
// byte — any drift breaks the host-app onConfigurationError callback.
//
// Mirrors the suites in:
// - sdk-web/src/errors.test.ts
// - sdk-ios/Tests/IssuetrackerSDKTests/SdkErrorReasonTests.swift
// - sdk-android/.../SdkErrorReasonTest.kt
// - sdk-react-native/src/errors.test.ts
//
// See ADR-0003 Decision 9.

void main() {
  group('SdkErrorReason', () {
    test('all canonical reasons present with correct raw values', () {
      // ADR-0003 Decision 9 + the ADR-0005 tester-gating reasons.
      final canonical = {
        'project_deleted',
        'project_not_found',
        'api_key_revoked',
        'workspace_suspended',
        'invalid_api_key',
        'quota_exceeded',
        'transient',
        'tester_attestation_required',
        'tester_token_invalid',
      };
      final actual = SdkErrorReason.values.map((r) => r.rawValue).toSet();
      expect(actual, equals(canonical));
    });

    test('workspace_deleted misnomer is rejected by fromRawValue', () {
      // The OPERATIONS-FOLLOWUPS doc used WORKSPACE_DELETED for a
      // week as the wire name — it never was. A server typo here
      // MUST NOT enter the lifecycle as TERMINATED.
      expect(SdkErrorReason.fromRawValue('workspace_deleted'), isNull);
      expect(SdkErrorReason.fromRawValue('WORKSPACE_SUSPENDED'), isNull);
      expect(SdkErrorReason.fromRawValue(''), isNull);
      expect(SdkErrorReason.fromRawValue(null), isNull);
    });

    test('fromRawValue resolves every canonical reason', () {
      for (final r in SdkErrorReason.values) {
        expect(SdkErrorReason.fromRawValue(r.rawValue), equals(r));
      }
    });

    test('isRecoverable mapping matches shared schema', () {
      expect(SdkErrorReason.quotaExceeded.isRecoverable, isTrue);
      expect(SdkErrorReason.transient.isRecoverable, isTrue);
      expect(SdkErrorReason.projectDeleted.isRecoverable, isFalse);
      expect(SdkErrorReason.projectNotFound.isRecoverable, isFalse);
      expect(SdkErrorReason.apiKeyRevoked.isRecoverable, isFalse);
      expect(SdkErrorReason.workspaceSuspended.isRecoverable, isFalse);
      expect(SdkErrorReason.invalidApiKey.isRecoverable, isFalse);
      expect(SdkErrorReason.testerAttestationRequired.isRecoverable, isFalse);
      expect(SdkErrorReason.testerTokenInvalid.isRecoverable, isFalse);
    });

    test('tester gating reasons are non-terminal', () {
      // ADR-0005: non-recoverable but NOT terminal — the SDK must
      // never transition to TERMINATED on a tester-gating rejection.
      expect(SdkErrorReason.testerAttestationRequired.isTerminal, isFalse);
      expect(SdkErrorReason.testerTokenInvalid.isTerminal, isFalse);
      expect(SdkErrorReason.quotaExceeded.isTerminal, isFalse);
      expect(SdkErrorReason.transient.isTerminal, isFalse);
      expect(SdkErrorReason.projectDeleted.isTerminal, isTrue);
      expect(SdkErrorReason.projectNotFound.isTerminal, isTrue);
      expect(SdkErrorReason.apiKeyRevoked.isTerminal, isTrue);
      expect(SdkErrorReason.workspaceSuspended.isTerminal, isTrue);
      expect(SdkErrorReason.invalidApiKey.isTerminal, isTrue);
    });
  });
}
