import 'dart:convert';

import 'package:flutter/material.dart';

import '../../grading/grader.dart';
import '../../data/progress_db.dart';
import '../widgets/code_context.dart';
import '../widgets/examiner_card.dart';
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
  var _started = DateTime.now();
  late final TextEditingController _ctl;
  late final DraftSaver _draft;
  late String _seen;
  bool _restored = false;

  /// Text saved before the examiner existed (or while it was unreachable) and never graded.
  bool _ungradedSaved = false;
  bool _grading = false;

  /// Why the last submit could not be graded (offline, no credit...). The attempt was not used up.
  String? _unavailable;
  late List<ExaminedAttempt> _history;

  StepScope get s => widget.scope;
  ExaminedAttempt? get _latest => _history.isEmpty ? null : _history.last;
  bool get _passed => _history.any((a) => a.passed);
  bool get _revealed => _passed || _history.length >= revealAfterAttempts;

  @override
  void initState() {
    super.initState();
    _history = s.progress.examinedAttempts(s.caseId, s.step.id);
    final last = s.progress.lastAttempt(s.caseId, s.step.id);
    final lastText = last == null ? '' : jsonDecode(last['answer_json'] as String) as String;
    _ungradedSaved = last != null && (_history.isEmpty || _latest!.answer != lastText);
    // Unsent text wins over the last submitted answer: it is newer.
    final kept = s.progress.draft(s.caseId, s.step.id);
    _restored = kept is String && kept != lastText;
    _seen = kept is String ? kept : lastText;
    _ctl = TextEditingController(text: _seen);
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

  Future<void> _submit({String? text}) async {
    final answer = text ?? _ctl.text;
    if (answer.trim().isEmpty || _grading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _grading = true;
      _unavailable = null;
    });
    final g = await s.grader.grade(s.step, answer, s.resolver, caseInfo: s.caseInfo);
    if (!mounted) return;
    if (!g.countsAsAttempt) {
      // Keep the text as a draft; nothing is used up.
      s.progress.saveDraft(s.caseId, s.step.id, _ctl.text);
      setState(() {
        _grading = false;
        _unavailable = g.message;
      });
      return;
    }
    s.progress.recordExaminedAttempt(
      caseId: s.caseId,
      stepId: s.step.id,
      answer: answer,
      startedAt: _started,
      feedback: g.toJson(),
      status: g.status.name,
      score: g.score,
      passed: g.passed,
      model: g.model,
      inputTokens: g.inputTokens,
      outputTokens: g.outputTokens,
      hintsUsed: _history.length.clamp(0, 2),
    );
    _history = s.progress.examinedAttempts(s.caseId, s.step.id);
    if (_revealed) s.progress.scheduleReview(s.caseId, s.step.id);
    s.onProgress();
    _draft.discard();
    s.progress.clearDraft(s.caseId, s.step.id);
    setState(() {
      _grading = false;
      _restored = false;
      _ungradedSaved = false;
      _started = DateTime.now();
    });
  }

  String get _tryLine {
    final n = _history.length;
    if (_passed) return 'Passed on try ${_history.indexWhere((a) => a.passed) + 1}.';
    if (_revealed) return 'Three tries used. The answer is shown below, and this step now counts as answered.';
    return 'Try $n of $revealAfterAttempts.';
  }

  @override
  Widget build(BuildContext context) {
    final step = s.step;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final latest = _latest;
    final hasText = _ctl.text.trim().isNotEmpty;
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
          key: const ValueKey('answer_field'),
          controller: _ctl,
          minLines: 8,
          maxLines: null,
          enabled: !_grading,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: t.bodyLarge?.copyWith(height: RuledAnswerBox.lineHeight),
          decoration: const InputDecoration(hintText: 'Explain in your own words…', fillColor: Colors.transparent),
        ),
      ),
      DraftStatus(_draft, restored: _restored, leading: _words > 0 ? (_words == 1 ? '1 word' : '$_words words') : null),
      if (_ungradedSaved && !_grading && _unavailable == null)
        FeedbackCard(
          key: const ValueKey('ungraded_saved'),
          kind: FeedbackKind.info,
          title: 'Saved but not graded yet',
          message: 'This answer was saved before the examiner could read it. Submit it to have it graded.',
          resolver: s.resolver,
        ),
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
      if (_grading)
        const _Reading()
      else ...[
        SubmitButton(
          label: _unavailable != null ? 'Grade now' : (latest == null ? 'Submit answer' : 'Submit again'),
          onPressed: hasText ? _submit : null,
        ),
        if (!_revealed)
          OutlinedButton.icon(
            key: const ValueKey('dont_know'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () => _submit(text: "I don't know"),
            icon: const Icon(Icons.help_outline_rounded),
            label: Text(_history.length == revealAfterAttempts - 1
                ? "I don't know: show me the answer"
                : "I don't know: give me a hint"),
          ),
      ],
      if (_unavailable != null)
        FeedbackCard(
          key: const ValueKey('examiner_unavailable'),
          kind: FeedbackKind.wrong,
          title: 'Not graded: your answer is saved',
          message: _unavailable,
          resolver: s.resolver,
        ),
      if (latest != null && !_grading) ...[
        Text(_tryLine, style: t.labelLarge?.copyWith(color: c.inkSoft)),
        ExaminerCard(
          result: GradeResult.fromJson(latest.feedback),
          attemptNo: _history.length,
          step: step,
          resolver: s.resolver,
        ),
      ],
      if (_history.isNotEmpty && step.analysisPointer != null && !_grading && !_revealed)
        FeedbackCard(kind: FeedbackKind.info, title: 'Where to look', message: step.analysisPointer, resolver: s.resolver),
      if (_history.isNotEmpty) ..._reveals(),
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

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('examiner_reading'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(spacing: 14, children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          Expanded(child: Text('The examiner is reading your answer…', style: t.bodyLarge)),
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
