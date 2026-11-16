/// The finished-case report (owner request 2026-11-16): a PDF of every question, every attempt, the examiner's
/// verdicts and pinpointed errors, and the model answer where it was shown, so the work can be kept and shared.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/content_db.dart';
import '../data/models.dart';
import '../data/progress_db.dart';
import '../engine/placeholders.dart';
import '../engine/step_status.dart';
import '../grading/claude_client.dart';
import '../grading/grader.dart';

/// Fonts are passed in (loaded from the bundled Archivo/JetBrains Mono in the app, from disk in tests).
class ReportFonts {
  const ReportFonts({required this.regular, required this.bold, required this.mono});
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font mono;
}

/// The examiner's overall view of the case, written by Claude from the verdicts (optional page).
class CaseSummary {
  const CaseSummary({required this.headline, required this.strengths, required this.gaps, required this.revise});
  final String headline;
  final List<String> strengths;
  final List<String> gaps;
  final List<String> revise;

  Map<String, dynamic> toJson() => {'headline': headline, 'strengths': strengths, 'gaps': gaps, 'revise': revise};
  factory CaseSummary.fromJson(Map<String, dynamic> j) => CaseSummary(
        headline: j['headline'] as String? ?? '',
        strengths: List<String>.from(j['strengths'] as List? ?? const []),
        gaps: List<String>.from(j['gaps'] as List? ?? const []),
        revise: List<String>.from(j['revise'] as List? ?? const []),
      );
}

const _summarySchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['headline', 'strengths', 'gaps', 'revise'],
  'properties': {
    'headline': {'type': 'string'},
    'strengths': {'type': 'array', 'items': {'type': 'string'}},
    'gaps': {'type': 'array', 'items': {'type': 'string'}},
    'revise': {'type': 'array', 'items': {'type': 'string'}},
  },
};

/// Per-step facts the report and the summary are built from.
class StepRecord {
  StepRecord(this.step, this.status, this.examined, this.checkedAttempts);
  final StepData step;
  final StepStatus status;
  final List<ExaminedAttempt> examined;
  final List<Map<String, dynamic>> checkedAttempts;

  bool get passed => examined.any((a) => a.passed);
  double? get best => examined.where((a) => a.score != null).map((a) => a.score!).fold<double?>(null, (m, x) => m == null || x > m ? x : m);
  bool get solved => checkedAttempts.any((a) => a['correct'] == 1);
}

List<StepRecord> collectRecords(ContentDb content, ProgressDb progress, String caseId) {
  final all = progress.attemptsOf(caseId);
  return [
    for (final st in content.steps(caseId))
      StepRecord(
        st,
        stepStatus(progress, caseId, st),
        st.isGraded ? progress.examinedAttempts(caseId, st.id) : const [],
        st.isGraded ? const [] : [for (final a in all) if (a['step_id'] == st.id) a],
      ),
  ];
}

/// Asks the examiner for an overall summary of the case. Returns null when it cannot be reached.
Future<CaseSummary?> summariseCase(ClaudeClient client, CaseInfo info, List<StepRecord> records, Resolver r) async {
  if (!client.hasKey) return null;
  // Owner budget rule: send only what the summary needs (no reading steps, latest try only, short quotes).
  String cut(String s) => s.length <= 160 ? s : '${s.substring(0, 157)}...';
  final b = StringBuffer('Case P${info.number}: ${info.title}\n');
  for (final rec in records) {
    if (rec.step.isInfo) continue;
    final head = 'Step ${rec.step.index + 1} "${rec.step.title}"';
    if (rec.step.isGraded) {
      if (rec.examined.isEmpty) {
        b.writeln('$head: not answered');
        continue;
      }
      final last = rec.examined.last;
      final g = GradeResult.fromJson(last.feedback);
      b.writeln('$head: ${rec.examined.length} tries, best ${rec.best?.round() ?? 0}${rec.passed ? ', passed' : ''}'
          '${rec.examined.any((a) => a.status == 'noAttempt') ? ', asked for hints' : ''}');
      final missing = [for (final p in g.points) if (p.coverage != Coverage.full) p.label];
      if (missing.isNotEmpty) b.writeln('  missing: ${missing.join('; ')}');
      for (final e in g.errors.take(2)) {
        b.writeln('  error: "${cut(e.quote)}": ${cut(e.problem)}');
      }
    } else {
      b.writeln('$head: ${rec.checkedAttempts.length} tries, ${rec.solved ? 'solved' : 'not solved'}');
    }
  }
  try {
    final reply = await client.json(
      system: 'You are the examiner in Case Trainer, a data-science case app. Write a short end-of-case summary for '
          'the learner from the grading record you are given: a one-sentence headline, two to four strengths, the '
          'recurring gaps (concepts, not single slips), and two to four concrete things to revise. Plain English; '
          'the learner knows p-values and correlation. State only what the record shows: do not invent results, do not '
          'claim progress between tries unless their scores differ, and treat steps marked not answered as not reached.',
      model: summaryModel,
      user: b.toString(),
      schema: _summarySchema,
      effort: 'low',
      maxTokens: 2000,
    );
    return CaseSummary.fromJson(reply.json);
  } on ClaudeError {
    return null;
  }
}

/// Builds the PDF.
Future<Uint8List> buildCaseReport({
  required CaseInfo info,
  required List<StepRecord> records,
  required Resolver resolver,
  required List<SourceRef> sources,
  required ReportFonts fonts,
  CaseSummary? summary,
  DateTime? now,
}) async {
  final date = (now ?? DateTime.now()).toLocal();
  // Archivo has no italic cut in the bundle; the upright faces stand in so every character renders.
  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold, italic: fonts.regular, boldItalic: fonts.bold);
  final doc = pw.Document(title: 'P${info.number} ${info.title}', author: 'Case Trainer', theme: theme);
  final ink = PdfColor.fromHex('#1D2A44');
  final soft = PdfColor.fromHex('#5B6478');
  final good = PdfColor.fromHex('#2E7D4F');
  final bad = PdfColor.fromHex('#B3261E');
  final paper = PdfColor.fromHex('#F3F5F8');

  String plain(String s) => resolver.plain(s);
  pw.Widget h(String s, [double size = 13]) =>
      pw.Padding(padding: const pw.EdgeInsets.only(top: 8, bottom: 4), child: pw.Text(s, style: pw.TextStyle(font: fonts.bold, fontSize: size, color: ink)));
  pw.Widget p(String s, {PdfColor? color, double size = 10, pw.Font? font, bool italic = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(s, style: pw.TextStyle(fontSize: size, color: color ?? ink, font: font, fontStyle: italic ? pw.FontStyle.italic : null, lineSpacing: 1.5)),
      );
  pw.Widget bullet(String s, {PdfColor? color}) => pw.Bullet(text: s, style: pw.TextStyle(fontSize: 10, color: color ?? ink), bulletColor: color ?? ink);
  pw.Widget answerBox(String s) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.symmetric(vertical: 4),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: paper, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Text(s, style: pw.TextStyle(fontSize: 9.5, color: ink, lineSpacing: 1.5)),
      );

  final graded = records.where((r) => r.step.isGraded).toList();
  final passedN = graded.where((r) => r.passed).length;
  final bests = [for (final r in graded) if (r.best != null) r.best!];
  final mean = bests.isEmpty ? null : bests.reduce((a, b) => a + b) / bests.length;
  final checked = records.where((r) => !r.step.isGraded && !r.step.isInfo).toList();
  final solvedN = checked.where((r) => r.solved).length;

  final body = <pw.Widget>[
    pw.Text('Case Trainer · case report', style: pw.TextStyle(fontSize: 10, color: soft)),
    pw.SizedBox(height: 4),
    pw.Text('P${info.number}: ${info.title}', style: pw.TextStyle(font: fonts.bold, fontSize: 20, color: ink)),
    p('For ${info.decisionMaker}. Decision: ${plain(info.decision)}', color: soft),
    p('Finished ${date.year}-${_two(date.month)}-${_two(date.day)} ${_two(date.hour)}:${_two(date.minute)}', color: soft),
    pw.SizedBox(height: 8),
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: soft, width: 0.5), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        p('Written answers passed: $passedN of ${graded.length}${mean == null ? '' : ' (average best score ${mean.round()} / 100)'}'),
        p('Checked questions solved: $solvedN of ${checked.length} (the rest revealed after three tries)'),
        p('Pass mark for written answers: ${passMark.round()}, with no critical red flag. Grades by the Claude examiner ($graderModel); '
            'scores are computed in the app from the rubric weights.', color: soft, size: 9),
      ]),
    ),
  ];

  if (summary != null) {
    body.addAll([
      h("Examiner's summary", 15),
      p(summary.headline, size: 11),
      if (summary.strengths.isNotEmpty) h('Strengths', 11),
      for (final s in summary.strengths) bullet(s, color: good),
      if (summary.gaps.isNotEmpty) h('Recurring gaps', 11),
      for (final s in summary.gaps) bullet(s, color: bad),
      if (summary.revise.isNotEmpty) h('What to revise', 11),
      for (final s in summary.revise) bullet(s),
    ]);
  }

  for (final rec in records) {
    final st = rec.step;
    final statusText = switch (rec.status) {
      StepStatus.done => st.isInfo
          ? 'read'
          : st.isGraded
              ? (rec.passed ? 'passed' : 'model answer shown after three tries')
              : (rec.solved ? 'solved' : 'answer shown after three tries'),
      StepStatus.started => 'started, not finished',
      StepStatus.untouched => 'not answered',
    };
    body.add(pw.Divider(color: soft, thickness: 0.3));
    body.add(h('Step ${st.index + 1} · ${st.title}', 12));
    body.add(p('${phaseLabels[st.phase] ?? st.phase} · $statusText', color: rec.status == StepStatus.done ? soft : bad, size: 9));
    if (st.isInfo) continue;
    body.add(p(plain(st.prompt), font: fonts.bold, size: 10));

    if (!st.isGraded) {
      for (final a in rec.checkedAttempts) {
        body.add(p('Try ${a['attempt_no']}: ${_answerText(jsonDecode(a['answer_json'] as String), st)}  ·  '
            '${a['correct'] == 1 ? 'correct' : 'wrong'}', color: a['correct'] == 1 ? good : bad, size: 9.5));
      }
      continue;
    }

    for (final a in rec.examined) {
      final g = GradeResult.fromJson(a.feedback);
      body.add(h(
          'Try ${a.attemptNo}${a.status == 'noAttempt' ? ': asked for a hint' : ': ${a.score?.round()} / 100${a.passed ? ', passed' : ''}'}', 10.5));
      body.add(answerBox(a.answer));
      if (g.graded) {
        if (g.summary.isNotEmpty) body.add(p(g.summary, italic: true, color: soft, size: 9.5));
        for (final pt in g.points) {
          final mark = switch (pt.coverage) { Coverage.full => 'covered', Coverage.partial => 'partly', Coverage.none => 'missing' };
          body.add(p('${pt.label} (${pt.earned.round()} of ${pt.weight.round()}, $mark)${pt.coverage == Coverage.full || pt.missing.isEmpty ? '' : ': ${pt.missing}'}',
              color: pt.coverage == Coverage.full ? good : (pt.coverage == Coverage.none ? bad : ink), size: 9.5));
        }
        for (final e in g.errors) {
          body.add(p('You wrote: "${e.quote}"', italic: true, size: 9.5, color: soft));
          body.add(p('Wrong: ${e.problem}', color: bad, size: 9.5));
          if (e.correction.isNotEmpty) body.add(p('Better: ${e.correction}', color: good, size: 9.5));
        }
        for (final f in g.flags) {
          body.add(p('Red flag${f.critical ? ' (critical)' : ''}: ${f.feedback}${f.quote.isEmpty ? '' : ' ("${f.quote}")'}', color: bad, size: 9.5));
        }
      }
    }
    if (rec.examined.isEmpty && rec.status != StepStatus.untouched) {
      body.add(p('Answered before the examiner existed and not graded.', color: soft, size: 9.5));
    }
    if (rec.status == StepStatus.done && st.modelAnswer != null) {
      body.add(h('Model answer', 10.5));
      body.add(p(plain(st.modelAnswer!), size: 9.5));
    }
  }

  final shown = [for (final s in sources) if (s.verified && info.sources.contains(s.key)) s];
  if (shown.isNotEmpty) {
    body.add(pw.Divider(color: soft, thickness: 0.3));
    body.add(h('Sources (verified)', 12));
    for (final s in shown) {
      body.add(p('${s.authorNames} (${s.year}). ${s.title}. ${s.url}', size: 9));
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 44),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('P${info.number} · page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: soft)),
    ),
    build: (_) => body,
  ));
  return doc.save();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// A checked step's stored answer as readable text (option texts for choices).
String _answerText(Object? a, StepData st) {
  final opts = {for (final o in st.options) o.id: o.text};
  if (a is List) return a.map((x) => opts[x] ?? '$x').join('; ');
  return '$a';
}

/// The file name used in Downloads.
String reportFileName(CaseInfo info, DateTime when) {
  final slug = info.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return 'P${info.number}-$slug-${when.year}${_two(when.month)}${_two(when.day)}-${_two(when.hour)}${_two(when.minute)}.pdf';
}
