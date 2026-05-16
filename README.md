# Issuetracker SDK for Flutter

Drop-in issue reporter wrapper for Flutter apps. Bridges to the native iOS and Android Issuetracker SDKs — all UI, screenshot capture, shake detection, and crash reporting runs on the native side; this package is a thin Dart façade.

## Install

```yaml
dependencies:
  issuetracker_sdk: ^0.1.0
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Issuetracker.configure(
    apiKey: 'it_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  );
  runApp(const MyApp());
}
```

That's it. Either gesture brings up the reporter:

| Trigger | Notes |
| --- | --- |
| Shake the device | Accelerometer-based — real devices only, not the simulator/emulator |
| Two-finger long-press for 3 seconds | Anywhere in the app; works in the simulator/emulator too |
| `Issuetracker.report()` | Programmatic, e.g. from a "Report a bug" button |

Both gestures are enabled by default. Disable individually via `shakeToReport: false` or `longPressToReport: false` on `Issuetracker.configure(...)`.

The SDK talks to Issuetracker's hosted backend — there is no endpoint to configure. Staging-prefixed keys (`it_staging_…`) are routed to the staging environment automatically; everything else hits production.

## Manual trigger

```dart
FilledButton(
  onPressed: Issuetracker.report,
  child: const Text('Report a bug'),
)
```

## API

```dart
Issuetracker.configure({apiKey, shakeToReport, longPressToReport, enableCrashReporting})
Issuetracker.report()
Issuetracker.identify(name)
Issuetracker.clearIdentity()
Issuetracker.recordAction(action, metadata: {...})
Issuetracker.testCrash()
```

## Development

This package depends on the native SDKs (`IssuetrackerSDK` for iOS, `io.issuetracker:sdk` for Android). For local development they're consumed from sibling repos:

**iOS** — add to `example/ios/Podfile` inside the Runner target:
```ruby
pod 'IssuetrackerSDK', :path => '../../../sdk-ios'
```

**Android** — publish the SDK to mavenLocal once:
```bash
cd ../sdk-android && ./gradlew :sdk:publishToMavenLocal
```

Then in `example/`:
```bash
flutter pub get
flutter run -d ios       # or: flutter run -d android
```

## Platform requirements

- iOS 16+
- Android 8.0+ (API 26)
- Flutter 3.3+

## License

MIT
