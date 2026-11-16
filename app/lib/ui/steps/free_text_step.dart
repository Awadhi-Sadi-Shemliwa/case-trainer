import 'dart:convert';

import 'package:flutter/material.dart';

import '../../grading/grader.dart';
import '../widgets/code_context.dart';
import '../widgets/code_view.dart';
import '../widgets/prose.dart';
import '../../charts/chart_view.dart';
import '../theme/tokens.dart';
import '../widgets/highlight.dart';
import 'draft_saver.dart';
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
  late final DraftSaver _draft;
  late String _seen;
  bool _restored = false;
  GradeResult? _grade;
  bool _submitted = false;
  bool _showModel = false;

  StepScope get s => widget.scope;

  @override
  void initState() {
    super.initState();
    final last = s.progress.lastAttempt(s.caseId, s.step.id);
    final lastText = last == null ? '' : jsonDecode(last['answer_json'] as String) as String;
    // Unsent text wins over the last submitted answer: it is newer.
    final kept = s.progress.draft(s.caseId, s.step.id);
    _restored = kept is String && kept != lastText;
    _seen = kept is String ? kept : lastText;
    _ctl = TextEditingController(text: _seen);
    _submitted = last != null;
    _draft = DraftSaver(() => s.progress.saveDraft(s.caseId, s.step.id, _ctl.text));
    _ctl.addListener(_onChanged);
  }

  void _onChanged() {
    if (_ctl.text != _seen) {
      _seen = _ctl.text;
      _draft.changed();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _draft.dispose(); // writes the latest text, so it runs before the controller goes
    _ctl.dispose();
    super.dispose();
  }

  int get _words => _ctl.text.trim().isEmpty ? 0 : _ctl.text.trim().split(RegExp(r'\s+')).length;

  void _submit() {
    if (_ctl.text.trim().isEmpty) return;
    final g = s.grader.grade(s.step, _ctl.text);
    s.record(answer: _ctl.text, startedAt: _started, correct: null, score: g.score);
    _draft.discard();
    s.progress.clearDraft(s.caseId, s.step.id);
    setState(() {
      _restored = false;
      _grade = g;
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = s.step;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      if (step.chart != null) InteractiveChart(step.chart!),
      if (step.flawedPlan != null)
        // The plan to attack, as a sticky note on the page.
        RuledNote(
          title: 'The plan to challenge',
          icon: Icons.sticky_note_2_outlined,
          rule: c.highlighter,
          background: c.stickyNote,
          child: Prose(step.flawedPlan!,
              resolver: s.resolver, style: t.bodyLarge?.copyWith(fontStyle: FontStyle.italic), linker: s.linker, onTerm: s.onTerm),
        ),
      ScaffoldGuide(step.scaffold),
      RuledAnswerBox(
        child: TextField(
          controller: _ctl,
          minLines: 8,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: t.bodyLarge?.copyWith(height: RuledAnswerBox.lineHeight),
          decoration: const InputDecoration(hintText: 'Explain in your own words…', fillColor: Colors.transparent),
        ),
      ),
      DraftStatus(_draft, restored: _restored, leading: _words > 0 ? '$_words words' : null),
      if (step.contextSnippets.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('show_code'),
            onPressed: () => CodeContext.showSheet(context, s),
            icon: const Icon(Icons.code_rounded),
            label: const Text('Show the code'),
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
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                SectionTitle('Model answer', icon: Icons.task_alt_rounded),
                Prose(step.modelAnswer!, resolver: s.resolver),
                const Divider(),
                SectionTitle('What the examiner will look for', icon: Icons.checklist_rounded),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          SectionTitle('The real file: ${d['key']}', icon: Icons.table_chart_outlined),
          Text('${d['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Units: ${d['units'] ?? '?'}'),
          Text('Frequency: ${d['frequency'] ?? '?'}'),
          Text('Rows: ${schema['rows']}'),
          Text('Columns: ${cols.map((c) => '$c (${dtypes[c]})').join(', ')}'),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          SectionTitle('What the pipeline logged: ${t['id']}', icon: Icons.receipt_long_outlined),
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

/// A writing pad: faint ruled lines behind the answer, like a notebook page.
class RuledAnswerBox extends StatelessWidget {
  const RuledAnswerBox({super.key, required this.child});
  final Widget child;

  /// Line height of the answer text, so the rules sit under each line.
  static const lineHeight = 1.6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fontSize = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16;
    return Container(
      decoration: BoxDecoration(color: c.paperRaised, borderRadius: BorderRadius.circular(12)),
      child: CustomPaint(painter: _Rules(c.rule, fontSize * lineHeight), child: child),
    );
  }
}

class _Rules extends CustomPainter {
  _Rules(this.color, this.gap);
  final Color color;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    // contentPadding top (14) + one line, then every line after.
    for (var y = 14 + gap; y < size.height - 6; y += gap) {
      canvas.drawLine(Offset(14, y), Offset(size.width - 14, y), p);
    }
  }

  @override
  bool shouldRepaint(_Rules old) => old.color != color || old.gap != gap;
}
