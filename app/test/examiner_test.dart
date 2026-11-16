// The Claude examiner, the "I don't know" ladder, the finish rule, the case report and the sector slots
// (owner requests 2026-11-16). No test calls the real API: http is mocked.
import 'dart:convert';
import 'dart:io';

import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/models.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/engine/sector_slots.dart';
import 'package:case_trainer/engine/step_status.dart';
import 'package:case_trainer/grading/claude_client.dart';
import 'package:case_trainer/grading/claude_grader.dart';
import 'package:case_trainer/grading/grader.dart';
import 'package:case_trainer/grading/no_attempt.dart';
import 'package:case_trainer/grading/score.dart';
import 'package:case_trainer/report/case_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf/widgets.dart' as pw;

import 'helpers.dart';

const p34 = 'p34_home_adv';

/// An API reply carrying [json] as the structured-output text block.
http.Response apiReply(Map<String, dynamic> json) => http.Response(
      jsonEncode({
        'model': examinerModel,
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'thinking', 'thinking': ''},
          {'type': 'text', 'text': jsonEncode(json)},
        ],
        'usage': {'input_tokens': 1200, 'output_tokens': 300},
      }),
      200,
    );

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  StepData step(String caseId, String id) => content.steps(caseId).firstWhere((s) => s.id == id);

  group('"I don\'t know" is a request for hints', () {
    test('detected locally', () {
      for (final a in ["I don't know", 'idk', 'no idea', 'Not sure', '?', '...', 'Yh', 'dont know', '']) {
        expect(isNoAttempt(a), isTrue, reason: a);
      }
      for (final a in [
        'Testing four leagues at five percent makes a false positive likely.',
        "I'm not sure, but four tests at five percent give a good chance of one false positive by luck alone.",
      ]) {
        expect(isNoAttempt(a), isFalse, reason: a);
      }
    });
  });

  group('score: weights, numbers and penalties are applied in the app', () {
    test('Σ weight × coverage − penalties, clipped; critical flag blocks a pass', () {
      const pts = [
        PointVerdict(id: 'a', label: 'A', weight: 60, coverage: Coverage.full),
        PointVerdict(id: 'b', label: 'B', weight: 40, coverage: Coverage.partial),
      ];
      expect(scoreOf(pts, const []), 80);
      expect(passes(90, const []), isTrue);
      const critical = FlagVerdict(id: 'x', critical: true, penalty: 0, feedback: '');
      expect(passes(95, const [critical]), isFalse);
      expect(scoreOf(pts, const [FlagVerdict(id: 'y', critical: false, penalty: 200, feedback: '')]), 0);
    });

    test('a numeric point keeps full credit only with the pipeline number (percent aware)', () {
      final r = ResultEntry(key: 'k', value: 0.412, unit: 'share', description: '', display: '41.2%');
      expect(hasNumber('the rate fell to 41.2%', r, tolerance: 0.01), isTrue);
      expect(hasNumber('the rate fell to 0.41', r, tolerance: 0.01), isTrue);
      expect(hasNumber('the rate fell to 55%', r, tolerance: 0.01), isFalse);
      expect(hasNumber('the rate fell a lot', r, tolerance: 0.01), isFalse);
    });
  });

  group('ClaudeGrader', () {
    late StepData plan;
    late ClaudeGrader grader;
    Map<String, dynamic>? sent;
    late http.Response Function() reply;

    setUp(() {
      plan = step(p34, 's12_plan_challenge');
      reply = () => apiReply({
            'no_attempt': false,
            'points': [
              {'id': 'multiple', 'coverage': 'partial', 'evidence_quote': 'five percentage level', 'missing': 'Name the multiple-testing problem.'},
              {'id': 'pooled', 'coverage': 'none', 'evidence_quote': '', 'missing': 'Propose one pooled test.'},
              {'id': 'causal', 'coverage': 'full', 'evidence_quote': 'until a proof has come to light', 'missing': ''},
              {'id': 'cards', 'coverage': 'none', 'evidence_quote': '', 'missing': 'Use cards per foul.'},
            ],
            'errors': [
              {
                'quote': 'We test each at the 95 percent level instead',
                'problem': 'A five percent cut-off and a ninety-five percent confidence level are the same thing.',
                'correction': 'Keep the cut-off but correct for four tests, for example with a Holm correction.',
              },
            ],
            'red_flags': [
              {'id': 'not_a_flag', 'quote': 'x'},
            ],
            'strengths': ['You avoided calling the result proof.'],
            'summary': 'Half right: the causal caution is good, the testing fix is not.',
          });
      final mock = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.headers['x-api-key'], 'test-key');
        return reply();
      });
      grader = ClaudeGrader(ClaudeClient(apiKey: () => 'test-key', httpClient: mock));
    });

    test('sends the rubric with resolved pipeline numbers and a closed JSON schema', () async {
      final r = resolverFor(content, p34);
      await grader.grade(plan, 'The plan assumes referees are biased.', r, caseInfo: content.caseById(p34));
      expect(sent!['model'], examinerModel);
      expect((sent!['output_config'] as Map)['format']['type'], 'json_schema');
      final user = ((sent!['messages'] as List).first as Map)['content'] as String;
      expect(user, contains('point id="multiple"'));
      expect(user, contains(r.results['n_leagues_significant']!.display));
      expect(user, isNot(contains('{expected.')), reason: 'placeholders are resolved before Claude sees them');
      expect(user, contains('The plan assumes referees are biased.'));
    });

    test('turns the verdict into a score with the rubric weights; quotes survive; unknown flags are ignored', () async {
      final g = await grader.grade(plan, 'The plan assumes referees are biased...', resolverFor(content, p34));
      expect(g.status, GradeStatus.graded);
      // multiple 30 × ½ (and capped anyway: no number) + causal 25 = 40.
      expect(g.score, 40);
      expect(g.passed, isFalse);
      expect(g.points.firstWhere((p) => p.id == 'pooled').hint, isNotNull);
      expect(g.errors.single.quote, 'We test each at the 95 percent level instead');
      expect(g.flags, isEmpty);
      expect(GradeResult.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>).score, 40);
    });

    test('no credit, offline and no key are reported, never graded', () async {
      reply = () => http.Response(jsonEncode({'type': 'error', 'error': {'type': 'invalid_request_error', 'message': 'Your credit balance is too low to access the Anthropic API.'}}), 400);
      final g = await grader.grade(plan, 'A real answer with several words in it.', resolverFor(content, p34));
      expect(g.status, GradeStatus.unavailable);
      expect(g.countsAsAttempt, isFalse);
      expect(g.message, contains('credit'));

      final offline = ClaudeGrader(ClaudeClient(apiKey: () => 'k', httpClient: MockClient((_) async => throw const SocketException('no route'))));
      expect((await offline.grade(plan, 'A real answer with several words in it.', resolverFor(content, p34))).message, contains('internet'));

      final noKey = ClaudeGrader(ClaudeClient(apiKey: () => ''));
      expect(noKey.isLive, isFalse);
      expect((await noKey.grade(plan, 'A real answer with several words in it.', resolverFor(content, p34))).message, contains('key'));
    });

    test('"I don\'t know" never reaches the API', () async {
      sent = null;
      final g = await grader.grade(plan, "I don't know", resolverFor(content, p34));
      expect(g.status, GradeStatus.noAttempt);
      expect(sent, isNull);
    });
  });

  group('free-text step', () {
    Future<void> openStep(WidgetTester tester, ProgressDb progress, FakeGrader grader, String stepId) async {
      final idx = content.steps(p34).indexWhere((s) => s.id == stepId);
      progress.saveCaseState(p34, idx);
      await pumpApp(tester, content, progress, grader: grader);
      await openCase(tester, content, p34);
    }

    testWidgets('a graded answer shows the score, the points and the quoted wrong sentence at once', (tester) async {
      final progress = ProgressDb.inMemory();
      final grader = FakeGrader(
        result: const GradeResult(
          status: GradeStatus.graded,
          score: 40,
          points: [
            PointVerdict(id: 'multiple', label: 'Multiple testing', weight: 30, coverage: Coverage.partial, missing: 'Name it.'),
          ],
          errors: [PinpointedError(quote: 'We test each at the 95 percent level', problem: 'Same thing as five percent.', correction: 'Correct for four tests.')],
        ),
      );
      await openStep(tester, progress, grader, 's12_plan_challenge');
      await tester.enterText(find.byKey(const ValueKey('answer_field')), 'We test each at the 95 percent level instead.');
      await tapVisible(tester, find.text('Submit answer'));
      expect(find.byKey(const ValueKey('examiner_score')), findsOneWidget);
      expect(find.textContaining('You wrote: "We test each at the 95 percent level"'), findsOneWidget);
      expect(find.text('Same thing as five percent.'), findsOneWidget);
      expect(find.byKey(const ValueKey('model_answer')), findsNothing, reason: 'not on the first try');
      expect(progress.examinedCount(p34, 's12_plan_challenge'), 1);
      expect(stepStatus(progress, p34, step(p34, 's12_plan_challenge')), StepStatus.started);
    });

    testWidgets('"I don\'t know" three times: hint, all hints, then the model answer and the step counts as answered', (tester) async {
      final progress = ProgressDb.inMemory();
      final grader = FakeGrader(onGrade: (_, a) => const GradeResult(status: GradeStatus.noAttempt, score: 0));
      await openStep(tester, progress, grader, 's13_result');
      await tapVisible(tester, find.byKey(const ValueKey('dont_know')));
      expect(find.byKey(const ValueKey('examiner_no_attempt')), findsOneWidget);
      expect(find.byKey(const ValueKey('model_answer')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey('dont_know')));
      expect(find.textContaining('Before you rewrite'), findsOneWidget, reason: 'second try adds what to re-read');
      expect(find.text("I don't know: show me the answer"), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('dont_know')));
      expect(find.byKey(const ValueKey('model_answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('dont_know')), findsNothing);
      expect(stepStatus(progress, p34, step(p34, 's13_result')), StepStatus.done);
    });
  });

  group('finish rule', () {
    testWidgets('Finish lists the open questions instead of finishing', (tester) async {
      final progress = ProgressDb.inMemory();
      final steps = content.steps(p34);
      progress.saveCaseState(p34, steps.length - 1);
      await pumpApp(tester, content, progress);
      await openCase(tester, content, p34);
      await tester.tap(find.byKey(const ValueKey('next_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unfinished_sheet')), findsOneWidget);
      expect(progress.caseState(p34)!.completed, isFalse);
      final open = unfinishedSteps(progress, p34, steps);
      expect(open.where((s) => s.isInfo), isEmpty, reason: 'reading cards never block');
      expect(open.length, steps.where((s) => !s.isInfo).length);
    });

    test("the owner's real backup migrates to v3 with every attempt kept, and P34 is no longer finished", () {
      final src = File('../../case-trainer-backups/progress-2026-11-16-before-examiner.sqlite');
      if (!src.existsSync()) {
        markTestSkipped('owner backup not on this machine');
        return;
      }
      final tmp = Directory.systemTemp.createTempSync('ct_');
      final copy = src.copySync('${tmp.path}/p.sqlite');
      final before = ProgressDb.openFile(copy.path);
      expect(before.caseSummary(p34).attempts, greaterThan(0));
      expect(before.examinedCount(p34, 's09_chart_gd'), 0, reason: 'old answers were never graded');
      final open = unfinishedSteps(before, p34, content.steps(p34)).map((s) => s.id).toList();
      expect(open, containsAll(['s07_justify_period', 's13_result', 's16_memo', 's09_chart_gd', 's14_numeric']));
      expect(before.caseState(p34)!.completed, isTrue, reason: 'the owner pressed Finish with steps open');
      reopenUnfinishedCases(content, before);
      expect(before.caseState(p34)!.completed, isFalse);
      before.close();
      tmp.deleteSync(recursive: true);
    });
  });

  group('report and next problem', () {
    test('the PDF holds every step, the attempts and the examiner\'s quotes', () async {
      final progress = ProgressDb.inMemory();
      progress.recordExaminedAttempt(
        caseId: p34, stepId: 's12_plan_challenge', answer: 'My answer text', startedAt: DateTime.now(),
        feedback: const GradeResult(
          status: GradeStatus.graded, score: 40,
          errors: [PinpointedError(quote: 'quoted words', problem: 'wrong because', correction: 'better')],
        ).toJson(),
        status: 'graded', score: 40,
      );
      pw.Font font(String f) => pw.Font.ttf(File('assets/fonts/$f').readAsBytesSync().buffer.asByteData());
      final bytes = await buildCaseReport(
        info: content.caseById(p34),
        records: collectRecords(content, progress, p34),
        resolver: resolverFor(content, p34),
        sources: content.sources(),
        fonts: ReportFonts(regular: font('Archivo-Regular.ttf'), bold: font('Archivo-Bold.ttf'), mono: font('JetBrainsMono-Regular.ttf')),
        summary: const CaseSummary(headline: 'Good start', strengths: ['a'], gaps: ['b'], revise: ['c']),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      expect(reportFileName(content.caseById(p34), DateTime(2026, 11, 16, 9, 5)), startsWith('P34-'));
    });

    test('after P34 is finished the football slot shows P33, being prepared', () {
      final progress = ProgressDb.inMemory();
      final cat = content.catalog();
      expect(cat.length, 50);
      var slot = sectorSlot('football', content.cases(), cat, progress);
      expect(slot.active!.id, p34);
      progress.saveCaseState(p34, 0, completed: true);
      slot = sectorSlot('football', content.cases(), cat, progress);
      expect(slot.active, isNull);
      expect(slot.preparing!.number, 33);
      expect(slot.finished.single.id, p34);
    });
  });

  test('no Claude API key is in any file git tracks', () {
    final root = Directory('..');
    final ls = Process.runSync('git', ['ls-files'], workingDirectory: root.path);
    if (ls.exitCode != 0) {
      markTestSkipped('git not available');
      return;
    }
    final prefix = ['sk', 'ant', ''].join('-');
    final hits = <String>[];
    for (final f in (ls.stdout as String).split('\n').where((l) => l.trim().isNotEmpty)) {
      final file = File('${root.path}/$f');
      if (!file.existsSync() || file.lengthSync() > 5000000) continue;
      try {
        if (file.readAsStringSync().contains(prefix)) hits.add(f);
      } on FileSystemException {
        // binary file
      }
    }
    expect(hits, isEmpty);
    expect(File('secrets.json').existsSync() ? Process.runSync('git', ['check-ignore', 'app/secrets.json'], workingDirectory: root.path).exitCode : 0, 0,
        reason: 'secrets.json must be git-ignored');
  });
}
