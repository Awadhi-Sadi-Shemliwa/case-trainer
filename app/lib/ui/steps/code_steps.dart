import 'package:flutter/material.dart';

import '../../engine/checker.dart';
import '../widgets/code_view.dart';
import 'step_common.dart';

String _snippet(StepScope s) {
  final sn = s.step.snippet!;
  return s.content.snippet(s.caseId, sn.file, sn.name) ?? (throw StateError('snippet ${sn.file}:${sn.name} missing from bundle'));
}

String _label(StepScope s) => '${s.step.snippet!.file} · ${s.step.snippet!.name}';

/// code_read: the real pipeline code, read before the next question.
class CodeReadStep extends StatelessWidget {
  const CodeReadStep(this.scope, {super.key});
  final StepScope scope;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        StepHeader(scope),
        CodeView(_snippet(scope), label: _label(scope)),
      ]);
}

/// Letters, not digits, label the blanks (the no-hard-coded-numbers test scans step text).
String blankLabel(int i) => 'Blank ${String.fromCharCode(65 + i)}';

/// code_fill: blanks cut out of the real code; each answer must match the removed token.
class CodeFillStep extends StatefulWidget {
  const CodeFillStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<CodeFillStep> createState() => _CodeFillStepState();
}

class _CodeFillStepState extends State<CodeFillStep> {
  final _started = DateTime.now();
  late final List<TextEditingController> _ctls;
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;

  @override
  void initState() {
    super.initState();
    _ctls = [for (final _ in s.step.blanks) TextEditingController()];
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
  }

  @override
  void dispose() {
    for (final c in _ctls) {
      c.dispose();
    }
    super.dispose();
  }

  String _withBlanks(String code) {
    var out = code;
    final blanks = s.step.blanks;
    for (var i = 0; i < blanks.length; i++) {
      out = out.replaceFirst(blanks[i].token, '[ ${blankLabel(i)} ]');
    }
    return out;
  }

  void _submit() {
    final r = Checker.codeFill(s.step, [for (final c in _ctls) c.text]);
    s.record(answer: [for (final c in _ctls) c.text], startedAt: _started, correct: r.correct);
    setState(() {
      _result = r;
      _attempts++;
      _solved = _solved || r.correct;
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = _snippet(s);
    final done = _solved || _attempts >= revealAfterAttempts;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      CodeView(done ? code : _withBlanks(code), label: done ? 'Real code' : _label(s)),
      if (!done)
        for (var i = 0; i < _ctls.length; i++)
          TextField(
            controller: _ctls[i],
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: blankLabel(i)),
          ),
      if (_result != null && !done)
        FeedbackCard(kind: FeedbackKind.wrong, title: 'Not quite', message: _result!.message, resolver: s.resolver),
      if (done)
        FeedbackCard(
          kind: _solved ? FeedbackKind.correct : FeedbackKind.info,
          title: _solved ? 'Correct. This matches the real pipeline code.' : 'Answer revealed: the full code is shown above.',
          resolver: s.resolver,
        ),
      if (!done) SubmitButton(label: 'Check', onPressed: _submit),
    ]);
  }
}

/// code_fix: edit the buggy version until it matches the real code.
class CodeFixStep extends StatefulWidget {
  const CodeFixStep(this.scope, {super.key});
  final StepScope scope;

  @override
  State<CodeFixStep> createState() => _CodeFixStepState();
}

class _CodeFixStepState extends State<CodeFixStep> {
  final _started = DateTime.now();
  late final TextEditingController _ctl;
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: s.step.buggyCode!.trimRight());
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final r = Checker.codeFix(_ctl.text, _snippet(s));
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      if (!done) ...[
        Text('Edit the code below. Spacing does not matter.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        TextField(
          key: CodeView.codeKey,
          controller: _ctl,
          maxLines: null,
          minLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ],
      if (_result != null && !done)
        FeedbackCard(kind: FeedbackKind.wrong, title: 'Not fixed yet', message: _result!.message, resolver: s.resolver),
      if (done) ...[
        CodeView(_snippet(s), label: 'Working code'),
        FeedbackCard(
          kind: _solved ? FeedbackKind.correct : FeedbackKind.info,
          title: _solved ? 'Fixed' : 'Fix revealed',
          message: s.step.bugExplanation,
          resolver: s.resolver,
        ),
      ],
      if (!done) SubmitButton(label: 'Check fix', onPressed: _submit),
      if (!done && _attempts > 0)
        TextButton(onPressed: () => setState(() => _attempts = revealAfterAttempts), child: const Text('Show the fix')),
    ]);
  }
}
