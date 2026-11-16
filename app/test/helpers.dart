import 'package:case_trainer/app.dart';
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/engine/placeholders.dart';
import 'package:case_trainer/data/models.dart';
import 'package:case_trainer/grading/grader.dart';
import 'package:case_trainer/providers.dart';
import 'package:case_trainer/ui/steps/step_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the whole app on a phone-sized view (S21+: 1080 × 2400 at 2.6) with the given databases.
Future<void> pumpApp(WidgetTester tester, ContentDb content, ProgressDb progress,
    {bool showCover = false, Grader grader = const OfflineGrader()}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      contentDbProvider.overrideWithValue(content),
      progressDbProvider.overrideWithValue(progress),
      graderProvider.overrideWithValue(grader),
    ],
    child: CaseTrainerApp(showCover: showCover),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls [f] to the middle of the viewport (clear of the bottom bar) and taps it.
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  final ctx = tester.element(f);
  await Scrollable.ensureVisible(ctx, alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Opens a case from the home list (cases further down are only built once scrolled into view).
Future<void> openCase(WidgetTester tester, ContentDb content, [String caseId = p50]) async {
  // The case card (the title can also appear on the "pick up where you left off" panel).
  final title = find.descendant(of: find.byType(Card), matching: find.text(content.caseById(caseId).title));
  await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(title);
  await tester.pumpAndSettle();
}

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
    grader: const OfflineGrader(),
    onProgress: () {},
  );
}

/// A stand-in examiner: returns [result] for real answers (or calls [onGrade]) and records what it was asked.
class FakeGrader implements Grader {
  FakeGrader({GradeResult? result, this.onGrade}) : result = result ?? passing();
  GradeResult result;
  final GradeResult Function(StepData step, String answer)? onGrade;
  final asked = <String>[];

  static GradeResult passing() => const GradeResult(
        status: GradeStatus.graded,
        score: 90,
        passed: true,
        points: [PointVerdict(id: 'a', label: 'Point A', weight: 100, coverage: Coverage.full)],
        summary: 'Clear and correct.',
      );

  @override
  bool get isLive => true;

  @override
  Future<GradeResult> grade(StepData step, String answer, resolver, {CaseInfo? caseInfo}) async {
    asked.add(answer);
    return onGrade?.call(step, answer) ?? result;
  }
}
