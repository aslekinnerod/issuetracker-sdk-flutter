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

## Full documentation

API reference, triggers, TERMINATED behavior, crash reporting, identity
flow, breadcrumbs, and troubleshooting — see
**[docs.issuetracker.no/sdk/flutter](https://docs.issuetracker.no/sdk/flutter)**.

## Requirements

- Flutter 3.13+
- iOS 16.0+ / Android 8.0+

## License

MIT
