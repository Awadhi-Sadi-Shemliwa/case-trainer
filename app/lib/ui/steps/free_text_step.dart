import 'dart:convert';

import 'package:flutter/material.dart';

import '../../grading/grader.dart';
import '../widgets/code_view.dart';
import '../widgets/prose.dart';
import '../../charts/chart_view.dart';
import 'step_common.dart';

/// Examiner steps: free_text, chart_explain, result_explain, memo, and the challenge-mode types
/// data_expectation, cleaning_justification, plan_challenge, decision_threshold.
class FreeTextStep extends StatefulWidget {
  const FreeTextStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<FreeTextStep> createState() => _FreeTextStepState();
}

class _FreeTextStepState extends State<FreeTextStep> {
  final _started = DateTime.now();
  late final TextEditingController _ctl;
  GradeResult? _grade;
  bool _submitted = false;
  bool _showModel = false;

  StepScope get s => widget.scope;

  @override
  void initState() {
    super.initState();
    final last = s.progress.lastAttempt(s.caseId, s.step.id);
    _ctl = TextEditingController(text: last == null ? '' : jsonDecode(last['answer_json'] as String) as String);
    _submitted = last != null;
    _ctl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  int get _words => _ctl.text.trim().isEmpty ? 0 : _ctl.text.trim().split(RegExp(r'\s+')).length;

  void _submit() {
    if (_ctl.text.trim().isEmpty) return;
    final g = s.grader.grade(s.step, _ctl.text);
    s.record(answer: _ctl.text, startedAt: _started, correct: null, score: g.score);
    setState(() {
      _grade = g;
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = s.step;
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      if (step.chart != null) InteractiveChart(step.chart!),
      if (step.flawedPlan != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Text('THE PLAN TO CHALLENGE', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.0, color: cs.onTertiaryContainer)),
            Prose(step.flawedPlan!, resolver: s.resolver, style: TextStyle(fontStyle: FontStyle.italic, color: cs.onTertiaryContainer)),
          ]),
        ),
      ScaffoldGuide(step.scaffold),
      TextField(
        controller: _ctl,
        minLines: 8,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: 'Explain in your own words…',
          helperText: _words > 0 ? '$_words words' : null,
        ),
      ),
      SubmitButton(label: _submitted ? 'Submit again' : 'Submit answer', onPressed: _ctl.text.trim().isEmpty ? null : _submit),
      if (_grade != null)
        FeedbackCard(kind: FeedbackKind.info, title: _grade!.message, resolver: s.resolver),
      if (_submitted && step.analysisPointer != null)
        FeedbackCard(kind: FeedbackKind.info, title: 'Where to look', message: step.analysisPointer, resolver: s.resolver),
      if (_submitted) ..._reveals(),
      // Until the examiner exists (Prompt 6) the model answer is available after you submit, for self-checking.
      if (_submitted && s.grader.isStub && step.modelAnswer != null) ...[
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => setState(() => _showModel = !_showModel),
          icon: Icon(_showModel ? Icons.visibility_off : Icons.visibility),
          label: Text(_showModel ? 'Hide model answer' : 'Compare with the model answer'),
        ),
        if (_showModel)
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                Text('MODEL ANSWER', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.0)),
                Prose(step.modelAnswer!, resolver: s.resolver),
                const Divider(),
                Text('WHAT THE EXAMINER WILL LOOK FOR', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.0)),
                for (final p in (step.rubric?['points'] as List? ?? const []))
                  Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                    const Text('•'),
                    Expanded(child: Text((p as Map)['label'] as String)),
                  ]),
              ]),
            ),
          ),
      ],
    ]);
  }

  /// Challenge-mode reveals: the real schema after you predicted it; the logged transform after you justified it.
  List<Widget> _reveals() {
    final step = s.step;
    final out = <Widget>[];
    if (step.dataset != null) {
      final d = s.content.dataset(s.caseId, step.dataset!);
      if (d != null) out.add(_DatasetReveal(d));
    }
    if (step.transform != null) {
      final t = s.content.transform(s.caseId, step.transform!);
      if (t != null) out.add(_TransformReveal(t));
    }
    return out;
  }
}

class _DatasetReveal extends StatelessWidget {
  const _DatasetReveal(this.d);
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final schema = d['schema'] as Map<String, dynamic>? ?? const {};
    final cols = List<String>.from(schema['columns'] as List? ?? const []);
    final dtypes = (schema['dtypes'] as Map?) ?? const {};
    final head = (schema['head'] as List? ?? const []).cast<Map>();
    final markers = (d['non_numeric_markers'] as Map?) ?? const {};
    final headText = [
      cols.join('  |  '),
      for (final r in head) cols.map((c) => '${r[c]}').join('  |  '),
    ].join('\n');
    final markerText = markers.isEmpty
        ? 'none'
        : markers.entries.map((e) => '${e.key.toString().isEmpty ? "(blank cell)" : '"${e.key}"'} × ${e.value}').join(', ');
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Text('THE REAL FILE: ${d['key']}', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.0)),
          Text('${d['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Units: ${d['units'] ?? '?'} · Frequency: ${d['frequency'] ?? '?'}'),
          Text('Rows: ${schema['rows']} · Columns: ${cols.map((c) => '$c (${dtypes[c]})').join(', ')}'),
          Text('Non-numeric markers: $markerText'),
          if (d['dating_note'] != null) Text('Note: ${d['dating_note']}'),
          CodeView(headText, label: 'First rows', highlight: false),
        ]),
      ),
    );
  }
}

class _TransformReveal extends StatelessWidget {
  const _TransformReveal(this.t);
  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Text('WHAT THE PIPELINE LOGGED: ${t['id']}', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.0)),
          Text('Rows ${t['rows_before']} → ${t['rows_after']} (dropped ${t['rows_dropped']})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${t['reason']}'),
          if ((t['details'] as Map?)?.isNotEmpty ?? false)
            CodeView(const JsonEncoder.withIndent('  ').convert(t['details']), label: 'Details', highlight: false),
        ]),
      ),
    );
  }
}
