// Finance Foundations (owner request 2026-11-15): the course, its quick checks, tier unlocking, word links in
// finance cases and the review ladder, all against the REAL bundle.
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/learn/course.dart';
import 'package:case_trainer/learn/quiz.dart';
import 'package:case_trainer/learn/term_linker.dart';
import 'package:case_trainer/ui/widgets/prose.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ContentDb content;
  late Course course;
  setUpAll(() {
    content = realContent();
    course = content.course();
  });
  tearDownAll(() => content.close());

  group('course', () {
    test('three tiers of a hundred words, ten lessons each, ranked 1..300', () {
      expect(course.tiers.map((t) => t.id), ['core', 'intermediate', 'quant']);
      expect(course.terms.length, 300);
      expect(course.lessons.length, 30);
      for (final t in course.tiers) {
        expect(course.termsOfTier(t.id).length, 100);
        expect(course.lessonsOf(t.id).length, 10);
      }
      expect([for (final t in course.terms) t.rank], List.generate(300, (i) => i + 1));
      expect(course.byId['equity']!.rank, lessThanOrEqualTo(10), reason: 'the owner did not know equity');
    });

    test('formula images named in the bundle are real assets', () {
      final withFormula = course.terms.where((t) => t.formula?.image != null).toList();
      expect(withFormula, isNotEmpty);
      for (final t in withFormula) {
        expect(t.formula!.image, 'formulas/${t.id}.png');
      }
    });
  });

  group('quick check', () {
    List<GlossaryTerm> words() => course.termsOf(course.lessons.first.id);

    test('one question per word, four distinct options, exactly one right', () {
      final q = buildQuiz(course, words(), seed: 'core_01_money|0');
      expect(q.length, 10);
      for (final x in q) {
        expect(x.options.length, 4);
        expect(x.options.map((o) => o.termId).toSet().length, 4);
        expect(x.options.map((o) => o.text).toSet().length, 4);
        expect(x.options.where(x.isCorrect).length, 1);
      }
      expect(q.map((x) => x.kind).toSet().length, 2, reason: 'both question kinds are used');
    });

    test('same seed gives the same quiz; a retry shuffles', () {
      String fp(List<QuizQuestion> q) => q.map((x) => '${x.kind.name}:${x.options.map((o) => o.termId).join(',')}').join('|');
      final a = fp(buildQuiz(course, words(), seed: 'core_01_money|0'));
      expect(fp(buildQuiz(course, words(), seed: 'core_01_money|0')), a);
      expect(fp(buildQuiz(course, words(), seed: 'core_01_money|1')), isNot(a));
    });
  });

  group('progress', () {
    test('a later tier opens only when every lesson before it is passed', () {
      final db = ProgressDb.inMemory();
      addTearDown(db.close);
      var p = CourseProgress(course, db);
      expect(p.tierUnlocked('core'), isTrue);
      expect(p.tierUnlocked('intermediate'), isFalse);
      final core = course.lessonsOf('core');
      for (final l in core.take(core.length - 1)) {
        db.recordLesson(l.id, score: 9, passed: true);
      }
      db.recordLesson(core.last.id, score: 7, passed: false);
      p = CourseProgress(course, db);
      expect(p.tierUnlocked('intermediate'), isFalse, reason: 'seven of ten is not a pass');
      db.recordLesson(core.last.id, score: 8, passed: true);
      p = CourseProgress(course, db);
      expect(p.tierUnlocked('intermediate'), isTrue);
      expect(p.tierUnlocked('quant'), isFalse);
      expect(p.nextLesson!.id, course.lessonsOf('intermediate').first.id);
    });

    test('review ladder: a day, then three, seven and twenty-one; a miss starts again', () {
      final db = ProgressDb.inMemory();
      addTearDown(db.close);
      final t0 = DateTime.utc(2026, 11, 15, 9);
      db.recordTermAnswer('equity', correct: true, now: t0);
      expect(db.termState('equity')!.known, isTrue);
      expect(db.termState('equity')!.dueAt, t0.add(const Duration(days: 1)));
      expect(db.dueTerms(t0), isEmpty);
      final t1 = t0.add(const Duration(days: 1));
      expect(db.dueTerms(t1), ['equity']);
      db.recordTermAnswer('equity', correct: true, now: t1);
      expect(db.termState('equity')!.dueAt, t1.add(const Duration(days: 3)));
      db.recordTermAnswer('equity', correct: false, now: t1);
      expect(db.termState('equity')!.dueAt, t1.add(const Duration(days: 1)));
      expect(db.termState('equity')!.known, isTrue, reason: 'a miss reschedules; it does not un-know the word');
      db.recordTermAnswer('asset', correct: false, now: t0);
      expect(db.termState('asset')!.known, isFalse);
      expect(db.dueTerms(t1.add(const Duration(days: 30))), ['equity']);
    });
  });

  group('word links', () {
    TermLinker linker() => TermLinker(course);

    test('finance words are found, longest name first, acronyms by exact case', () {
      expect([for (final p in linker().split('a portfolio manager at a UK asset manager').whereType<TermPiece>()) p.text],
          ['portfolio manager'], reason: 'the second alias of a linked word still blocks "asset" inside it');
      final pieces = linker().split('A recession hits earnings per share and GDP; the fed data was fed into the Fed model.');
      final linked = [for (final p in pieces.whereType<TermPiece>()) '${p.text}=${p.term.id}'];
      expect(linked, contains('recession=recession'));
      expect(linked, contains('earnings per share=eps'));
      expect(linked, contains('GDP=gdp'));
      expect(linked, contains('the Fed=federal_reserve'), reason: 'longest alias, exact case');
      expect(linked.where((l) => l.startsWith('fed=')), isEmpty, reason: '"fed" in ordinary prose is not the Fed');
      expect(pieces.map((p) => p.text).join(), 'A recession hits earnings per share and GDP; the fed data was fed into the Fed model.');
    });

    testWidgets('a P50 step underlines finance words and opens the word on tap', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final progress = ProgressDb.inMemory();
      addTearDown(progress.close);
      await pumpApp(tester, content, progress);
      await openCase(tester, content);
      final links = [for (final e in find.byType(RichText).evaluate()) ...termLinksIn(e.widget as RichText)];
      final texts = [for (final l in links) l.text.toLowerCase()];
      expect(texts, contains('recession'));
      expect(texts, isNot(contains('asset')), reason: '"asset" inside "asset manager" is not the word Asset');
      links.firstWhere((l) => l.text.toLowerCase() == 'recession').recognizer.onTap!();
      await tester.pumpAndSettle();
      expect(find.text('How it fools people'), findsOneWidget);
    });
  });

  testWidgets('a lesson: read, take the quick check, pass, words become known', (tester) async {
    final progress = ProgressDb.inMemory();
    addTearDown(progress.close);
    await pumpApp(tester, content, progress);
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 300 words known'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start_next_lesson')));
    await tester.pumpAndSettle();

    final lesson = course.lessons.first;
    final words = course.termsOf(lesson.id);
    for (var i = 0; i < words.length; i++) {
      await tester.tap(find.byKey(const ValueKey('lesson_next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('start_check')));
    await tester.pumpAndSettle();
    for (final w in words) {
      await tapVisible(tester, find.byKey(ValueKey('quiz_option_${w.id}')));
      await tapVisible(tester, find.byKey(const ValueKey('quiz_next')));
    }
    expect(find.text('10 of 10'), findsOneWidget);
    expect(find.text('Lesson passed'), findsOneWidget);
    expect(progress.lessonStates()[lesson.id]!.passed, isTrue);
    for (final w in words) {
      expect(progress.termState(w.id)!.known, isTrue, reason: w.id);
    }
  });
}
