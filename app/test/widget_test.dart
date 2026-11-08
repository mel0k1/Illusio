import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:illusio/ui/screens/about_screen.dart';
import 'package:illusio/ui/theme.dart';
import 'package:illusio/version.dart';

void main() {
  testWidgets('about screen shows name and version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildIllusioTheme(), home: const AboutScreen()),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Illusio'), findsWidgets);
    expect(find.text('v$appVersion'), findsOneWidget);
    expect(find.textContaining('MIT'), findsOneWidget);
    expect(find.textContaining('Material 3 Expressive'), findsNothing);
  });
}
