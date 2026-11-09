import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const ColorScheme inkDarkScheme = ColorScheme.dark(
  primary: Color(0xFFF2F2F3),
  onPrimary: Color(0xFF111113),
  primaryContainer: Color(0xFFF2F2F3),
  onPrimaryContainer: Color(0xFF111113),
  secondary: Color(0xFFC3C3C9),
  onSecondary: Color(0xFF1C1C1F),
  secondaryContainer: Color(0xFF2E2E33),
  onSecondaryContainer: Color(0xFFE4E4E8),
  tertiary: Color(0xFFABABB2),
  onTertiary: Color(0xFF19191C),
  tertiaryContainer: Color(0xFF333338),
  onTertiaryContainer: Color(0xFFE0E0E4),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF5F1512),
  errorContainer: Color(0xFF7A201B),
  onErrorContainer: Color(0xFFFFDAD5),
  surface: Color(0xFF0B0B0C),
  onSurface: Color(0xFFEDEDEF),
  onSurfaceVariant: Color(0xFFB2B2B8),
  surfaceContainerLowest: Color(0xFF060607),
  surfaceContainerLow: Color(0xFF131315),
  surfaceContainer: Color(0xFF18181B),
  surfaceContainerHigh: Color(0xFF222225),
  surfaceContainerHighest: Color(0xFF2D2D31),
  onInverseSurface: Color(0xFF151517),
  inverseSurface: Color(0xFFEDEDEF),
  inversePrimary: Color(0xFF2B2B2F),
  outline: Color(0xFF8A8A91),
  outlineVariant: Color(0xFF38383D),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFFF2F2F3),
);

const ColorScheme inkLightScheme = ColorScheme.light(
  primary: Color(0xFF131315),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF131315),
  onPrimaryContainer: Color(0xFFF4F4F5),
  secondary: Color(0xFF54545B),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE8E8EB),
  onSecondaryContainer: Color(0xFF1A1A1D),
  tertiary: Color(0xFF6B6B72),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFE2E2E6),
  onTertiaryContainer: Color(0xFF1A1A1D),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF131315),
  onSurfaceVariant: Color(0xFF5E5E65),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFAFAFA),
  surfaceContainer: Color(0xFFF4F4F5),
  surfaceContainerHigh: Color(0xFFEFEFF1),
  surfaceContainerHighest: Color(0xFFE7E7EA),
  onInverseSurface: Color(0xFFF2F2F3),
  inverseSurface: Color(0xFF1B1B1E),
  inversePrimary: Color(0xFFF2F2F3),
  outline: Color(0xFF7B7B82),
  outlineVariant: Color(0xFFDBDBDF),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFF131315),
);

const Map<String, Color> inkPresetSeeds = {
  'darkRed': Color(0xFFFFB4A9),
  'darkPurple': Color(0xFFD0B4FF),
  'midnightBlue': Color(0xFFAAC7FF),
  'emeraldDusk': Color(0xFF9CD69D),
  'copperNight': Color(0xFFFFB77E),
};

Color themeDot(String id) {
  final seed = inkPresetSeeds[id];
  if (seed != null) {
    return seed;
  }
  return switch (id) {
    'dark' => const Color(0xFFF2F2F3),
    'light' => const Color(0xFF131315),
    _ => const Color(0xFF8A8A91),
  };
}

ColorScheme _presetScheme(String preset) {
  final seed = inkPresetSeeds[preset];
  if (seed == null) {
    return inkDarkScheme;
  }
  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );
}

const Duration spatialFast = Duration(milliseconds: 280);
const Duration spatialDefault = Duration(milliseconds: 380);
const Duration effectsFast = Duration(milliseconds: 160);
const Curve springCurve = Curves.easeOutBack;
const Curve expressCurve = Easing.emphasizedDecelerate;
const Curve settleCurve = Easing.standard;
const Curve exitCurve = Easing.emphasizedAccelerate;

ThemeData buildIllusioTheme(Brightness brightness, {String preset = 'dark'}) {
  final scheme = brightness == Brightness.dark
      ? _presetScheme(preset)
      : inkLightScheme;
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
  );
  final textTheme = GoogleFonts.robotoFlexTextTheme(
    theme.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
  );
  final body = textTheme.copyWith(
    headlineLarge: textTheme.headlineLarge
        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
    headlineMedium:
        textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
    headlineSmall:
        textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelLarge: textTheme.labelLarge
        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    labelMedium: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
  );

  final stadium =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  final buttonPadding =
      const EdgeInsets.symmetric(horizontal: 24, vertical: 14);

  return theme.copyWith(
    textTheme: body,
    iconTheme: theme.iconTheme.copyWith(color: scheme.onSurfaceVariant),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: body.titleLarge,
      contentTextStyle: body.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      modalBarrierColor: Colors.black.withValues(alpha: 0.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: stadium,
        padding: buttonPadding,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: body.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: stadium,
        side: BorderSide(color: scheme.outlineVariant),
        padding: buttonPadding,
        foregroundColor: scheme.primary,
        textStyle: body.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: stadium,
        padding: buttonPadding,
        foregroundColor: scheme.primary,
        textStyle: body.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        highlightColor: scheme.primary.withValues(alpha: 0.12),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        )),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        textStyle: WidgetStatePropertyAll(body.labelLarge),
      ),
      selectedIcon: const Icon(Icons.check, size: 16),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return scheme.surfaceContainerHighest;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.onPrimary;
        }
        return scheme.outline;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return scheme.outlineVariant;
      }),
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Icon(Icons.check, size: 14, color: scheme.onPrimary);
        }
        return null;
      }),
      overlayColor: WidgetStatePropertyAll(
        scheme.primary.withValues(alpha: 0.08),
      ),
    ),
    chipTheme: theme.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: body.labelMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle:
          body.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme:
        DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      hintStyle: body.bodyMedium
          ?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
      strokeCap: StrokeCap.round,
      stopIndicatorColor: scheme.primary,
      stopIndicatorRadius: 4,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      iconColor: scheme.onSurfaceVariant,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: body.labelMedium?.copyWith(color: scheme.onInverseSurface),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textStyle: body.bodyMedium,
      elevation: 6,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        )),
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      backgroundColor: scheme.surfaceContainerLow,
      collapsedBackgroundColor: scheme.surfaceContainerLow,
      iconColor: scheme.primary,
      collapsedIconColor: scheme.onSurfaceVariant,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );
}

InputDecoration illusioInput(String label,
    {String? hint, Widget? suffix, Widget? prefixIcon}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    prefixIcon: prefixIcon,
  );
}

SnackBar illusioSnackBar(
  String message, {
  bool error = false,
  Color? errorColor,
}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    content: Text(message),
    backgroundColor: error ? errorColor : null,
  );
}
