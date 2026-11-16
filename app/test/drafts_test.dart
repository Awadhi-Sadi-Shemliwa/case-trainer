// Owner request 2026-11-15: text typed into a step, then Back, was lost. Unsubmitted input is now a draft in
// progress.sqlite that survives the Back button, leaving the case and restarting the app.
import 'dart:io';

import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'helpers.dart';

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('next_button')));
  await tester.pumpAndSettle();
}

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  int indexOf(String type) => content.steps(p50).indexWhere((s) => s.type == type);

  group('ProgressDb drafts', () {
    test('upgrading a version-1 file keeps every attempt and adds drafts', () {
      final dir = Directory.systemTemp.createTempSync('ct_progress');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}progress.sqlite';
      // A database exactly as version 1 of the app left it.
      final v1 = sqlite3.open(path);
      v1.execute('''
        CREATE TABLE attempts(id INTEGER PRIMARY KEY AUTOINCREMENT, case_id TEXT NOT NULL, step_id TEXT NOT NULL,
          attempt_no INTEGER NOT NULL, answer_json TEXT NOT NULL, correct INTEGER, score REAL,
          hints_used INTEGER NOT NULL DEFAULT 0, started_at TEXT NOT NULL, submitted_at TEXT NOT NULL, duration_ms INTEGER NOT NULL);
        CREATE TABLE case_state(case_id TEXT PRIMARY KEY, step_idx INTEGER NOT NULL, max_idx INTEGER NOT NULL,
          completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL);
        CREATE TABLE reviews(case_id TEXT NOT NULL, step_id TEXT NOT NULL, due_at TEXT NOT NULL, interval_days INTEGER NOT NULL,
          PRIMARY KEY(case_id, step_id));
        CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO attempts(case_id, step_id, attempt_no, answer_json, started_at, submitted_at, duration_ms)
          VALUES('p50_yield_curve', 's05_predict_data', 1, '"my old answer"', 't', 't', 1);
        INSERT INTO case_state VALUES('p50_yield_curve', 4, 6, 0, 't');
        INSERT INTO settings VALUES('theme_mode', 'dark');
      ''');
      v1.userVersion = 1;
      v1.close();

      final db = ProgressDb.openFile(path);
      expect(db.attemptCount('p50_yield_curve', 's05_predict_data'), 1);
      expect(db.lastAttempt('p50_yield_curve', 's05_predict_data')!['answer_json'], '"my old answer"');
      expect(db.caseState('p50_yield_curve')!.maxIdx, 6);
      expect(db.setting('theme_mode'), 'dark');
      db.saveDraft('p50_yield_curve', 's05_predict_data', 'half-written');
      expect(db.draft('p50_yield_curve', 's05_predict_data'), 'half-written');
      db.close();

      final again = ProgressDb.openFile(path);
      expect(again.draft('p50_yield_curve', 's05_predict_data'), 'half-written', reason: 'drafts are on disk');
      again.close();
    });

    test('reset clears drafts with the rest of the case progress', () {
      final db = ProgressDb.inMemory();
      db.saveDraft('c', 's', ['a', 'b']);
      expect(db.draft('c', 's'), ['a', 'b']);
      db.resetProgress();
      expect(db.draft('c', 's'), isNull);
      db.close();
    });
  });

  group('typed input survives', () {
    const typed = 'Daily rows in percentage points, blanks on bond-market holidays.';

    testWidgets('Back then Next on a written answer', (tester) async {
      final progress = ProgressDb.inMemory();
      final idx = content.steps(p50).indexWhere((s) => s.isGraded);
      progress.saveCaseState(p50, idx);
      await pumpApp(tester, content, progress);
      await openCase(tester, content);

      await tester.enterText(find.byType(TextField).first, typed);
      await tester.pump();
      await _back(tester);
      expect(find.text(typed), findsNothing);
      await _next(tester);
      expect(find.text(typed), findsOneWidget);
      expect(progress.attemptCount(p50, content.steps(p50)[idx].id), 0, reason: 'a draft is not an attempt');
    });

    testWidgets('leaving the case, and restarting the app', (tester) async {
      final progress = ProgressDb.inMemory();
      final idx = content.steps(p50).indexWhere((s) => s.isGraded);
      progress.saveCaseState(p50, idx);
      await pumpApp(tester, content, progress);
      await openCase(tester, content);
      await tester.enterText(find.byType(TextField).first, typed);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('draft_status')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await openCase(tester, content);
      expect(find.text(typed), findsOneWidget);

      // A fresh widget tree over the same database is what a restarted app sees.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, content, progress);
      await openCase(tester, content);
      expect(find.text(typed), findsOneWidget);
      expect(find.text('Your unsent answer is back'), findsOneWidget);
    });

    testWidgets('submitting turns the draft into an attempt', (tester) async {
      final progress = ProgressDb.inMemory();
      final steps = content.steps(p50);
      final idx = steps.indexWhere((s) => s.isGraded);
      progress.saveCaseState(p50, idx);
      await pumpApp(tester, content, progress, grader: FakeGrader());
      await openCase(tester, content);
      await tester.enterText(find.byType(TextField).first, typed);
      await tapVisible(tester, find.text('Submit answer'));
      expect(progress.draft(p50, steps[idx].id), isNull);
      expect(progress.attemptCount(p50, steps[idx].id), 1);
    });

    testWidgets('numeric, code blanks and an unchecked choice', (tester) async {
      final progress = ProgressDb.inMemory();
      final steps = content.steps(p50);

      final numeric = indexOf('numeric');
      progress.saveCaseState(p50, numeric);
      await pumpApp(tester, content, progress);
      await openCase(tester, content);
      await tester.enterText(find.byType(TextField).first, '17');
      await tester.pump();
      await _back(tester);
      await _next(tester);
      expect(find.text('17'), findsOneWidget);

      final fill = indexOf('code_fill');
      await tester.pageBack();
      await tester.pumpAndSettle();
      progress.saveCaseState(p50, fill);
      await openCase(tester, content);
      await tester.enterText(find.byType(TextField).first, 'shift(-k)');
      await tester.pump();
      await _back(tester);
      await _next(tester);
      expect(find.text('shift(-k)'), findsOneWidget);

      final mcq = indexOf('mcq');
      await tester.pageBack();
      await tester.pumpAndSettle();
      progress.saveCaseState(p50, mcq);
      await openCase(tester, content);
      final wrong = steps[mcq].options.firstWhere((o) => !o.correct);
      await tapVisible(tester, find.text(wrong.text));
      await _next(tester);
      await _back(tester);
      expect(progress.draft(p50, steps[mcq].id), [wrong.id]);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });
  });
}
