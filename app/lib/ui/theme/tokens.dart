import 'package:flutter/material.dart';

/// "The analyst's working notebook" (owner's choice, 2026-11-15): real data marked up to reach a decision.
/// Cool graph paper and navy ink; pipeline numbers look highlighted on a printout; the four sectors are the
/// four series of one chart. Everything else stays quiet.
///
/// Sector colours were checked with the data-viz palette validator against each surface, all pairs
/// (they meet on the cover): light passes every check (aviation/football/finance need direct labels, which
/// every use has); dark passes every check outright. Text never wears a sector colour.
@immutable
class CaseColors extends ThemeExtension<CaseColors> {
  const CaseColors({
    required this.paper,
    required this.paperRaised,
    required this.paperSunken,
    required this.grid,
    required this.rule,
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.highlighter,
    required this.onHighlighter,
    required this.stickyNote,
    required this.codeBg,
    required this.codeFg,
    required this.good,
    required this.goodContainer,
    required this.bad,
    required this.badContainer,
    required this.aviation,
    required this.f1,
    required this.football,
    required this.finance,
  });

  /// Page background: cool graph paper (light) or night navy (dark).
  final Color paper;

  /// Cards and sheets: a fresh sheet laid on the page.
  final Color paperRaised;

  /// Inputs and wells.
  final Color paperSunken;

  /// Graph-paper grid and hairline dividers (decorative only).
  final Color grid;

  /// Ruled lines in the answer box.
  final Color rule;

  final Color ink;
  final Color inkSoft;
  final Color inkMuted;

  /// Behind every pipeline number (value chips), like a highlighter on a printout.
  final Color highlighter;
  final Color onHighlighter;

  /// The plan to challenge is a sticky note on the page.
  final Color stickyNote;

  final Color codeBg;
  final Color codeFg;

  final Color good;
  final Color goodContainer;
  final Color bad;
  final Color badContainer;

  final Color aviation;
  final Color f1;
  final Color football;
  final Color finance;

  Color sector(String domain) => switch (domain) {
        'aviation' => aviation,
        'f1' => f1,
        'football' => football,
        'finance' => finance,
        _ => inkSoft,
      };

  static const light = CaseColors(
    paper: Color(0xFFF2F4F1),
    paperRaised: Color(0xFFFBFCFA),
    paperSunken: Color(0xFFE8ECE7),
    grid: Color(0xFFD6DDD8),
    rule: Color(0xFFDDE3EC),
    ink: Color(0xFF1B2A4A),
    inkSoft: Color(0xFF4A5874),
    inkMuted: Color(0xFF6B778D),
    highlighter: Color(0xFFF6D84A),
    onHighlighter: Color(0xFF1B2A4A),
    stickyNote: Color(0xFFFFF3BF),
    codeBg: Color(0xFF16233A),
    codeFg: Color(0xFFE4EAF4),
    good: Color(0xFF1E6B45),
    goodContainer: Color(0xFFDDEFE3),
    bad: Color(0xFFA8231C),
    badContainer: Color(0xFFF8DEDA),
    aviation: Color(0xFF1F5FBF),
    f1: Color(0xFFD43D2F),
    football: Color(0xFF1FA596),
    finance: Color(0xFFD9A21B),
  );

  static const dark = CaseColors(
    paper: Color(0xFF132036),
    paperRaised: Color(0xFF1A2A44),
    paperSunken: Color(0xFF0F1A2D),
    grid: Color(0xFF24334C),
    rule: Color(0xFF2A3B57),
    ink: Color(0xFFE4EAF4),
    inkSoft: Color(0xFFB4C0D4),
    inkMuted: Color(0xFF8E9BB2),
    highlighter: Color(0xFFE9C93F),
    onHighlighter: Color(0xFF132036),
    stickyNote: Color(0xFF2E3A4F),
    codeBg: Color(0xFF0C1626),
    codeFg: Color(0xFFE4EAF4),
    good: Color(0xFF7FD3A3),
    goodContainer: Color(0xFF1C3B33),
    bad: Color(0xFFF2A49C),
    badContainer: Color(0xFF4A2229),
    aviation: Color(0xFF3A78D8),
    f1: Color(0xFFC94432),
    football: Color(0xFF16A090),
    finance: Color(0xFFB98D17),
  );

  @override
  CaseColors copyWith() => this;

  @override
  CaseColors lerp(ThemeExtension<CaseColors>? other, double t) {
    if (other is! CaseColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CaseColors(
      paper: l(paper, other.paper),
      paperRaised: l(paperRaised, other.paperRaised),
      paperSunken: l(paperSunken, other.paperSunken),
      grid: l(grid, other.grid),
      rule: l(rule, other.rule),
      ink: l(ink, other.ink),
      inkSoft: l(inkSoft, other.inkSoft),
      inkMuted: l(inkMuted, other.inkMuted),
      highlighter: l(highlighter, other.highlighter),
      onHighlighter: l(onHighlighter, other.onHighlighter),
      stickyNote: l(stickyNote, other.stickyNote),
      codeBg: l(codeBg, other.codeBg),
      codeFg: l(codeFg, other.codeFg),
      good: l(good, other.good),
      goodContainer: l(goodContainer, other.goodContainer),
      bad: l(bad, other.bad),
      badContainer: l(badContainer, other.badContainer),
      aviation: l(aviation, other.aviation),
      f1: l(f1, other.f1),
      football: l(football, other.football),
      finance: l(finance, other.finance),
    );
  }
}

extension CaseTheme on BuildContext {
  CaseColors get colors => Theme.of(this).extension<CaseColors>() ?? CaseColors.light;
}

/// Icon per sector (shown next to the sector name, never alone).
IconData sectorIcon(String domain) => switch (domain) {
      'aviation' => Icons.flight_takeoff_rounded,
      'f1' => Icons.sports_motorsports_rounded,
      'football' => Icons.sports_soccer_rounded,
      'finance' => Icons.show_chart_rounded,
      _ => Icons.folder_open_rounded,
    };
