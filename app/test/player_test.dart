import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  testWidgets('home lists the P50 case under Finance and empty domains say so', (tester) async {
    final progress = ProgressDb.inMemory();
    await pumpApp(tester, content, progress);
    final empty = {'aviation', 'f1', 'football', 'finance'}.difference({for (final c in content.cases()) c.domain});
    if (empty.isNotEmpty) {
      final note = find.textContaining('No cases yet');
      await tester.scrollUntilVisible(note, 300, scrollable: find.byType(Scrollable).first);
      expect(note, findsWidgets);
    }
    await tester.scrollUntilVisible(find.text(content.caseById(p50).title), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text(content.caseById(p50).title), findsOneWidget);
  });

  testWidgets('play first steps, leave, reopen: resumes at the same step', (tester) async {
    final progress = ProgressDb.inMemory();
    final total = content.steps(p50).length;
    await pumpApp(tester, content, progress);

    await openCase(tester, content);
    expect(find.text('Step 1 of $total'), findsOneWidget);
    expect(find.text('Brief'), findsOneWidget);

    // answer the first MCQ correctly
    final first = content.steps(p50).first;
    final right = first.options.firstWhere((o) => o.correct);
    await tapVisible(tester, find.text(right.text));
    await tapVisible(tester, find.text('Check'));
    expect(progress.solved(p50, first.id), isTrue);

    await tester.tap(find.byKey(const ValueKey('next_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of $total'), findsOneWidget);

    // leave the case and come back
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('resume_case')), -300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('resume_case')), findsOneWidget, reason: 'home offers to pick up where you left off');
    await openCase(tester, content);
    expect(find.text('Step 3 of $total'), findsOneWidget);
    expect(progress.caseState(p50)!.stepIdx, 2);
  });

  testWidgets('free-text step saves the answer and reports not graded yet', (tester) async {
    final progress = ProgressDb.inMemory();
    final steps = content.steps(p50);
    final idx = steps.indexWhere((s) => s.isGraded);
    progress.saveCaseState(p50, idx);
    await pumpApp(tester, content, progress);
    await openCase(tester, content);

    await tester.enterText(find.byType(TextField).first, 'Daily rows in percentage points with holiday blanks.');
    await tester.pump();
    await tapVisible(tester, find.text('Submit answer'));
    expect(find.textContaining('Not graded yet'), findsOneWidget);
    expect(progress.attemptCount(p50, steps[idx].id), 1);
  });
}
