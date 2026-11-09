import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/engine/placeholders.dart';
import 'package:case_trainer/grading/grader.dart';
import 'package:case_trainer/ui/steps/step_common.dart';

/// The REAL bundle written by pipeline/build_content.py (tests run with cwd = app/).
ContentDb realContent() => ContentDb.openFile(contentAsset);

const p50 = 'p50_yield_curve';

Resolver resolverFor(ContentDb c, String caseId) => Resolver(c.results(caseId), c.captured(caseId));

StepScope scopeFor(ContentDb c, ProgressDb p, String caseId, int idx) {
  final steps = c.steps(caseId);
  return StepScope(
    caseInfo: c.caseById(caseId),
    step: steps[idx],
    resolver: resolverFor(c, caseId),
    content: c,
    progress: p,
    grader: const StubGrader(),
    onProgress: () {},
  );
}
