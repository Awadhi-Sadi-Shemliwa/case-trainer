/// The examiner (owner decision 2026-11-16, docs/knowledge/GRADING.md): Claude judges how well each rubric point is
/// covered and quotes the sentences that are wrong; the app computes the score from the rubric weights, checks the
/// numbers against the pipeline, and decides pass = score >= 85 with no critical red flag.
library;

import '../data/models.dart';
import '../engine/placeholders.dart';

/// Pass mark (spec §5).
const passMark = 85.0;

/// Coverage of one rubric point, as judged by the examiner.
enum Coverage {
  full(1),
  partial(0.5),
  none(0);

  const Coverage(this.value);
  final double value;

  static Coverage parse(Object? s) => switch (s) {
        'full' => Coverage.full,
        'partial' => Coverage.partial,
        _ => Coverage.none,
      };
}

/// One rubric point after grading.
class PointVerdict {
  const PointVerdict({
    required this.id,
    required this.label,
    required this.weight,
    required this.coverage,
    this.evidence = '',
    this.missing = '',
    this.hint,
    this.why,
    this.numberCapped = false,
  });

  final String id;
  final String label;
  final double weight;
  final Coverage coverage;

  /// The learner's own words that earned the credit.
  final String evidence;

  /// What the examiner says is missing or wrong for this point.
  final String missing;
  final String? hint;
  final String? why;

  /// True when the point needed a pipeline number the answer did not get right (credit capped at partial).
  final bool numberCapped;

  double get earned => weight * coverage.value;

  Map<String, dynamic> toJson() => {
        'id': id, 'label': label, 'weight': weight, 'coverage': coverage.name, 'evidence': evidence,
        'missing': missing, 'hint': hint, 'why': why, 'number_capped': numberCapped,
      };

  factory PointVerdict.fromJson(Map<String, dynamic> j) => PointVerdict(
        id: j['id'] as String,
        label: j['label'] as String,
        weight: (j['weight'] as num).toDouble(),
        coverage: Coverage.parse(j['coverage']),
        evidence: j['evidence'] as String? ?? '',
        missing: j['missing'] as String? ?? '',
        hint: j['hint'] as String?,
        why: j['why'] as String?,
        numberCapped: j['number_capped'] as bool? ?? false,
      );
}

/// A sentence of the answer that is wrong, quoted, with what is wrong and the correct version.
class PinpointedError {
  const PinpointedError({required this.quote, required this.problem, required this.correction});
  final String quote;
  final String problem;
  final String correction;

  Map<String, dynamic> toJson() => {'quote': quote, 'problem': problem, 'correction': correction};
  factory PinpointedError.fromJson(Map<String, dynamic> j) => PinpointedError(
      quote: j['quote'] as String? ?? '', problem: j['problem'] as String? ?? '', correction: j['correction'] as String? ?? '');
}

/// A red flag the answer raised.
class FlagVerdict {
  const FlagVerdict({required this.id, required this.critical, required this.penalty, required this.feedback, this.quote = ''});
  final String id;
  final bool critical;
  final double penalty;
  final String feedback;
  final String quote;

  Map<String, dynamic> toJson() => {'id': id, 'critical': critical, 'penalty': penalty, 'feedback': feedback, 'quote': quote};
  factory FlagVerdict.fromJson(Map<String, dynamic> j) => FlagVerdict(
        id: j['id'] as String,
        critical: j['critical'] as bool? ?? false,
        penalty: (j['penalty'] as num?)?.toDouble() ?? 0,
        feedback: j['feedback'] as String? ?? '',
        quote: j['quote'] as String? ?? '',
      );
}

enum GradeStatus {
  /// Graded: score and verdicts are set.
  graded,

  /// "I don't know" (or nothing to grade): counts as an attempt and unlocks the next hint.
  noAttempt,

  /// The examiner could not be reached; the answer is kept and the attempt is NOT used up.
  unavailable,
}

class GradeResult {
  const GradeResult({
    required this.status,
    this.score,
    this.passed = false,
    this.points = const [],
    this.errors = const [],
    this.flags = const [],
    this.strengths = const [],
    this.summary = '',
    this.message = '',
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.usage,
  });

  final GradeStatus status;
  final double? score;
  final bool passed;
  final List<PointVerdict> points;
  final List<PinpointedError> errors;
  final List<FlagVerdict> flags;
  final List<String> strengths;
  final String summary;

  /// Why the examiner was unavailable, or a short note.
  final String message;
  final String? model;
  final int? inputTokens;
  final int? outputTokens;

  /// Tokens, cache reads, retries, time and estimated cost of the call (null for local verdicts).
  final Map<String, dynamic>? usage;

  bool get graded => status == GradeStatus.graded;
  bool get countsAsAttempt => status != GradeStatus.unavailable;
  List<PointVerdict> get missingPoints => [for (final p in points) if (p.coverage != Coverage.full) p];

  Map<String, dynamic> toJson() => {
        'status': status.name, 'score': score, 'passed': passed,
        'points': [for (final p in points) p.toJson()],
        'errors': [for (final e in errors) e.toJson()],
        'flags': [for (final f in flags) f.toJson()],
        'strengths': strengths, 'summary': summary, 'message': message, 'model': model,
        if (usage != null) 'usage': usage,
      };

  factory GradeResult.fromJson(Map<String, dynamic> j) => GradeResult(
        status: GradeStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => GradeStatus.graded),
        score: (j['score'] as num?)?.toDouble(),
        passed: j['passed'] as bool? ?? false,
        points: [for (final p in (j['points'] as List? ?? const [])) PointVerdict.fromJson(p as Map<String, dynamic>)],
        errors: [for (final e in (j['errors'] as List? ?? const [])) PinpointedError.fromJson(e as Map<String, dynamic>)],
        flags: [for (final f in (j['flags'] as List? ?? const [])) FlagVerdict.fromJson(f as Map<String, dynamic>)],
        strengths: List<String>.from(j['strengths'] as List? ?? const []),
        summary: j['summary'] as String? ?? '',
        message: j['message'] as String? ?? '',
        model: j['model'] as String?,
        usage: (j['usage'] as Map?)?.cast<String, dynamic>(),
      );
}

abstract interface class Grader {
  /// False when the grader can never grade (tests without a network, no key).
  bool get isLive;
  Future<GradeResult> grade(StepData step, String answer, Resolver resolver, {CaseInfo? caseInfo});
}

/// Grader that is never available (widget tests and builds without a key).
class OfflineGrader implements Grader {
  const OfflineGrader([this.reason = 'No Claude API key. Add one in Settings to have your answers graded.']);
  final String reason;

  @override
  bool get isLive => false;

  @override
  Future<GradeResult> grade(StepData step, String answer, Resolver resolver, {CaseInfo? caseInfo}) async =>
      GradeResult(status: GradeStatus.unavailable, message: reason);
}
