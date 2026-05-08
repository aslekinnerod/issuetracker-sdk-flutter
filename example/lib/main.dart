import 'package:flutter/material.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';

const String _apiKey = 'it_replace_with_real_key_from_admin_ui';
const String _endpoint = 'https://issuetracker-api-staging.web.app/v1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Issuetracker.configure(apiKey: _apiKey, endpoint: _endpoint);
  runApp(const SampleApp());
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Issuetracker SDK — Flutter Sample',
      theme: ThemeData(useMaterial3: true),
      home: const SampleScreen(),
    );
  }
}

class SampleScreen extends StatelessWidget {
  const SampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Issuetracker SDK — Flutter Sample')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Shake the device to trigger the reporter, or use the buttons below.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: Issuetracker.report,
                child: const Text('Report a bug'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Issuetracker.recordAction('button_tapped'),
                child: const Text('Record breadcrumb'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Issuetracker.identify('Alice Andersen'),
                child: const Text('Identify as Alice'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: Issuetracker.clearIdentity,
                child: const Text('Clear identity'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: Issuetracker.testCrash,
                child: const Text('Test crash'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
