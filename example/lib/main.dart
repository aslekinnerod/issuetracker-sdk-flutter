import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:issuetracker_sdk/issuetracker_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

// API key comes from `--dart-define=ISSUETRACKER_API_KEY=it_staging_...`
// at flutter run / build time. Falls back to a placeholder that the
// SDK rejects with invalid_api_key — useful for demoing the
// TERMINATED flow if you leave it in.
const String _apiKey = String.fromEnvironment(
  'ISSUETRACKER_API_KEY',
  defaultValue: 'it_staging_REPLACE_ME',
);

const String _prefUseNorwegianTerminatedUI = 'useNorwegianTerminatedUI';
const String _prefLastConfigError = 'lastConfigError';
const String _prefLastConfigErrorAt = 'lastConfigErrorAt';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final useNorwegian = prefs.getBool(_prefUseNorwegianTerminatedUI) ?? false;
  await configureSdk(prefs, useNorwegian: useNorwegian);

  runApp(SampleApp(prefs: prefs));
}

/// Shared by [main] and the TERMINATED-UI i18n toggle: the SDK
/// accepts repeated [Issuetracker.configure] calls, so a new
/// `terminatedUI` applies immediately without an app restart.
Future<void> configureSdk(
  SharedPreferences prefs, {
  required bool useNorwegian,
}) async {
  final terminatedUI = useNorwegian
      ? const TerminatedUiStrings(
          title: 'Feilrapportering er ikke lenger tilgjengelig.',
          subtitle: 'Kontakt teamet ditt.',
          closeLabel: 'Lukk',
        )
      : null;

  await Issuetracker.configure(
    apiKey: _apiKey,
    shakeToReport: true,
    longPressToReport: true,
    // ADR-0008: the one-line accessibility path — a screen-reader
    // custom action plus an SDK-provided floating report button
    // (takes effect once the native SDKs ship the flags).
    accessibilityAction: true,
    showReportButton: true,
    enableCrashReporting: true,
    showOnboarding: true,
    onConfigurationError: (SdkErrorReason reason) {
      // Persist so the Lifecycle section can show what fired. The
      // SDK has already transitioned to TERMINATED by this point.
      prefs.setString(_prefLastConfigError, reason.rawValue);
      prefs.setInt(_prefLastConfigErrorAt, DateTime.now().millisecondsSinceEpoch);
      SemanticsService.announce(
        'Configuration error: ${reason.rawValue}',
        TextDirection.ltr,
      );
    },
    terminatedUI: terminatedUI,
  );
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Issuetracker SDK demo',
      theme: ThemeData(useMaterial3: true),
      home: SampleScreen(prefs: prefs),
    );
  }
}

/// Single-screen demo. Every meaningful SDK surface gets a section
/// card with one or two buttons + a short explanation, so a person
/// who's never seen the SDK can shake-test it in 30 seconds.
///
/// Same feature checklist is the spec for the Android, iOS, and RN
/// sample apps — see example/README.md.
class SampleScreen extends StatefulWidget {
  const SampleScreen({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<SampleScreen> createState() => _SampleScreenState();
}

class _SampleScreenState extends State<SampleScreen> {
  final TextEditingController _nameCtl = TextEditingController();
  String? _identityFeedback;
  final List<String> _recentBreadcrumbs = [];
  late bool _useNorwegian;

  @override
  void initState() {
    super.initState();
    _useNorwegian =
        widget.prefs.getBool(_prefUseNorwegianTerminatedUI) ?? false;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issuetracker SDK demo'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _lifecycleSection(),
              const SizedBox(height: 12),
              _reportingSection(),
              const SizedBox(height: 12),
              _identitySection(),
              const SizedBox(height: 12),
              _breadcrumbSection(),
              const SizedBox(height: 12),
              _onboardingSection(),
              const SizedBox(height: 12),
              _i18nSection(),
              const SizedBox(height: 12),
              _destructiveSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _lifecycleSection() {
    final lastError = widget.prefs.getString(_prefLastConfigError);
    final lastErrorAt = widget.prefs.getInt(_prefLastConfigErrorAt) ?? 0;
    String? whenStr;
    if (lastErrorAt > 0) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastErrorAt;
      final mins = (elapsed / 60000).round();
      whenStr = mins < 1 ? 'just now' : '$mins min ago';
    }

    final subtitle = lastError != null
        ? 'Last onConfigurationError: $lastError ($whenStr)'
        : 'Listening for onConfigurationError. Nothing fired yet.';

    return _sectionCard(
      title: 'Lifecycle',
      subtitle: subtitle,
      child: OutlinedButton(
        onPressed: () async {
          await widget.prefs.remove(_prefLastConfigError);
          await widget.prefs.remove(_prefLastConfigErrorAt);
          setState(() {});
        },
        child: const Text('Reset last error'),
      ),
    );
  }

  Widget _reportingSection() {
    return _sectionCard(
      title: 'Reporting',
      subtitle:
          'Shake the device, two-finger long-press (3s), or tap the button.',
      child: FilledButton(
        onPressed: () => Issuetracker.report(),
        child: const Text('Report a bug'),
      ),
    );
  }

  Widget _identitySection() {
    return _sectionCard(
      title: 'Identity',
      subtitle: 'Skips the in-form name prompt and stamps every report.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'e.g. Kari Nordmann',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final v = _nameCtl.text.trim();
                    if (v.isNotEmpty) {
                      await Issuetracker.identify(v);
                      setState(() => _identityFeedback = 'Saved "$v"');
                      SemanticsService.announce(
                        'Saved "$v"',
                        TextDirection.ltr,
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Issuetracker.clearIdentity();
                    _nameCtl.clear();
                    setState(() => _identityFeedback = 'Cleared.');
                    SemanticsService.announce(
                      'Identity cleared.',
                      TextDirection.ltr,
                    );
                  },
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          if (_identityFeedback != null) ...[
            const SizedBox(height: 8),
            Text(
              _identityFeedback!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breadcrumbSection() {
    return _sectionCard(
      title: 'Breadcrumbs',
      subtitle: 'Last 5 actions ride along with every report.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Issuetracker.recordAction('viewed_home');
                    setState(() {
                      _recentBreadcrumbs.add('viewed_home');
                      if (_recentBreadcrumbs.length > 5) {
                        _recentBreadcrumbs.removeAt(0);
                      }
                    });
                    SemanticsService.announce(
                      'Recorded viewed_home',
                      TextDirection.ltr,
                    );
                  },
                  child: const Text('viewed_home'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Issuetracker.recordAction(
                      'tapped_button',
                      metadata: const {'id': 'settings'},
                    );
                    setState(() {
                      _recentBreadcrumbs.add('tapped_button');
                      if (_recentBreadcrumbs.length > 5) {
                        _recentBreadcrumbs.removeAt(0);
                      }
                    });
                    SemanticsService.announce(
                      'Recorded tapped_button',
                      TextDirection.ltr,
                    );
                  },
                  child: const Text('tapped_button'),
                ),
              ),
            ],
          ),
          if (_recentBreadcrumbs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Recorded: ${_recentBreadcrumbs.join(' → ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _onboardingSection() {
    return _sectionCard(
      title: 'Onboarding',
      subtitle:
          'Re-show the trigger introduction popover regardless of whether it has been shown before.',
      child: OutlinedButton(
        onPressed: () => Issuetracker.showOnboarding(),
        child: const Text('Show intro again'),
      ),
    );
  }

  Widget _i18nSection() {
    return _sectionCard(
      title: 'TERMINATED-UI i18n',
      subtitle:
          'When ON, the SDK shows the terminal screen in Norwegian. Applied immediately — no restart needed (the SDK accepts a new terminatedUI on every configure() call).',
      child: SwitchListTile(
        title: const Text('Norwegian strings'),
        contentPadding: EdgeInsets.zero,
        value: _useNorwegian,
        onChanged: (v) async {
          await widget.prefs.setBool(_prefUseNorwegianTerminatedUI, v);
          setState(() => _useNorwegian = v);
          await configureSdk(widget.prefs, useNorwegian: v);
        },
      ),
    );
  }

  Widget _destructiveSection() {
    final errorColor = Theme.of(context).colorScheme.error;
    return _sectionCard(
      title: 'Destructive',
      subtitle:
          'Test the crash-reporting flow. The app will die immediately and the SDK files an issue on next launch.',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: errorColor),
        onPressed: () => _confirmAndCrash(),
        child: const Text('Force crash'),
      ),
    );
  }

  Future<void> _confirmAndCrash() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force crash'),
        content: const Text(
          'This will throw and the app process will die. Re-open the app and the SDK will queue a crash report on the next launch.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Crash now'),
          ),
        ],
      ),
    );
    if (go == true) {
      await Issuetracker.testCrash();
    }
  }
}
