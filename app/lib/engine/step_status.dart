/// Whether a step counts as answered, for the finish rule (owner request 2026-11-16: a case cannot be finished
/// until every question is answered).
library;

import '../data/content_db.dart';
import '../data/models.dart';
import '../data/progress_db.dart';
import '../ui/steps/step_common.dart' show revealAfterAttempts;

enum StepStatus {
  /// Passed, solved, or its answer was revealed after three tries. Reading cards are always done.
  done,

  /// Tried but not yet passed (or answered before the examiner existed and not graded yet).
  started,

  /// Never answered.
  untouched,
}

StepStatus stepStatus(ProgressDb p, String caseId, StepData step) {
  if (step.isInfo) return StepStatus.done;
  if (step.isGraded) {
    if (p.examinerPassed(caseId, step.id) || p.examinedCount(caseId, step.id) >= revealAfterAttempts) return StepStatus.done;
    return p.attemptCount(caseId, step.id) > 0 ? StepStatus.started : StepStatus.untouched;
  }
  final n = p.attemptCount(caseId, step.id);
  if (p.solved(caseId, step.id) || n >= revealAfterAttempts) return StepStatus.done;
  return n > 0 ? StepStatus.started : StepStatus.untouched;
}

/// Steps that still need an answer before the case can be finished, in case order.
List<StepData> unfinishedSteps(ProgressDb p, String caseId, List<StepData> steps) =>
    [for (final s in steps) if (stepStatus(p, caseId, s) != StepStatus.done) s];

/// Cases marked finished while questions were still open (before the finish rule existed) are opened again.
void reopenUnfinishedCases(ContentDb content, ProgressDb progress) {
  for (final c in content.cases()) {
    if ((progress.caseState(c.id)?.completed ?? false) && unfinishedSteps(progress, c.id, content.steps(c.id)).isNotEmpty) {
      progress.reopenCase(c.id);
    }
  }
}
