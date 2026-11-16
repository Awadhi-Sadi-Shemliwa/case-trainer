/// The Claude examiner (owner decision 2026-11-16). Claude reads the step, the rubric, the pipeline's numbers and
/// the answer, then judges each rubric point and quotes every wrong sentence. This file turns that judgement into
/// the score with the rubric weights (score.dart) and never lets Claude pick the score or a number.
library;

import 'dart:convert';

import '../data/models.dart';
import '../engine/placeholders.dart';
import 'claude_client.dart';
import 'grader.dart';
import 'no_attempt.dart';
import 'score.dart';

const examinerSystem = '''
You are the examiner in Case Trainer, an app that teaches data-science thinking on real, already-solved business
cases (aviation, Formula 1, football, finance). A learner has written an explanation for one step of a case.

Grade it against the rubric you are given. Judge meaning, not wording: a point is covered if the learner says the
same thing in their own words. Be strict but fair, as a good university examiner would be.

Rules:
- Coverage per rubric point: "full" (the idea is stated clearly and correctly), "partial" (touched on, vague, or
  half right), "none" (missing or wrong).
- The numbers you are given come from the pipeline that solved the case. They are the truth. A learner number that
  contradicts them is an error. Never invent numbers or facts that are not in the material.
- errors: quote, word for word, every sentence (or clause) of the answer that is wrong, misleading or confused, say
  in plain words what is wrong, and give the correct version. These quotes are shown to the learner, so they must
  match the answer exactly. Do not list mere omissions here; omissions belong to "missing" on the rubric point.
- red_flags: list a red flag only if the answer actually asserts it (watch for negation: "this is not proof of
  causation" does not assert causation). Quote the words that raise it.
- no_attempt: true only if the answer makes no real attempt (for example "I don't know", or text unrelated to the
  question).
- Write for a learner who knows p-values and correlation but may not know other methods. If your feedback names a
  method (for example a Holm correction or difference-in-differences), explain what it does in a short clause.
- Do not reveal the model answer wholesale. "missing" says what is missing in a sentence; it may name the idea,
  but should not paste the model answer.
- Keep each text field short: one or two sentences.
''';

/// The JSON the examiner must return (structured outputs: every object closed, every field required).
const examinerSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['no_attempt', 'points', 'errors', 'red_flags', 'strengths', 'summary'],
  'properties': {
    'no_attempt': {'type': 'boolean'},
    'points': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['id', 'coverage', 'evidence_quote', 'missing'],
        'properties': {
          'id': {'type': 'string'},
          'coverage': {'type': 'string', 'enum': ['full', 'partial', 'none']},
          'evidence_quote': {'type': 'string'},
          'missing': {'type': 'string'},
        },
      },
    },
    'errors': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['quote', 'problem', 'correction'],
        'properties': {
          'quote': {'type': 'string'},
          'problem': {'type': 'string'},
          'correction': {'type': 'string'},
        },
      },
    },
    'red_flags': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['id', 'quote'],
        'properties': {
          'id': {'type': 'string'},
          'quote': {'type': 'string'},
        },
      },
    },
    'strengths': {'type': 'array', 'items': {'type': 'string'}},
    'summary': {'type': 'string'},
  },
};

typedef ChartLoader = Future<Map<String, dynamic>?> Function(String chartId);

class ClaudeGrader implements Grader {
  ClaudeGrader(this.client, {this.loadChart});

  final ClaudeClient client;
  final ChartLoader? loadChart;

  @override
  bool get isLive => client.hasKey;

  @override
  Future<GradeResult> grade(StepData step, String answer, Resolver resolver, {CaseInfo? caseInfo}) async {
    if (isNoAttempt(answer)) return const GradeResult(status: GradeStatus.noAttempt, score: 0);
    final rubric = step.rubric;
    if (rubric == null) {
      return const GradeResult(status: GradeStatus.unavailable, message: 'This step has no rubric.');
    }
    final user = await buildPrompt(step, answer, resolver, caseInfo: caseInfo);
    try {
      final reply = await client.json(system: examinerSystem, user: user, schema: examinerSchema);
      return interpret(step, answer, resolver, reply.json,
          model: reply.model, inputTokens: reply.inputTokens, outputTokens: reply.outputTokens);
    } on ClaudeError catch (e) {
      return GradeResult(status: GradeStatus.unavailable, message: explainClaudeError(e));
    }
  }

  /// The per-step part of the prompt. Placeholders are resolved, so Claude sees the pipeline's real values.
  Future<String> buildPrompt(StepData step, String answer, Resolver resolver, {CaseInfo? caseInfo}) async {
    String p(String? s) => s == null ? '' : resolver.plain(s);
    final rubric = step.rubric!;
    final b = StringBuffer();
    if (caseInfo != null) {
      b.writeln('<case>\nP${caseInfo.number}: ${caseInfo.title}\nDecision maker: ${caseInfo.decisionMaker}. '
          'Decision: ${resolver.plain(caseInfo.decision)}\n</case>\n');
    }
    b.writeln('<step type="${step.type}" title="${step.title}">');
    if (step.body != null) b.writeln(p(step.body));
    b.writeln('Question: ${p(step.prompt)}');
    if (step.flawedPlan != null) b.writeln('The plan the learner must challenge: ${p(step.flawedPlan)}');
    b.writeln('</step>\n');
    if (step.chart != null && loadChart != null) {
      final chart = await loadChart!(step.chart!);
      if (chart != null) b.writeln('<chart>\n${describeChart(chart)}\n</chart>\n');
    }
    if (step.modelAnswer != null) b.writeln('<model_answer>\n${p(step.modelAnswer)}\n</model_answer>\n');
    b.writeln('<rubric>');
    for (final raw in (rubric['points'] as List? ?? const [])) {
      final pt = raw as Map;
      b.writeln('- point id="${pt['id']}" label="${pt['label']}" weight=${pt['weight']}');
      final paras = [for (final x in (pt['paraphrases'] as List? ?? const [])) p(x as String)];
      if (paras.isNotEmpty) b.writeln('  acceptable ways to say it: ${paras.join(' | ')}');
      final num = pt['numeric'] as Map?;
      if (num != null) {
        final r = resolver.results[num['key']];
        if (r != null) b.writeln('  needs the pipeline number: ${r.display} (${r.description}); tolerance ${num['tolerance'] ?? 0}');
      }
      if (pt['why'] != null) b.writeln('  why it matters: ${pt['why']}');
    }
    final flags = rubric['red_flags'] as List? ?? const [];
    if (flags.isNotEmpty) {
      b.writeln('Red flags (only if asserted):');
      for (final raw in flags) {
        final f = raw as Map;
        final paras = [for (final x in (f['paraphrases'] as List? ?? const [])) p(x as String)];
        b.writeln('- flag id="${f['id']}"${f['critical'] == true ? ' critical' : ''}: ${paras.join(' | ')}');
      }
    }
    b.writeln('</rubric>\n');
    final nums = _numbersShown(step, resolver);
    if (nums.isNotEmpty) {
      b.writeln('<pipeline_numbers>');
      for (final r in nums) {
        b.writeln('- ${r.key} = ${r.display}: ${r.description}');
      }
      b.writeln('</pipeline_numbers>\n');
    }
    b.writeln('<learner_answer>\n$answer\n</learner_answer>');
    b.writeln('\nGrade the learner answer. Give one entry in "points" for every rubric point id, in rubric order.');
    return b.toString();
  }

  /// Every pipeline number the step, its model answer or its rubric refers to.
  List<ResultEntry> _numbersShown(StepData step, Resolver resolver) {
    final text = jsonEncode(step.json);
    final keys = <String>{for (final m in placeholderRe.allMatches(text)) if (m.group(1) == 'expected') m.group(2)!};
    for (final raw in (step.rubric?['points'] as List? ?? const [])) {
      final k = ((raw as Map)['numeric'] as Map?)?['key'];
      if (k is String) keys.add(k);
    }
    return [for (final k in keys) if (resolver.results[k] != null) resolver.results[k]!];
  }

  /// Turns Claude's judgement into a result: weights, number check and penalties are applied here.
  GradeResult interpret(StepData step, String answer, Resolver resolver, Map<String, dynamic> j,
      {String? model, int? inputTokens, int? outputTokens}) {
    if (j['no_attempt'] == true) {
      return GradeResult(status: GradeStatus.noAttempt, score: 0, model: model, inputTokens: inputTokens, outputTokens: outputTokens);
    }
    final rubric = step.rubric!;
    final judged = {
      for (final raw in (j['points'] as List? ?? const [])) (raw as Map)['id'] as String: raw,
    };
    var points = <PointVerdict>[
      for (final raw in (rubric['points'] as List? ?? const []))
        () {
          final pt = raw as Map;
          final v = judged[pt['id']];
          return PointVerdict(
            id: pt['id'] as String,
            label: pt['label'] as String,
            weight: (pt['weight'] as num).toDouble(),
            coverage: Coverage.parse(v?['coverage']),
            evidence: (v?['evidence_quote'] as String?) ?? '',
            missing: (v?['missing'] as String?) ?? (v == null ? 'Not covered.' : ''),
            hint: pt['hint'] == null ? null : resolver.plain(pt['hint'] as String),
            why: pt['why'] as String?,
          );
        }(),
    ];
    points = applyNumberAnchors(step, points, answer, resolver.results);
    final flagDefs = {
      for (final raw in (rubric['red_flags'] as List? ?? const [])) (raw as Map)['id'] as String: raw,
    };
    final flags = <FlagVerdict>[];
    for (final raw in (j['red_flags'] as List? ?? const [])) {
      final id = (raw as Map)['id'] as String?;
      final def = flagDefs[id];
      if (def == null || flags.any((f) => f.id == id)) continue; // unknown or duplicate ids are ignored
      flags.add(FlagVerdict(
        id: id!,
        critical: def['critical'] == true,
        penalty: (def['penalty'] as num?)?.toDouble() ?? 0,
        feedback: resolver.plain(def['feedback'] as String? ?? ''),
        quote: raw['quote'] as String? ?? '',
      ));
    }
    final score = scoreOf(points, flags);
    return GradeResult(
      status: GradeStatus.graded,
      score: score,
      passed: passes(score, flags),
      points: points,
      errors: [
        for (final e in (j['errors'] as List? ?? const []))
          if (((e as Map)['quote'] as String? ?? '').trim().isNotEmpty) PinpointedError.fromJson(e.cast<String, dynamic>())
      ],
      flags: flags,
      strengths: List<String>.from(j['strengths'] as List? ?? const []),
      summary: j['summary'] as String? ?? '',
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
}

/// A compact text description of a pipeline chart (title, axes, series, shaded periods, reference lines).
String describeChart(Map<String, dynamic> c) {
  final b = StringBuffer('${c['title']}');
  if (c['subtitle'] != null) b.write('. ${c['subtitle']}');
  b.writeln();
  String axis(Object? a) {
    if (a is! Map) return '?';
    return '${a['title']}${a['unit'] != null ? ' (${a['unit']})' : ''}';
  }

  b.writeln('Chart type: ${c['type']}. x axis: ${axis(c['x_axis'])}. y axis: ${axis(c['y_axis'])}.');
  for (final s in (c['series'] as List? ?? const [])) {
    final m = s as Map;
    final xs = (m['x'] as List?) ?? const [];
    final ys = (m['y'] as List?) ?? const [];
    // Short series are given in full; long ones as a sample, so the examiner can check described shapes.
    final n = xs.length;
    final idx = n <= 24 ? List.generate(n, (i) => i) : List.generate(24, (i) => (i * (n - 1) / 23).round());
    final pts = [for (final i in idx) if (i < ys.length) '${xs[i]}: ${ys[i]}'].join('; ');
    b.writeln('Series "${m['name']}" (${m['role'] ?? 'data'}, $n points): $pts');
  }
  for (final r in (c['shaded_regions'] as List? ?? const [])) {
    final m = r as Map;
    b.writeln('Shaded ${m['start']} to ${m['end']}: ${m['label']}');
  }
  for (final r in (c['reference_lines'] as List? ?? const [])) {
    final m = r as Map;
    b.writeln('Reference line ${m['axis']} = ${m['value']}: ${m['label']}');
  }
  if (c['source_note'] != null) b.writeln(c['source_note']);
  return b.toString().trim();
}
