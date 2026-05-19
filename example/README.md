# Issuetracker SDK — Flutter sample app

A real installable Flutter app that exercises every public surface
of the SDK so you can shake-test changes in 30 seconds. Same feature
checklist as the Android, iOS, and React Native sample apps — keep
them in lockstep when adding capabilities.

## How to run

1. Get a key from the Issuetracker admin UI and pass it via
   `--dart-define` (Flutter's idiomatic build-time secret hook):

   ```
   flutter run --dart-define=ISSUETRACKER_API_KEY=it_staging_xxxxxxxxxxxxxxxxxxxxxxxx
   ```

   Skip the flag and the SDK will fall into `invalid_api_key` →
   TERMINATED on the first report — a useful demo path, just not the
   happy one.

2. Run on a connected device or simulator:

   ```
   cd sdk-flutter/example
   flutter pub get
   flutter run -d <device-id> --dart-define=ISSUETRACKER_API_KEY=...
   ```

## Feature checklist

Each section in the app maps 1:1 to a surface in the SDK. When you
add a feature, add a section here AND in the sister sample apps so
the four platforms stay comparable.

| Section | What it exercises | SDK API |
|---|---|---|
| **Lifecycle** | Shows the last `onConfigurationError` reason the SDK reported. Has a "Reset" button so you can retry a path that has already fired. | `onConfigurationError` callback on `configure(...)` |
| **Reporting** | One button programmatically opens the reporter. Shake-to-report and two-finger long-press also trigger it. | `Issuetracker.report()` + `shakeToReport` + `longPressToReport` |
| **Identity** | Sets / clears the display name that stamps every report. | `identify(name)` / `clearIdentity()` |
| **Breadcrumbs** | Records up to two action breadcrumbs with optional metadata. The most-recent 5 ride along on every report. | `recordAction(name, metadata?)` |
| **Onboarding** | Re-presents the first-launch trigger introduction popover regardless of whether it has been shown before. | `Issuetracker.showOnboarding()` |
| **TERMINATED-UI i18n** | Toggle a Norwegian translation of the terminal-state strings. Restart the app to apply (`configure(...)` runs once in `main`). | `terminatedUI: TerminatedUiStrings` on `configure(...)` |
| **Destructive** | Crash-test button (with confirmation). The next launch picks up the crash and queues a report. | `Issuetracker.testCrash()` |

## Folder layout

```
example/
  README.md                  ← you are here
  pubspec.yaml               ← deps: issuetracker_sdk (path) + shared_preferences
  lib/
    main.dart                ← Issuetracker.configure() in main() + single demo screen
  android/                   ← platform shell (generated)
  ios/                       ← platform shell (generated)
```

The companion sample apps mirror this layout per platform convention:

- `sdk-android/sample-app/` (Compose single screen, see its README)
- `sdk-ios/example-app/` (Swift Package + SwiftUI single screen)
- `sdk-react-native/example/` (existing — extend to match this feature set)
- `sdk-web/example/` (existing — extend to match)

Each sample-app README is the same shape (How to run + Feature
checklist table) so a person can hop between platforms and find the
same affordances.

## Adding a new feature

When the SDK gains a new public surface:

1. Add a section to **this** app (a `_xSection()` method in `main.dart`).
2. Add the row to the **Feature checklist** table above.
3. Replicate to the other three sample apps using the same section
   title + same affordance (button label / toggle label).

## What this app intentionally is NOT

- Not a production reference app — uses `shared_preferences` for
  tiny state (i18n toggle + last error display), not Hive / Drift /
  Isar.
- Not a layout exemplar — single scroll, surfaceContainerHighest
  cards. The point is to surface every SDK affordance, not to look
  pretty.
- Not multi-screen — keeps the surface flat so anyone testing the
  SDK can find every feature without learning a navigation tree.
