import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color hullBlack = Color(0xFF17140F);
const Color hullSurface = Color(0xFF231F18);
const Color hullRaised = Color(0xFF2E2922);
const Color edgeColor = Color(0xFF52483A);
const Color signalAmber = Color(0xFFFFD65C);
const Color calmGreen = Color(0xFF93D69B);
const Color fogWhite = Color(0xFFF2E9D9);
const Color mutedFog = Color(0xFFD6C9AE);
const Color errorClay = Color(0xFFFFB4AB);

const Color hullBlackLight = Color(0xFFFFF8F0);
const Color hullSurfaceLight = Color(0xFFF4ECDF);
const Color hullRaisedLight = Color(0xFFEEE7D9);
const Color edgeColorLight = Color(0xFFD0C9B5);

const Color surfaceWarmDark = Color(0xFF1F1B14);

const ColorScheme darkScheme = ColorScheme.dark(
  primary: signalAmber,
  onPrimary: Color(0xFF3A2E00),
  primaryContainer: Color(0xFF5C4800),
  onPrimaryContainer: Color(0xFFFFE08D),
  secondary: calmGreen,
  onSecondary: Color(0xFF0A3316),
  secondaryContainer: Color(0xFF2A4A2E),
  onSecondaryContainer: Color(0xFFB4E9B8),
  tertiary: Color(0xFFD9C3FF),
  onTertiary: Color(0xFF341D66),
  tertiaryContainer: Color(0xFF4B367D),
  onTertiaryContainer: Color(0xFFEADDFF),
  error: errorClay,
  onError: Color(0xFF442925),
  errorContainer: Color(0xFF6A2B24),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: hullBlack,
  onSurface: fogWhite,
  onSurfaceVariant: mutedFog,
  surfaceContainerLowest: Color(0xFF0C0A07),
  surfaceContainerLow: surfaceWarmDark,
  surfaceContainer: hullSurface,
  surfaceContainerHigh: hullRaised,
  surfaceContainerHighest: Color(0xFF39332B),
  onInverseSurface: Color(0xFF35302B),
  inverseSurface: fogWhite,
  inversePrimary: Color(0xFF775A00),
  outline: Color(0xFF9F927B),
  outlineVariant: edgeColor,
  scrim: Color(0xFF000000),
);

const ColorScheme lightScheme = ColorScheme.light(
  primary: Color(0xFF775A00),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFE08D),
  onPrimaryContainer: Color(0xFF241A00),
  secondary: Color(0xFF3B6E41),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFC2EFC1),
  onSecondaryContainer: Color(0xFF00210A),
  tertiary: Color(0xFF654DBA),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFEADDFF),
  onTertiaryContainer: Color(0xFF21005D),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: hullBlackLight,
  onSurface: Color(0xFF201B11),
  onSurfaceVariant: Color(0xFF4C4636),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFAF2E7),
  surfaceContainer: hullSurfaceLight,
  surfaceContainerHigh: hullRaisedLight,
  surfaceContainerHighest: Color(0xFFE8E1D4),
  onInverseSurface: Color(0xFFFBF2E7),
  inverseSurface: Color(0xFF35302B),
  inversePrimary: Color(0xFFFFD65C),
  outline: Color(0xFF7E7653),
  outlineVariant: edgeColorLight,
  scrim: Color(0xFF000000),
);

const Duration spatialFast = Duration(milliseconds: 280);
const Duration spatialDefault = Duration(milliseconds: 380);
const Duration effectsFast = Duration(milliseconds: 160);
const Curve springCurve = Curves.easeOutBack;
const Curve expressCurve = Curves.easeOutCubic;

class IllusioPreset {
  const IllusioPreset(
    this.id,
    this.primary,
    this.onPrimary,
    this.primaryContainer,
    this.onPrimaryContainer,
  );

  final String id;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
}

const List<IllusioPreset> illusioPresets = [
  IllusioPreset('dark', signalAmber, Color(0xFF3A2E00), Color(0xFF5C4800), Color(0xFFFFE08D)),
  IllusioPreset('darkRed', Color(0xFFFFB4A0), Color(0xFF5B1500), Color(0xFF7C2C00), Color(0xFFFFDBCF)),
  IllusioPreset('darkPurple', Color(0xFFD0B4FF), Color(0xFF381E72), Color(0xFF4F378B), Color(0xFFEADDFF)),
  IllusioPreset('midnightBlue', Color(0xFFAAC7FF), Color(0xFF002F67), Color(0xFF00458F), Color(0xFFD6E3FF)),
  IllusioPreset('emeraldDusk', calmGreen, Color(0xFF00390F), Color(0xFF1F5123), Color(0xFFB4F1B5)),
  IllusioPreset('copperNight', Color(0xFFFFB77E), Color(0xFF4A2800), Color(0xFF6B3D0D), Color(0xFFFFDCC2)),
];

ColorScheme _applyPreset(ColorScheme scheme, String preset) {
  for (final value in illusioPresets) {
    if (value.id != preset) {
      continue;
    }
    return scheme.copyWith(
      primary: value.primary,
      onPrimary: value.onPrimary,
      primaryContainer: value.primaryContainer,
      onPrimaryContainer: value.onPrimaryContainer,
    );
  }
  return scheme;
}

ThemeData buildIllusioTheme(Brightness brightness, {String preset = 'dark'}) {
  final base = brightness == Brightness.dark ? darkScheme : lightScheme;
  final scheme = brightness == Brightness.dark
      ? _applyPreset(base, preset)
      : base;
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

  return base.copyWith(
    textTheme: body,
    iconTheme: base.iconTheme.copyWith(color: scheme.onSurfaceVariant),
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
    ),
    chipTheme: base.chipTheme.copyWith(
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
