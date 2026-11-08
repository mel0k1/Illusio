import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color hullBlack = Color(0xFF0C0D0F);
const Color hullSurface = Color(0xFF16171B);
const Color hullRaised = Color(0xFF1F2126);
const Color edgeColor = Color(0xFF2B2D33);
const Color signalAmber = Color(0xFFFFC400);
const Color calmGreen = Color(0xFF7DDB8A);
const Color fogWhite = Color(0xFFEEECE5);
const Color mutedFog = Color(0xFF9A9A94);
const Color errorClay = Color(0xFFE5735F);

ThemeData buildIllusioTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: hullBlack,
    colorScheme: const ColorScheme.dark(
      primary: signalAmber,
      onPrimary: Color(0xFF1A1400),
      secondary: calmGreen,
      onSecondary: Color(0xFF0B1A0D),
      surface: hullSurface,
      onSurface: fogWhite,
      outlineVariant: edgeColor,
      error: errorClay,
      onError: Color(0xFF2A0E08),
    ),
  );
  final textTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: textTheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: const BorderSide(color: edgeColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    dividerTheme: const DividerThemeData(color: edgeColor, thickness: 1),
  );
}

InputDecoration illusioInput(String label, {String? hint}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(20),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: hullSurface,
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: const BorderSide(color: signalAmber),
    ),
  );
}

SnackBar illusioSnackBar(String message) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: hullRaised,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    content: Text(message),
  );
}
