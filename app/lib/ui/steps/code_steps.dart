import 'package:flutter/material.dart';

import '../../engine/checker.dart';
import '../theme/typography.dart';
import '../widgets/code_view.dart';
import 'draft_saver.dart';
import 'step_common.dart';

String _snippet(StepScope s) {
  final sn = s.step.snippet!;
  return s.content.snippet(s.caseId, sn.file, sn.name) ?? (throw StateError('snippet ${sn.file}:${sn.name} missing from bundle'));
}

String _label(StepScope s) => '${s.step.snippet!.name} in ${s.step.snippet!.file}';

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
  late final DraftSaver _draft;
  bool _restored = false;
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;
  bool get _done => _solved || _attempts >= revealAfterAttempts;

  @override
  void initState() {
    super.initState();
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
    final kept = s.progress.draft(s.caseId, s.step.id);
    final n = s.step.blanks.length;
    final restore = !_done && kept is List && kept.length == n;
    if (_done) s.progress.clearDraft(s.caseId, s.step.id);
    _ctls = [for (var i = 0; i < n; i++) TextEditingController(text: restore ? '${kept[i]}' : '')];
    _restored = restore && _ctls.any((c) => c.text.isNotEmpty);
    _draft = DraftSaver(() => s.progress.saveDraft(s.caseId, s.step.id, [for (final c in _ctls) c.text]));
    final seen = [for (final c in _ctls) c.text];
    for (var i = 0; i < n; i++) {
      _ctls[i].addListener(() {
        if (_ctls[i].text == seen[i]) return;
        seen[i] = _ctls[i].text;
        _draft.changed();
      });
    }
  }

  @override
  void dispose() {
    _draft.dispose();
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
    if (_done) {
      _draft.discard();
      s.progress.clearDraft(s.caseId, s.step.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _snippet(s);
    final done = _done;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      StepHeader(s),
      CodeView(done ? code : _withBlanks(code), label: done ? 'Real code' : _label(s)),
      if (!done)
        for (var i = 0; i < _ctls.length; i++)
          TextField(
            controller: _ctls[i],
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: fontCode, fontFeatures: codeFeatures),
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: blankLabel(i)),
          ),
      if (!done) DraftStatus(_draft, restored: _restored),
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
  late final DraftSaver _draft;
  late String _seen;
  bool _restored = false;
  CheckResult? _result;
  late int _attempts;
  late bool _solved;

  StepScope get s => widget.scope;
  bool get _done => _solved || _attempts >= revealAfterAttempts;

  @override
  void initState() {
    super.initState();
    _attempts = s.progress.attemptCount(s.caseId, s.step.id);
    _solved = s.progress.solved(s.caseId, s.step.id);
    final buggy = s.step.buggyCode!.trimRight();
    final kept = s.progress.draft(s.caseId, s.step.id);
    if (_done) s.progress.clearDraft(s.caseId, s.step.id);
    _restored = !_done && kept is String && kept != buggy;
    _seen = _restored ? kept as String : buggy;
    _ctl = TextEditingController(text: _seen);
    _draft = DraftSaver(() => s.progress.saveDraft(s.caseId, s.step.id, _ctl.text));
    _ctl.addListener(() {
      if (_ctl.text == _seen) return;
      _seen = _ctl.text;
      _draft.changed();
    });
  }

  @override
  void dispose() {
    _draft.dispose();
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
    if (_done) {
      _draft.discard();
      s.progress.clearDraft(s.caseId, s.step.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
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
          style: const TextStyle(fontFamily: fontCode, fontSize: 13, height: 1.5, fontFeatures: codeFeatures),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        DraftStatus(_draft, restored: _restored),
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
        TextButton(
          onPressed: () {
            setState(() => _attempts = revealAfterAttempts);
            _draft.discard();
            s.progress.clearDraft(s.caseId, s.step.id);
          },
          child: const Text('Show the fix'),
        ),
    ]);
  }
}
