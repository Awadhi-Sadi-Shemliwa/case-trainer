import 'package:flutter/material.dart';

import '../../engine/checker.dart';
import '../../engine/placeholders.dart';
import '../widgets/prose.dart';
import '../widgets/code_view.dart';
import '../theme/tokens.dart';
import 'draft_saver.dart';
import 'step_common.dart';

/// mcq, multi_select, kpi_builder and code_predict.
class ChoiceStep extends StatefulWidget {
  const ChoiceStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<ChoiceStep> createState() => _ChoiceStepState();
}

class _ChoiceStepState extends State<ChoiceStep> {
  final _started = DateTime.now();
  final Set<String> _selected = {};
  late final DraftSaver _draft;
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;
  bool get _multi => s.step.type == 'multi_select' || s.step.type == 'kpi_builder';
  bool get _revealed => _solved || _attempts >= revealAfterAttempts;

  @override
  void initState() {
    super.initState();
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
    _draft = DraftSaver(() => s.progress.saveDraft(s.caseId, s.step.id, _selected.toList()..sort()));
    final kept = s.progress.draft(s.caseId, s.step.id);
    if (_revealed) {
      s.progress.clearDraft(s.caseId, s.step.id);
    } else if (kept is List) {
      final ids = {for (final o in s.step.options) o.id};
      final picks = [for (final k in kept) if (ids.contains(k)) k as String];
      _selected.addAll(_multi ? picks : picks.take(1));
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _submit() {
    final r = _multi ? Checker.multi(s.step, _selected) : Checker.mcq(s.step, _selected.firstOrNull);
    if (_selected.isEmpty) {
      setState(() => _result = r);
      return;
    }
    s.record(answer: _selected.toList()..sort(), startedAt: _started, correct: r.correct);
    setState(() {
      _result = r;
      _attempts++;
      _solved = _solved || r.correct;
    });
    if (_revealed) {
      _draft.discard();
      s.progress.clearDraft(s.caseId, s.step.id);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_multi) {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      } else {
        _selected
          ..clear()
          ..add(id);
      }
      _result = null;
    });
    _draft.changed();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final step = s.step;
    final snippet = step.snippet;
    final code = snippet == null ? null : s.content.snippet(s.caseId, snippet.file, snippet.name);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      if (code != null) CodeView(code, label: '${snippet!.name} in ${snippet.file}'),
      if (_multi) Text('Select all that apply.', style: TextStyle(color: c.inkSoft)),
      for (final o in step.options)
        _OptionTile(
          text: o.text,
          selected: _selected.contains(o.id),
          multi: _multi,
          reveal: _revealed ? o.correct : null,
          explanation: _revealed ? o.explanation : null,
          resolver: s.resolver,
          onTap: () => _toggle(o.id),
        ),
      if (_result != null && !_revealed)
        FeedbackCard(
          kind: _result!.correct ? FeedbackKind.correct : FeedbackKind.wrong,
          title: _selected.isEmpty ? 'Choose an option first.' : (_result!.correct ? 'Correct' : 'Not quite'),
          message: _selected.isEmpty || _multi ? (_selected.isEmpty ? null : _result!.message) : _result!.message,
          resolver: s.resolver,
        ),
      if (_revealed)
        FeedbackCard(
          kind: _solved ? FeedbackKind.correct : FeedbackKind.info,
          title: _solved ? 'Correct. Every option is explained above.' : 'Answer revealed. Every option is explained above.',
          resolver: s.resolver,
        ),
      if (_revealed && step.outputName != null)
        CodeView(s.content.captured(s.caseId)[step.outputName!] ?? '', label: 'Real output', highlight: false),
      if (!_revealed) SubmitButton(label: 'Check', onPressed: _submit),
    ]);
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.selected,
    required this.multi,
    required this.reveal,
    required this.explanation,
    required this.resolver,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final bool multi;
  final bool? reveal;
  final String? explanation;
  final Resolver resolver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = reveal == null ? (selected ? c.ink : c.grid) : (reveal! ? c.good : c.grid);
    final icon = multi
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return Material(
      color: reveal == true ? c.goodContainer : (selected ? c.stickyNote : c.paperRaised),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border, width: selected || reveal == true ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: reveal == null ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                Icon(reveal == null ? icon : (reveal! ? Icons.check_circle : Icons.cancel_outlined),
                    color: reveal == null ? c.ink : (reveal! ? c.good : c.inkMuted)),
                Expanded(child: Prose(text, resolver: resolver, style: Theme.of(context).textTheme.bodyLarge)),
              ]),
              if (explanation != null && explanation!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Prose(explanation!, resolver: resolver, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.inkSoft)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
