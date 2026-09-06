# Changelog

## Unreleased

* Thread `terminatedUI` strings (title, subtitle, close label) through
  `configure()` to both native SDKs — ADR-0003 Decision 9.
* Rebuild the example app as a full SDK demo, with accessibility fixes
  and the ADR-0008 API surface on the Dart side. The
  `accessibilityAction` / `showReportButton` flags are sent over the
  method channel but ignored by the native SDKs until they reach 0.7.
* Bump the native dependency to 0.6.0 on both platforms — tester
  attestation (ADR-0005): `setTesterToken` / `clearTesterToken`.
  iOS note: `IssuetrackerSDK` 0.6.0 is not on CocoaPods trunk yet, so
  this cannot be released to pub.dev until it is.

## 0.5.0

* Add first-run onboarding: the `showOnboarding` flag on `configure()`
  and a `showOnboarding()` call, both bridged to the native popover.

## 0.4.1

* Forward native configuration errors to Dart over an EventChannel, so
  host apps can observe `onConfigurationError` — ADR-0003 Decision 9
  Phase C.
* Bump the Android native dependency to `no.issuetracker:sdk:0.4.1`.

## 0.4.0

* First public release of the Flutter wrapper: `configure()`,
  `report()`, `identify()` / `clearIdentity()`, `recordAction()` and
  `testCrash()`, bridged to the native iOS and Android SDKs at 0.4.0.
* `configure()` no longer takes an `endpoint` argument; the API key
  prefix selects the environment.
