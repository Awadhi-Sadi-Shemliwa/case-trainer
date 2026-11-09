// Spec Prompt 4 §4: "Every number rendered in the UI comes from content.sqlite results — add a widget
// test that fails if any hard-coded number appears in step text."
//
// Each P50 step is rendered from the REAL bundle. Text is collected from every RichText EXCEPT
// pipeline value chips ({expected.*}), code blocks (real code and {captured.*} outputs) and
// interactive charts (labels from the pipeline's chart JSON). Pipeline
// values sit inside paragraphs as widget spans, so they never appear in the paragraph's own text.
// Allowed literals (names such as T10Y2Y) are removed. Any digit left was typed by hand and fails.
// (Stripping display STRINGS instead would be vacuous: displays like "1" or "5" erase most digits.)
import 'package:case_trainer/charts/chart_view.dart';
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/ui/steps/step_view.dart';
import 'package:case_trainer/ui/widgets/code_view.dart';
import 'package:case_trainer/ui/widgets/prose.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  final digit = RegExp(r'\d');

  testWidgets('no hand-typed numbers in any rendered step of any case', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    var checked = 0;
    var totalSteps = 0;
    final offenders = <String>[];
    for (final caseInfo in content.cases()) {
      final strip = [...caseInfo.allowedLiterals]..sort((a, b) => b.length.compareTo(a.length));
      final steps = content.steps(caseInfo.id);
      totalSteps += steps.length;
      for (var i = 0; i < steps.length; i++) {
        final progress = ProgressDb.inMemory();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StepView(scopeFor(content, progress, caseInfo.id, i)))),
        ));
        await tester.pump();
        final excluded = {
          ...find.descendant(of: find.byKey(CodeView.codeKey), matching: find.byType(RichText)).evaluate().map((e) => e.widget),
          ...find.descendant(of: find.byType(ValueChip), matching: find.byType(RichText)).evaluate().map((e) => e.widget),
          // chart labels/legends come from the pipeline's chart JSON, not from authored text
          ...find.descendant(of: find.byKey(InteractiveChart.chartKey), matching: find.byType(RichText)).evaluate().map((e) => e.widget),
        };
        for (final el in find.byType(RichText).evaluate()) {
          if (excluded.contains(el.widget)) continue;
          checked++;
          var text = (el.widget as RichText).text.toPlainText();
          for (final s in strip) {
            if (s.isNotEmpty) text = text.replaceAll(s, ' ');
          }
          if (digit.hasMatch(text)) offenders.add('${caseInfo.id}/${steps[i].id}: "${text.trim()}"');
        }
        progress.close();
      }
    }
    // let chart animations finish so no timers are left pending
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(checked, greaterThan(totalSteps * 3), reason: 'the test must actually inspect text');
    expect(offenders, isEmpty, reason: 'Hand-typed numbers found:\n${offenders.join('\n')}');
  });
}
