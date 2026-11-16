// LIVE: calls the real Claude API with the key in app/secrets.json (git-ignored). Skipped unless LIVE_CLAUDE=1, so the
// normal suite never spends credit. Run: LIVE_CLAUDE=1 flutter test test/live_examiner_test.dart
// Grades the owner's real P34 step-9 answer twice (the second should read the cached step material), then writes a
// full report PDF with a Haiku summary to LIVE_OUT (default: the system temp folder).
import 'dart:convert';
import 'dart:io';

import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/grading/claude_client.dart';
import 'package:case_trainer/grading/claude_grader.dart';
import 'package:case_trainer/grading/grader.dart';
import 'package:case_trainer/report/case_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'helpers.dart';

const ownerAnswer = 'The graph shows the goals per match by middle half of the season. The x axis is the middle half of the '
    'season, the y axis is the goals per match. The period is from 2017 to 2021. There is an average of goals scored per '
    'match between 0.3 and 0.4. The shape of the pattern is a zigzag rise and fall. Anomalies is in the 2019/2020 season '
    'there was a huge drop in the goals per match. It cant show the actual reason to why there was a drop of goals per '
    'match middle of half season';

void main() {
  final live = Platform.environment['LIVE_CLAUDE'] == '1' && File('secrets.json').existsSync();
  test('live examiner on the owner\'s real answer, with caching and a report', () async {
    final key = (jsonDecode(File('secrets.json').readAsStringSync()) as Map)['ANTHROPIC_API_KEY'] as String;
    final content = realContent();
    final client = ClaudeClient(apiKey: () => key);
    final grader = ClaudeGrader(client, loadChart: (id) async =>
        jsonDecode(File('assets/content/charts/$id.json').readAsStringSync()) as Map<String, dynamic>);
    final step = content.steps('p34_home_adv').firstWhere((s) => s.id == 's09_chart_gd');
    final r = resolverFor(content, 'p34_home_adv');
    final progress = ProgressDb.inMemory();

    for (var i = 1; i <= 2; i++) {
      final g = await grader.grade(step, ownerAnswer, r, caseInfo: content.caseById('p34_home_adv'));
      // ignore: avoid_print
      print('--- try $i: ${g.status.name} score=${g.score} passed=${g.passed} usage=${jsonEncode(g.usage)}\n'
          '${g.summary}\n${g.points.map((p) => '  ${p.coverage.name.padRight(7)} ${p.label}: ${p.missing}').join('\n')}\n'
          '${g.errors.map((e) => '  WRONG "${e.quote}"\n     -> ${e.problem}\n     => ${e.correction}').join('\n')}\n'
          '${g.flags.map((f) => '  FLAG ${f.id}: ${f.quote}').join('\n')}');
      expect(g.status, GradeStatus.graded, reason: g.message);
      expect(g.points.length, (step.rubric!['points'] as List).length);
      progress.recordExaminedAttempt(caseId: 'p34_home_adv', stepId: step.id, answer: ownerAnswer, startedAt: DateTime.now(),
          feedback: g.toJson(), status: g.status.name, score: g.score, passed: g.passed);
      if (i == 2) expect((g.usage!['cache_read_input_tokens'] as num) > 0, isTrue, reason: 'second try reads the cache');
    }

    final info = content.caseById('p34_home_adv');
    final records = collectRecords(content, progress, info.id);
    final summary = await summariseCase(client, info, records, r);
    // ignore: avoid_print
    print('--- summary: ${jsonEncode(summary?.toJson())}');
    expect(summary, isNotNull);
    pw.Font font(String f) => pw.Font.ttf(File('assets/fonts/$f').readAsBytesSync().buffer.asByteData());
    final bytes = await buildCaseReport(
      info: info, records: records, resolver: r, sources: content.sources(), summary: summary,
      fonts: ReportFonts(regular: font('Archivo-Regular.ttf'), bold: font('Archivo-Bold.ttf'), mono: font('JetBrainsMono-Regular.ttf')),
    );
    final out = File('${Platform.environment['LIVE_OUT'] ?? Directory.systemTemp.path}/live_p34_report.pdf')..writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('--- report: ${out.path} (${bytes.length} bytes); usage so far: ${progress.examinerUsage()}');
  }, skip: live ? false : 'set LIVE_CLAUDE=1 (and have app/secrets.json) to call the real API', timeout: const Timeout(Duration(minutes: 5)));
}
