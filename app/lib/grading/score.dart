/// The deterministic half of the examiner: score from rubric weights, number check against the pipeline, pass rule.
library;

import '../data/models.dart';
import 'grader.dart';

final _numberRe = RegExp(r'(?<![A-Za-z])[-−]?\d+(?:[.,]\d+)?\s*%?');

/// Every number written in [text], read as written plus, for percentages, as a fraction ("27%" -> 27 and 0.27).
List<double> numbersIn(String text, {bool percentResult = false}) {
  final out = <double>[];
  for (final m in _numberRe.allMatches(text)) {
    var s = m.group(0)!.replaceAll('−', '-').replaceAll(' ', '');
    final pct = s.endsWith('%');
    s = s.replaceAll('%', '').replaceAll(',', '.');
    final x = double.tryParse(s);
    if (x == null) continue;
    out.add(x);
    if (pct || percentResult) out.add(x / 100);
  }
  return out;
}

/// True when [answer] contains a number within [tolerance] of the pipeline [result].
bool hasNumber(String answer, ResultEntry result, {double tolerance = 0, bool acceptPercent = false}) {
  final v = result.value;
  if (v is! num) return true; // nothing numeric to check
  final target = v.toDouble();
  final pctShown = acceptPercent || result.display.trim().endsWith('%');
  final eps = 1e-9 + tolerance.abs();
  for (final x in numbersIn(answer, percentResult: pctShown)) {
    if ((x - target).abs() <= eps) return true;
    // A value shown as e.g. "-0.12" is often written without its sign ("fell by 0.12").
    if ((x.abs() - target.abs()).abs() <= eps) return true;
  }
  return false;
}

/// Applies the number check: a point with a numeric anchor whose number the answer does not get right keeps at
/// most partial credit.
List<PointVerdict> applyNumberAnchors(StepData step, List<PointVerdict> points, String answer, Map<String, ResultEntry> results) {
  final rubricPoints = {
    for (final p in (step.rubric?['points'] as List? ?? const [])) (p as Map)['id'] as String: p,
  };
  return [
    for (final v in points)
      () {
        final numeric = (rubricPoints[v.id]?['numeric']) as Map?;
        if (numeric == null || v.coverage != Coverage.full) return v;
        final r = results[numeric['key'] as String];
        if (r == null) return v;
        final ok = hasNumber(answer, r,
            tolerance: (numeric['tolerance'] as num?)?.toDouble() ?? 0, acceptPercent: numeric['accept_percent'] == true);
        if (ok) return v;
        return PointVerdict(
          id: v.id, label: v.label, weight: v.weight, coverage: Coverage.partial, evidence: v.evidence,
          missing: v.missing.isEmpty ? 'Quote the pipeline number for this point.' : v.missing,
          hint: v.hint, why: v.why, numberCapped: true,
        );
      }(),
  ];
}

/// Σ weight × coverage − penalties, clipped to 0..100.
double scoreOf(List<PointVerdict> points, List<FlagVerdict> flags) {
  final earned = points.fold<double>(0, (a, p) => a + p.earned);
  final penalty = flags.fold<double>(0, (a, f) => a + f.penalty);
  return (earned - penalty).clamp(0, 100).toDouble();
}

/// Pass = score ≥ 85 and no critical red flag.
bool passes(double score, List<FlagVerdict> flags) => score >= passMark && !flags.any((f) => f.critical);
