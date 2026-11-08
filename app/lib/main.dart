import 'dart:isolate';

import 'package:flutter/material.dart';

import 'ffi/bindings.dart';
import 'l10n/strings.dart';
import 'state/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';
import 'version.dart';

void main(List<String> arguments) {
  runApp(IllusioApp(initialServer: _initialServer(arguments)));
}

String? _initialServer(List<String> arguments) {
  for (final argument in arguments) {
    final value = argument.trim();
    if (value.toLowerCase().startsWith('ss14://') ||
        value.toLowerCase().startsWith('ss14s://')) {
      return value;
    }
  }
  return null;
}

class IllusioApp extends StatefulWidget {
  const IllusioApp({super.key, this.initialServer});

  final String? initialServer;

  @override
  State<IllusioApp> createState() => _IllusioAppState();
}

class _IllusioAppState extends State<IllusioApp> {
  final AppController _controller = AppController();
  bool _blocked = false;
  String _blockReason = '';

  @override
  void initState() {
    super.initState();
    _checkVersion();
    _applyInitialServer();
  }

  Future<void> _checkVersion() async {
    await _controller.ready;
    final result = await _controller.checkLauncherUpdate(appVersion);
    if (result['ok'] != true || result['blocked'] != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _blocked = true;
      _blockReason = result['reason']?.toString() ?? _controller.s.outdatedVersion;
    });
  }

  Future<void> _applyInitialServer() async {
    final server = widget.initialServer;
    if (server == null || server.isEmpty) {
      return;
    }
    await _controller.ready;
    _controller.pendingConnect = server;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final mode = switch (_controller.theme) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.dark,
        };
        return SB(
          s: _controller.s,
          child: MaterialApp(
            title: 'Illusio',
            theme: buildIllusioTheme(
              Brightness.light,
              preset: _controller.theme,
            ),
            darkTheme: buildIllusioTheme(
              Brightness.dark,
              preset: _controller.theme,
            ),
            themeMode: mode,
            home: _blocked
                ? _BlockedScreen(reason: _blockReason)
                : AppShell(controller: _controller),
          ),
        );
      },
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pause_circle_outline, size: 56, color: scheme.error),
              const SizedBox(height: 20),
              Text(
                s.blockedTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                reason,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () {
                  _open(context, 'https://github.com/mel0k1/Illusio/releases');
                },
                icon: const Icon(Icons.open_in_new, size: 20),
                label: Text(s.openReleases),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    await Isolate.run(() => Core.openUrl(url));
  }
}
