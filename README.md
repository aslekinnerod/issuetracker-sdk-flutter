# Issuetracker SDK for Flutter

Drop-in issue reporter for Flutter apps. Bridges to the native iOS and
Android Issuetracker SDKs via platform channels — all UI, screenshot
capture, shake detection, and crash reporting runs on the native side.

## Install

`pubspec.yaml`:

```yaml
dependencies:
  issuetracker: ^0.5.0
```

```bash
flutter pub get
```

## Quickstart

```dart
import 'package:flutter/material.dart';
import 'package:issuetracker/issuetracker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Issuetracker.configure(apiKey: 'it_...');
  runApp(const MyApp());
}
```

## Accessibility

The default triggers are gestures: shake (`shakeToReport`) and a
two-finger 3-second long-press (`longPressToReport`), both enabled by
default. Gestures alone are not accessible to everyone — WCAG 2.2
2.5.1 (Pointer Gestures) and 2.5.4 (Motion Actuation) require a
single-pointer, non-motion alternative. If you enable either gesture
trigger, you MUST also provide a conventional, single-pointer entry
point. The one-line path (ADR-0008):

```dart
await Issuetracker.configure(
  apiKey: 'it_...',
  accessibilityAction: true, // screen-reader custom action "Report a bug"
  showReportButton: true, // SDK-provided floating report button
);
```

- `accessibilityAction: true` registers a screen-reader custom action
  ("Report a bug") whenever VoiceOver / TalkBack is running — the
  population most likely to be locked out of both gestures, since the
  OS screen reader claims shake and multi-finger gestures. No visible
  chrome for anyone else.
- `showReportButton: true` renders a small SDK-provided floating
  button, covering sighted motor-impaired users who can't shake or
  long-press.

Alternatively (or additionally), wire your own visible button or menu
item to `Issuetracker.report()` — that also satisfies the
requirement, and gives you full control over placement and styling.
You SHOULD also offer a user-facing setting to turn shake detection
off (some users trigger it accidentally due to tremors, or use their
device in motion). Apply it by calling `Issuetracker.configure()`
again with `shakeToReport: false` — reconfiguration takes effect
immediately, no restart needed.

The example app's "Report a bug" button demonstrates the programmatic
trigger.

## Full documentation

API reference, triggers, TERMINATED behavior, crash reporting, identity
flow, breadcrumbs, and troubleshooting — see
**[docs.issuetracker.no/sdk/flutter](https://docs.issuetracker.no/sdk/flutter)**.

## Requirements

- Flutter 3.13+
- iOS 16.0+ / Android 8.0+

## License

MIT
