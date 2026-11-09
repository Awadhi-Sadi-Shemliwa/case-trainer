import 'package:flutter/material.dart';

import '../../engine/checker.dart';
import '../../engine/placeholders.dart';
import '../widgets/prose.dart';
import '../widgets/code_view.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = s.step;
    final snippet = step.snippet;
    final code = snippet == null ? null : s.content.snippet(s.caseId, snippet.file, snippet.name);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      if (code != null) CodeView(code, label: '${snippet!.file} · ${snippet.name}'),
      if (_multi) Text('Select all that apply.', style: TextStyle(color: cs.onSurfaceVariant)),
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
    final cs = Theme.of(context).colorScheme;
    final border = reveal == null
        ? (selected ? cs.primary : cs.outlineVariant)
        : (reveal! ? cs.primary : cs.outlineVariant);
    final icon = multi
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return Material(
      color: selected ? cs.primaryContainer.withValues(alpha: 0.45) : cs.surfaceContainerLow,
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
                    color: reveal == null ? cs.primary : (reveal! ? cs.primary : cs.outline)),
                Expanded(child: Prose(text, resolver: resolver, style: Theme.of(context).textTheme.bodyLarge)),
              ]),
              if (explanation != null && explanation!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Prose(explanation!, resolver: resolver, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
