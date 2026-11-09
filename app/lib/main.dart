import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'ffi/bindings.dart';
import 'l10n/strings.dart';
import 'state/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main(List<String> arguments) {
  final ipc = Core.ipcInit(jsonEncode(arguments));
  if (ipc['primary'] == false) {
    exit(0);
  }
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

  @override
  void initState() {
    super.initState();
    Future(() => Core.updateFinalize());
    _applyInitialServer();
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
              font: _controller.font,
              corners: _controller.corners,
              customColor: _controller.customColor,
            ),
            darkTheme: buildIllusioTheme(
              Brightness.dark,
              preset: _controller.theme,
              font: _controller.font,
              corners: _controller.corners,
              customColor: _controller.customColor,
            ),
            themeMode: mode,
            home: AppShell(controller: _controller),
          ),
        );
      },
    );
  }
}
