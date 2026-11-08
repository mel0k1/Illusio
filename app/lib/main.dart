import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const IllusioApp());
}

class IllusioApp extends StatelessWidget {
  const IllusioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Illusio',
      theme: buildIllusioTheme(),
      home: const HomeScreen(),
    );
  }
}
