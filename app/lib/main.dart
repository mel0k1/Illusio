import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const IllusioApp());
}

class IllusioApp extends StatefulWidget {
  const IllusioApp({super.key});

  @override
  State<IllusioApp> createState() => _IllusioAppState();
}

class _IllusioAppState extends State<IllusioApp> {
  final AppController _controller = AppController();

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
        return MaterialApp(
          title: 'Illusio',
          theme: buildIllusioTheme(Brightness.light),
          darkTheme: buildIllusioTheme(Brightness.dark),
          themeMode: mode,
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}
