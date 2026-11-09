/// The examiner interface. Prompt 6 replaces [StubGrader] with the embedding + rubric grader
/// (spec §5: deterministic, offline, pass = score >= 85 and no critical red flag).
library;

import '../data/models.dart';

class GradeResult {
  const GradeResult({required this.graded, this.score, this.passed, this.message = ''});
  final bool graded;
  final double? score;
  final bool? passed;
  final String message;
}

abstract interface class Grader {
  bool get isStub;
  GradeResult grade(StepData step, String answer);
}

class StubGrader implements Grader {
  const StubGrader();

  @override
  bool get isStub => true;

  @override
  GradeResult grade(StepData step, String answer) => const GradeResult(
        graded: false,
        message: 'Not graded yet. The examiner arrives in Prompt 6. Your answer is saved.',
      );
}
