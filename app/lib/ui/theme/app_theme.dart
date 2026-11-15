import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Material 3 theme built from the notebook tokens. Ink is the primary colour (buttons are written in ink);
/// the highlighter marks what is selected or important; cards are sheets of paper with a hairline edge.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? CaseColors.dark : CaseColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.ink,
    onPrimary: c.paper,
    primaryContainer: dark ? const Color(0xFF2A3A57) : const Color(0xFFDCE3F0),
    onPrimaryContainer: c.ink,
    secondary: c.inkSoft,
    onSecondary: c.paper,
    secondaryContainer: dark ? const Color(0xFF22324D) : const Color(0xFFE4E9E5),
    onSecondaryContainer: c.ink,
    tertiary: dark ? c.highlighter : const Color(0xFF7A5C00),
    onTertiary: c.onHighlighter,
    tertiaryContainer: c.stickyNote,
    onTertiaryContainer: c.ink,
    error: c.bad,
    onError: c.paper,
    errorContainer: c.badContainer,
    onErrorContainer: c.ink,
    surface: c.paper,
    onSurface: c.ink,
    onSurfaceVariant: c.inkSoft,
    surfaceContainerLowest: dark ? const Color(0xFF0F1A2D) : const Color(0xFFFFFFFF),
    surfaceContainerLow: dark ? const Color(0xFF172640) : const Color(0xFFF7F8F6),
    surfaceContainer: dark ? const Color(0xFF1A2A44) : const Color(0xFFEEF1ED),
    surfaceContainerHigh: dark ? const Color(0xFF20314D) : const Color(0xFFE8ECE7),
    surfaceContainerHighest: dark ? const Color(0xFF273957) : const Color(0xFFE1E6E1),
    outline: dark ? const Color(0xFF7686A1) : const Color(0xFF75837D),
    outlineVariant: c.grid,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: c.ink,
    onInverseSurface: c.paper,
    inversePrimary: dark ? const Color(0xFF1B2A4A) : const Color(0xFFDCE3F0),
    surfaceTint: Colors.transparent,
  );
  final text = buildTextTheme(c.ink, c.inkSoft);
  final radius12 = BorderRadius.circular(12);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    fontFamily: fontBody,
    textTheme: text,
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded, // 48 dp+ touch targets
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(color: c.grid, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: c.paperRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.grid)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink,
        foregroundColor: c.paper,
        disabledBackgroundColor: c.grid,
        disabledForegroundColor: c.inkMuted,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 52),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.ink, textStyle: text.labelLarge, minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.paperRaised,
      hintStyle: text.bodyLarge?.copyWith(color: c.inkMuted),
      labelStyle: text.bodyMedium?.copyWith(color: c.inkSoft),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c.ink, width: 2)),
      disabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c.grid)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.paperSunken,
      side: BorderSide.none,
      labelStyle: text.labelMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.paperRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.highlighter,
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? c.onHighlighter : c.inkSoft)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
          color: s.contains(WidgetState.selected) ? c.ink : c.inkSoft,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.paperRaised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: c.inkMuted,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.paperRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: text.titleLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: c.paper),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.grid, circularTrackColor: c.grid),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.highlighter : null),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onHighlighter : c.ink),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.paper : c.inkSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.paperSunken),
      trackOutlineColor: WidgetStatePropertyAll(scheme.outline),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: c.ink,
      collapsedIconColor: c.inkSoft,
      textColor: c.ink,
      collapsedTextColor: c.ink,
    ),
    listTileTheme: ListTileThemeData(iconColor: c.inkSoft, textColor: c.ink),
  );
}
