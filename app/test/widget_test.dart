import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:illusio/ui/theme.dart';

void main() {
  testWidgets('dark and light themes are valid', (tester) async {
    final dark = buildIllusioTheme(Brightness.dark);
    final light = buildIllusioTheme(Brightness.light);
    expect(dark.useMaterial3, isTrue);
    expect(light.useMaterial3, isTrue);
    expect(dark.colorScheme.surfaceContainer, isNot(dark.colorScheme.surface));
    expect(
        light.colorScheme.surfaceContainer, isNot(light.colorScheme.surface));
    expect(dark.colorScheme.primary, isNot(dark.colorScheme.surface));
    expect(light.colorScheme.primary, isNot(light.colorScheme.surface));
    expect(dark.colorScheme.primaryContainer, dark.colorScheme.primary);
    expect(light.colorScheme.primaryContainer, light.colorScheme.primary);
  });

  testWidgets('theme input decoration exposes label and hint', (tester) async {
    final decoration = illusioInput('Адрес', hint: 'ss14://example.com');
    expect(decoration.labelText, 'Адрес');
    expect(decoration.hintText, 'ss14://example.com');
  });

  testWidgets('custom color and corners reshape the theme', (tester) async {
    final custom = buildIllusioTheme(
      Brightness.dark,
      preset: 'custom',
      customColor: 0x7C5CFF,
    );
    expect(custom.colorScheme.primary, isNot(inkDarkScheme.primary));
    final compact = buildIllusioTheme(Brightness.dark, corners: 'compact');
    final round = buildIllusioTheme(Brightness.dark, corners: 'round');
    final compactRadius =
        (compact.cardTheme.shape as RoundedRectangleBorder).borderRadius;
    final roundRadius =
        (round.cardTheme.shape as RoundedRectangleBorder).borderRadius;
    expect(roundRadius, isNot(compactRadius));
  });
}
