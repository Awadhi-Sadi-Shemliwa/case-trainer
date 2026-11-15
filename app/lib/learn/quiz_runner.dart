import 'package:flutter/material.dart';

import '../ui/theme/tokens.dart';
import '../ui/widgets/highlight.dart';
import 'course.dart';
import 'quiz.dart';
import 'term_card.dart';

/// Runs a list of quick-check questions one at a time: answer, see why, next. Reports each answer as it
/// happens (so progress is saved even if you leave halfway) and the score at the end.
class QuizRunner extends StatefulWidget {
  const QuizRunner({
    super.key,
    required this.questions,
    required this.onAnswer,
    required this.onFinished,
    this.passMark,
  });

  final List<QuizQuestion> questions;
  final void Function(GlossaryTerm term, bool correct) onAnswer;
  final void Function(int score, List<GlossaryTerm> missed) onFinished;

  /// When set, the result says whether the check was passed.
  final int? passMark;

  @override
  State<QuizRunner> createState() => _QuizRunnerState();
}

class _QuizRunnerState extends State<QuizRunner> {
  int _i = 0;
  QuizOption? _picked;
  int _score = 0;
  final List<GlossaryTerm> _missed = [];
  bool _done = false;

  QuizQuestion get _q => widget.questions[_i];

  void _pick(QuizOption o) {
    if (_picked != null) return;
    final ok = _q.isCorrect(o);
    setState(() {
      _picked = o;
      if (ok) {
        _score++;
      } else {
        _missed.add(_q.term);
      }
    });
    widget.onAnswer(_q.term, ok);
  }

  void _next() {
    if (_i + 1 < widget.questions.length) {
      setState(() {
        _i++;
        _picked = null;
      });
    } else {
      setState(() => _done = true);
      widget.onFinished(_score, List.of(_missed));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _Result(score: _score, total: widget.questions.length, missed: _missed, passMark: widget.passMark);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final q = _q;
    final answered = _picked != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      _Dots(count: widget.questions.length, at: _i),
      Text('Question ${_i + 1} of ${widget.questions.length}', style: t.labelMedium?.copyWith(color: c.inkSoft)),
      Text(q.prompt, style: t.headlineSmall),
      if (q.clue != null)
        RuledNote(rule: c.highlighter, background: c.stickyNote, child: Text(q.clue!, style: t.bodyLarge)),
      for (final o in q.options)
        _OptionButton(
          key: ValueKey('quiz_option_${o.termId}'),
          text: o.text,
          state: !answered
              ? _OptionState.open
              : q.isCorrect(o)
                  ? _OptionState.right
                  : (o == _picked ? _OptionState.wrong : _OptionState.dim),
          onTap: () => _pick(o),
        ),
      if (answered) ...[
        RuledNote(
          title: q.isCorrect(_picked!) ? 'Right' : 'Not quite',
          icon: q.isCorrect(_picked!) ? Icons.check_circle_rounded : Icons.highlight_off_rounded,
          rule: q.isCorrect(_picked!) ? c.good : c.bad,
          child: Text('${q.term.term}: ${q.term.short}', style: t.bodyMedium),
        ),
        FilledButton(
          key: const ValueKey('quiz_next'),
          onPressed: _next,
          child: Text(_i + 1 < widget.questions.length ? 'Next question' : 'See my score'),
        ),
      ],
    ]);
  }
}

enum _OptionState { open, right, wrong, dim }

class _OptionButton extends StatelessWidget {
  const _OptionButton({super.key, required this.text, required this.state, required this.onTap});
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (border, bg, icon) = switch (state) {
      _OptionState.open => (c.grid, c.paperRaised, Icons.radio_button_unchecked_rounded),
      _OptionState.right => (c.good, c.goodContainer, Icons.check_circle_rounded),
      _OptionState.wrong => (c.bad, c.badContainer, Icons.cancel_rounded),
      _OptionState.dim => (c.grid, c.paper, Icons.radio_button_unchecked_rounded),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border, width: state == _OptionState.open || state == _OptionState.dim ? 1 : 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: state == _OptionState.open ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Icon(icon, color: state == _OptionState.right ? c.good : (state == _OptionState.wrong ? c.bad : c.inkSoft)),
              Expanded(
                child: Text(text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: state == _OptionState.dim ? c.inkMuted : c.ink)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.at});
  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(spacing: 4, children: [
      for (var i = 0; i < count; i++)
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 5,
            decoration: BoxDecoration(
              color: i < at ? c.ink : (i == at ? c.highlighter : c.grid),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
    ]);
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.score, required this.total, required this.missed, required this.passMark});
  final int score;
  final int total;
  final List<GlossaryTerm> missed;
  final int? passMark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final passed = passMark == null ? null : score >= passMark!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Text('$score of $total', key: const ValueKey('quiz_score'), style: t.displaySmall),
      if (passed != null)
        RuledNote(
          title: passed ? 'Lesson passed' : 'Not passed yet',
          icon: passed ? Icons.verified_rounded : Icons.refresh_rounded,
          rule: passed ? c.good : c.bad,
          child: Text(
            passed
                ? 'The words you got right are now known. They come back for review after a day, then three, seven and twenty-one.'
                : 'You need $passMark of $total to pass. Read the words you missed, then try again: the questions change each time.',
            style: t.bodyMedium,
          ),
        ),
      if (missed.isNotEmpty) ...[
        SectionTitle('Words to look at again', icon: Icons.bookmark_border_rounded),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in missed) ActionChip(label: Text(m.term), onPressed: () => showTermSheet(context, m)),
        ]),
      ],
    ]);
  }
}
