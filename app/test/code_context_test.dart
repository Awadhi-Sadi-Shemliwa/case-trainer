// Owner request 2026-11-15: steps that talk about what the pipeline did show that code
// (e.g. P34 "The pipeline labels matches as fans, ghost…" shows assign_period).
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/ui/steps/step_view.dart';
import 'package:case_trainer/ui/widgets/code_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  Future<void> pumpStep(WidgetTester tester, String caseId, String stepId) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final idx = content.steps(caseId).indexWhere((s) => s.id == stepId);
    expect(idx, isNonNegative, reason: '$caseId/$stepId exists');
    final progress = ProgressDb.inMemory();
    addTearDown(progress.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: StepView(scopeFor(content, progress, caseId, idx)))),
    ));
    await tester.pump();
  }

  // Code is rendered with SelectableText.rich (copyable), so read its span rather than a RichText.
  bool codeShows(WidgetTester tester, String fragment) => find
      .descendant(of: find.byKey(CodeContext.sectionKey), matching: find.byType(SelectableText))
      .evaluate()
      .any((e) => ((e.widget as SelectableText).textSpan?.toPlainText() ?? '').contains(fragment));

  testWidgets('P34: the ghost-game definition shows the code that labels matches', (tester) async {
    await pumpStep(tester, 'p34_home_adv', 's07_justify_period');
    expect(find.text('The code behind this step'), findsOneWidget);
    expect(find.text('assign_period in clean.py'), findsOneWidget);
    expect(codeShows(tester, 'df["period"] = "fans"'), isTrue);
  });

  testWidgets('every cleaning justification in every case shows its code', (tester) async {
    for (final c in content.cases()) {
      for (final s in content.steps(c.id).where((s) => s.type == 'cleaning_justification')) {
        await pumpStep(tester, c.id, s.id);
        expect(find.byKey(CodeContext.sectionKey), findsOneWidget, reason: '${c.id}/${s.id}');
        for (final r in s.contextSnippets) {
          expect(find.text('${r.name} in ${r.file}'), findsOneWidget, reason: '${c.id}/${s.id} ${r.name}');
        }
      }
    }
  });

  testWidgets('P50 blank days: load_daily and to_monthly, also in the sheet next to the answer box', (tester) async {
    await pumpStep(tester, p50, 's08_clean_blanks');
    expect(find.text('load_daily in clean.py'), findsOneWidget);
    expect(find.text('to_monthly in clean.py'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('show_code')));
    await tester.tap(find.byKey(const ValueKey('show_code')));
    await tester.pumpAndSettle();
    expect(find.text('to_monthly in clean.py'), findsNWidgets(2), reason: 'inline and in the sheet');
  });

  testWidgets('code never appears before the fill-the-blank step that asks for it', (tester) async {
    for (final c in content.cases()) {
      final steps = content.steps(c.id);
      for (var i = 0; i < steps.length; i++) {
        for (final r in steps[i].contextSnippets) {
          final later = steps.skip(i).where((s) =>
              (s.type == 'code_fill' || s.type == 'code_fix') && s.snippet?.file == r.file && s.snippet?.name == r.name);
          expect(later, isEmpty, reason: '${c.id}/${steps[i].id} would reveal ${r.name}');
        }
      }
    }
  });
}
