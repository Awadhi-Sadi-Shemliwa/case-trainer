// Quality floor (plan, 2026-11-15): the main screens lay out at 130% system text size without overflow.
// Any RenderFlex overflow is reported by the test framework as an error, which fails the test.
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  Future<ProgressDb> start(WidgetTester tester, {bool cover = false}) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final progress = ProgressDb.inMemory()..saveCaseState(p50, 3);
    addTearDown(progress.close);
    await pumpApp(tester, content, progress, showCover: cover);
    await tester.pump(const Duration(seconds: 2));
    return progress;
  }

  testWidgets('cover at 130% text', (tester) async {
    await start(tester, cover: true);
    expect(find.byKey(const ValueKey('cover_continue')), findsOneWidget);
  });

  testWidgets('cases, learn, progress and settings tabs at 130% text', (tester) async {
    await start(tester);
    for (final tab in ['Learn', 'Progress', 'Settings', 'Cases']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('measures cards with reading scales at 130% text', (tester) async {
    await start(tester);
    await tester.tap(find.text('Learn').last);
    await tester.pumpAndSettle();
    for (final (query, id) in [('AUC', 'roc_auc'), ('confidence interval', 'confidence_interval'), ('PSI', 'population_stability_index')]) {
      await tester.tap(find.byKey(const ValueKey('open_glossary')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('glossary_search')), query);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('glossary_$id')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(ValueKey('reading_$id')), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('It does not mean'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a case step and a lesson at 130% text', (tester) async {
    await start(tester);
    await tapVisible(tester, find.byKey(const ValueKey('resume_case')));
    expect(find.byKey(const ValueKey('next_button')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('start_next_lesson')));
    expect(find.byKey(const ValueKey('lesson_next')), findsOneWidget);
  });
}
