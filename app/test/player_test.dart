import 'package:case_trainer/app.dart';
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> _pumpApp(WidgetTester tester, ContentDb content, ProgressDb progress) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      contentDbProvider.overrideWithValue(content),
      progressDbProvider.overrideWithValue(progress),
    ],
    child: const CaseTrainerApp(),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls [f] to the middle of the viewport (clear of the bottom bar) and taps it.
Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  final ctx = tester.element(f);
  await Scrollable.ensureVisible(ctx, alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  testWidgets('home lists the P50 case under Finance and empty domains say so', (tester) async {
    final progress = ProgressDb.inMemory();
    await _pumpApp(tester, content, progress);
    expect(find.text('FINANCE'), findsOneWidget);
    expect(find.text(content.caseById(p50).title), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.textContaining('No cases yet'), findsNWidgets(3));
  });

  testWidgets('play first steps, leave, reopen: resumes at the same step', (tester) async {
    final progress = ProgressDb.inMemory();
    final total = content.steps(p50).length;
    await _pumpApp(tester, content, progress);

    await tester.tap(find.text(content.caseById(p50).title));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of $total'), findsOneWidget);
    expect(find.text('BRIEF'), findsOneWidget);

    // answer the first MCQ correctly
    final first = content.steps(p50).first;
    final right = first.options.firstWhere((o) => o.correct);
    await _tapVisible(tester, find.text(right.text));
    await _tapVisible(tester, find.text('Check'));
    expect(progress.solved(p50, first.id), isTrue);

    await tester.tap(find.byKey(const ValueKey('next_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of $total'), findsOneWidget);

    // leave the case and come back
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text(content.caseById(p50).title));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of $total'), findsOneWidget);
    expect(progress.caseState(p50)!.stepIdx, 2);
  });

  testWidgets('free-text step saves the answer and reports not graded yet', (tester) async {
    final progress = ProgressDb.inMemory();
    final steps = content.steps(p50);
    final idx = steps.indexWhere((s) => s.isGraded);
    progress.saveCaseState(p50, idx);
    await _pumpApp(tester, content, progress);
    await tester.tap(find.text(content.caseById(p50).title));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Daily rows in percentage points with holiday blanks.');
    await tester.pump();
    await _tapVisible(tester, find.text('Submit answer'));
    expect(find.textContaining('Not graded yet'), findsOneWidget);
    expect(progress.attemptCount(p50, steps[idx].id), 1);
  });
}
