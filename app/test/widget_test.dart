import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:illusio/ui/screens/about_screen.dart';
import 'package:illusio/ui/theme.dart';

void main() {
  testWidgets('about screen shows name and version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildIllusioTheme(), home: const AboutScreen()),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Illusio'), findsWidgets);
    expect(find.textContaining('v0.1.0'), findsOneWidget);
    expect(find.textContaining('MIT'), findsOneWidget);
  });
}
