import 'package:flutter/material.dart';

/// Archivo (Omnibus-Type, OFL) carries the personality: its condensed cut sets headings and numbers the way
/// timing towers, departure boards and tickers do; the normal width is for reading. JetBrains Mono (OFL) is
/// used only inside code. Both are bundled (assets/fonts), so the app looks the same offline.
const fontBody = 'Archivo';
const fontDisplay = 'ArchivoCondensed';
const fontCode = 'JetBrainsMono';

/// JetBrains Mono draws '==' or '->' as single glyphs by default; code shown to learners keeps every character.
const codeFeatures = [FontFeature.disable('calt'), FontFeature.disable('liga')];

TextTheme buildTextTheme(Color ink, Color inkSoft) {
  TextStyle display(double size, FontWeight w, {double height = 1.05, double spacing = 0}) =>
      TextStyle(fontFamily: fontDisplay, fontSize: size, fontWeight: w, height: height, letterSpacing: spacing, color: ink);
  TextStyle body(double size, FontWeight w, {double height = 1.45, double spacing = 0, Color? color}) =>
      TextStyle(fontFamily: fontBody, fontSize: size, fontWeight: w, height: height, letterSpacing: spacing, color: color ?? ink);

  return TextTheme(
    displayLarge: display(60, FontWeight.w800, height: 0.92, spacing: -1.0),
    displayMedium: display(46, FontWeight.w800, height: 0.95, spacing: -0.6),
    displaySmall: display(38, FontWeight.w700, height: 1.0, spacing: -0.4),
    headlineLarge: display(34, FontWeight.w700, height: 1.02, spacing: -0.3),
    headlineMedium: display(29, FontWeight.w700, height: 1.05, spacing: -0.2),
    headlineSmall: display(26, FontWeight.w700, height: 1.08, spacing: -0.1),
    titleLarge: display(23, FontWeight.w700, height: 1.12),
    titleMedium: body(17, FontWeight.w600, height: 1.3),
    titleSmall: body(15, FontWeight.w600, height: 1.3),
    bodyLarge: body(17, FontWeight.w400),
    bodyMedium: body(15, FontWeight.w400),
    bodySmall: body(13, FontWeight.w400, height: 1.35, color: inkSoft),
    labelLarge: body(15, FontWeight.w600, height: 1.2, spacing: 0.1),
    labelMedium: body(13, FontWeight.w500, height: 1.2, spacing: 0.1),
    labelSmall: body(11.5, FontWeight.w500, height: 1.2, spacing: 0.2),
  );
}
