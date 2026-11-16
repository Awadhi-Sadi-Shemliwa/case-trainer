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
    test('Core holds 100 finance words then 40 measures and methods; the other tiers 100 each; ranked 1..340', () {
      expect(course.tiers.map((t) => t.id), ['core', 'intermediate', 'quant']);
      expect(course.terms.length, 340);
      expect(course.lessons.length, 34);
      expect([for (final t in course.tiers) course.termsOfTier(t.id).length], [140, 100, 100]);
      expect([for (final t in course.tiers) course.lessonsOf(t.id).length], [14, 10, 10]);
      expect([for (final l in course.lessonsOf('core')) l.isMeasures], [...List.filled(10, false), true, true, true, true]);
      expect(course.lessons.where((l) => l.isMeasures).every((l) => l.tier == 'core'), isTrue);
      expect([for (final t in course.terms) t.rank], List.generate(340, (i) => i + 1));
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

  group('measures (owner request 2026-11-16)', () {
    test('every method the owner had not met has a card, linked in every case (Holm, DiD, fixed effects...)', () {
      final linker = TermLinker(course, where: course.isMeasure);
      for (final (text, id) in [
        ('Leagues significant after Holm correction', 'holm_correction'),
        ('a difference-in-differences on cards per foul', 'difference_in_differences'),
        ('race fixed effects absorb the track', 'fixed_effects'),
        ('stints ending in a pit stop are censored', 'censoring'),
      ]) {
        final ids = [for (final p in linker.split(text)) if (p is TermPiece) p.term.id];
        expect(ids, contains(id), reason: text);
      }
    });

    test('the P50 evaluation words and the measures the owner named sit in Core', () {
      for (final id in ['base_rate', 'hit_false_alarm', 'roc_auc', 'brier_score', 'calibration', 'decision_threshold',
          'pca', 'ks_statistic', 'eda', 'r_squared', 'gini_accuracy_ratio', 'population_stability_index']) {
        final t = course.byId[id]!;
        expect(t.tier, 'core', reason: id);
        expect(course.isMeasure(t), isTrue, reason: id);
        expect(t.rank, inInclusiveRange(101, 140), reason: id);
        expect(t.usedFor, isNotNull, reason: id);
        expect(t.inFinance, isNotNull, reason: id);
      }
    });

    test('the AUC reading arrives with its numbers, bands and finance name filled in by the pipeline', () {
      final r = course.byId['roc_auc']!.reading!;
      expect(r.question, 'What does an AUC of 0.78 mean?');
      expect(r.point, (at: 0.78, text: '0.78'));
      expect((r.lo, r.hi), (0.5, 1.0));
      expect(r.pointBand!.label, 'acceptable');
      expect(r.bandsSource, 'casrai_auc_bands');
      expect(r.misreadings, hasLength(3));
      expect(r.meansPlain, isNot(contains('[[')));
      expect(course.byId['roc_auc']!.inFinance, contains('[[0.56]]'), reason: 'Gini = 2 x AUC - 1, computed');
    });

    test('a read-the-number question has the right reading and three misreadings, and is deterministic', () {
      final auc = course.byId['roc_auc']!;
      final words = course.termsOf(auc.lesson);
      QuizQuestion? q;
      var seed = '';
      for (var attempt = 0; q == null; attempt++) {
        seed = '${auc.lesson}|$attempt';
        q = buildQuiz(course, words, seed: seed)
            .where((x) => x.term.id == 'roc_auc' && x.kind == QuestionKind.readTheNumber)
            .firstOrNull;
      }
      expect(q.prompt, auc.reading!.question);
      expect(q.options.map((o) => o.text), unorderedEquals([auc.reading!.meansPlain, ...auc.reading!.misreadings]));
      expect(q.options.where(q.isCorrect).single.text, auc.reading!.meansPlain);
      String fp(List<QuizQuestion> l) => l.map((x) => '${x.kind.name}:${x.options.map((o) => o.termId).join(',')}').join('|');
      expect(fp(buildQuiz(course, words, seed: seed)), fp(buildQuiz(course, words, seed: seed)));
    });

    test('distractors for a measure are other measures, never finance words', () {
      for (final l in course.lessons.where((l) => l.isMeasures)) {
        for (var attempt = 0; attempt < 4; attempt++) {
          for (final q in buildQuiz(course, course.termsOf(l.id), seed: '${l.id}|$attempt')) {
            if (q.kind == QuestionKind.readTheNumber) continue;
            for (final o in q.options) {
              expect(course.isMeasure(course.byId[o.termId]!), isTrue, reason: '${q.term.id}: ${o.termId}');
            }
          }
        }
      }
    });

    test('the measures linker finds measures only; the full linker finds both', () {
      const s = 'The confidence interval for the return on equity was wide, and the median shows it.';
      List<String> ids(TermLinker l) => [for (final p in l.split(s).whereType<TermPiece>()) p.term.id];
      expect(ids(TermLinker(course, where: course.isMeasure)), ['confidence_interval', 'mean_median']);
      expect(ids(TermLinker(course)), containsAll(['confidence_interval', 'return', 'equity', 'mean_median']));
    });

    testWidgets('an F1 step links its measures and no finance word', (tester) async {
      final progress = ProgressDb.inMemory();
      addTearDown(progress.close);
      const f1 = 'p13_tyre_deg';
      progress.saveCaseState(f1, content.steps(f1).indexWhere((s) => s.id == 's11_read_fe'));
      await pumpApp(tester, content, progress);
      await tapVisible(tester, find.byKey(const ValueKey('resume_case')));
      final links = [for (final e in find.byType(RichText).evaluate()) ...termLinksIn(e.widget as RichText)];
      expect([for (final l in links) l.text.toLowerCase()], containsAll(['standard errors', 'least squares']));
      final measureNames = {
        for (final t in course.terms)
          if (course.isMeasure(t))
            for (final n in t.names) n.toLowerCase()
      };
      for (final l in links) {
        expect(measureNames, contains(l.text.toLowerCase()), reason: '"${l.text}" is not a measure');
      }
      links.firstWhere((l) => l.text.toLowerCase() == 'standard errors').recognizer.onTap!();
      await tester.pumpAndSettle();
      expect(find.text('In finance'), findsOneWidget);
    });

    testWidgets('Learn lists the measures under their own heading inside Core', (tester) async {
      final progress = ProgressDb.inMemory();
      addTearDown(progress.close);
      await pumpApp(tester, content, progress);
      await tester.tap(find.text('Learn'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('measures_heading_core')), 400,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Measures every case uses'), findsOneWidget);
      expect(find.byKey(const ValueKey('lesson_core_11_forecast_scores')), findsOneWidget);
    });

    testWidgets('the AUC card: the value on its scale, what it does not mean, and the finance name', (tester) async {
      final semantics = tester.ensureSemantics();
      final progress = ProgressDb.inMemory();
      addTearDown(progress.close);
      await pumpApp(tester, content, progress);
      await tester.tap(find.text('Learn'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open_glossary')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('glossary_search')), 'gini');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('glossary_gini_accuracy_ratio')), findsOneWidget);
      expect(find.byKey(const ValueKey('glossary_roc_auc')), findsOneWidget, reason: 'its finance note names the Gini');
      await tester.enterText(find.byKey(const ValueKey('glossary_search')), 'AUC');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary_roc_auc')));
      await tester.pumpAndSettle();

      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('reading_roc_auc')), 300, scrollable: scroll);
      expect(find.text('What does an AUC of 0.78 mean?'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'This value: 0\.78, in the band acceptable\..*coin toss')), findsOneWidget);
      await tester.scrollUntilVisible(find.text('It does not mean'), 300, scrollable: scroll);
      expect(find.text('The model classifies 78% of months correctly.'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('in_finance')), 300, scrollable: scroll);
      expect(find.text('In finance'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('ROC Curves and AUC'), 300, scrollable: scroll);
      expect(find.textContaining('ROC Curves and AUC'), findsOneWidget, reason: 'the bands source is listed');
      semantics.dispose();
    });
  });

  testWidgets('a lesson: read, take the quick check, pass, words become known', (tester) async {
    final progress = ProgressDb.inMemory();
    addTearDown(progress.close);
    await pumpApp(tester, content, progress);
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    expect(find.text('0 of ${course.terms.length} words known'), findsOneWidget);
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
