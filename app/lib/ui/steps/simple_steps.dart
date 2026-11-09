import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/checker.dart';
import '../widgets/prose.dart';
import 'step_common.dart';

/// Stable 32-bit FNV-1a hash, so the shuffled order is the same on every run and device.
int _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// order_steps: drag the items into the right order.
class OrderStep extends StatefulWidget {
  const OrderStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<OrderStep> createState() => _OrderStepState();
}

class _OrderStepState extends State<OrderStep> {
  final _started = DateTime.now();
  late List<String> _items;
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;

  @override
  void initState() {
    super.initState();
    final target = s.step.items;
    _items = [...target]..sort((a, b) => _fnv('${s.step.id}|$a').compareTo(_fnv('${s.step.id}|$b')));
    if (_listEq(_items, target)) _items = [..._items.reversed];
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
    if (_solved) _items = [...target];
  }

  bool _listEq(List<String> a, List<String> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  void _submit() {
    final r = Checker.order(s.step, _items);
    s.record(answer: _items, startedAt: _started, correct: r.correct);
    setState(() {
      _result = r;
      _attempts++;
      _solved = _solved || r.correct;
      if (!_solved && _attempts >= revealAfterAttempts) _items = [...s.step.items];
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = _solved || _attempts >= revealAfterAttempts;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      Text(done ? 'The correct order:' : 'Hold and drag the handle to reorder.', style: TextStyle(color: cs.onSurfaceVariant)),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: done
            ? (_, _) {}
            : (oldI, newI) => setState(() {
                  _items.insert(newI, _items.removeAt(oldI));
                  _result = null;
                }),
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              key: ValueKey(_items[i]),
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: cs.surfaceContainerLow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
                child: ListTile(
                  minTileHeight: 56,
                  title: Text(_items[i]),
                  trailing: done
                      ? Icon(Icons.check, color: cs.primary)
                      : ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle))),
                ),
              ),
            ),
        ],
      ),
      if (_result != null)
        FeedbackCard(
          kind: _result!.correct ? FeedbackKind.correct : (done ? FeedbackKind.info : FeedbackKind.wrong),
          title: _result!.correct ? 'Correct order' : (done ? 'Order revealed' : 'Not yet'),
          message: _result!.correct || done ? null : _result!.message,
          resolver: s.resolver,
        ),
      if (!done) SubmitButton(label: 'Check order', onPressed: _submit),
    ]);
  }
}

/// numeric: type a number; checked against the pipeline result within the declared tolerance.
class NumericStep extends StatefulWidget {
  const NumericStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<NumericStep> createState() => _NumericStepState();
}

class _NumericStepState extends State<NumericStep> {
  final _started = DateTime.now();
  final _ctl = TextEditingController();
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;

  @override
  void initState() {
    super.initState();
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final res = s.resolver.results[s.step.answerKey!]!;
    final r = Checker.numeric(s.step, _ctl.text, res);
    if (double.tryParse(_ctl.text.replaceAll('%', '').replaceAll(',', '').trim()) == null) {
      setState(() => _result = r);
      return;
    }
    s.record(answer: _ctl.text, startedAt: _started, correct: r.correct);
    setState(() {
      _result = r;
      _attempts++;
      _solved = _solved || r.correct;
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _solved || _attempts >= revealAfterAttempts;
    final key = s.step.answerKey!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      TextField(
        controller: _ctl,
        enabled: !done,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,% ]'))],
        decoration: InputDecoration(border: const OutlineInputBorder(), labelText: 'Your answer', suffixText: s.step.unit),
        onSubmitted: (_) => _submit(),
      ),
      if (_result != null && !done)
        FeedbackCard(kind: FeedbackKind.wrong, title: 'Not quite', message: _result!.message, resolver: s.resolver),
      if (done)
        FeedbackCard(
          kind: _solved ? FeedbackKind.correct : FeedbackKind.info,
          title: _solved ? 'Correct' : 'Answer revealed',
          message: 'The pipeline value is {expected.$key} ${s.step.unit ?? ''}.',
          resolver: s.resolver,
        ),
      if (!done) SubmitButton(label: 'Check', onPressed: _submit),
    ]);
  }
}

/// concept_card: information only (optionally with a chart).
class ConceptCardStep extends StatefulWidget {
  const ConceptCardStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<ConceptCardStep> createState() => _ConceptCardStepState();
}

class _ConceptCardStepState extends State<ConceptCardStep> {
  @override
  Widget build(BuildContext context) {
    final s = widget.scope;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Text(s.step.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      Prose(s.step.prompt, resolver: s.resolver, style: t.titleMedium),
      if (s.step.chart != null) ChartImage(s.step.chart!),
      if (s.step.body != null) Prose(s.step.body!, resolver: s.resolver),
    ]);
  }
}
