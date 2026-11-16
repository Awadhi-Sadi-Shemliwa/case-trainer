import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../engine/placeholders.dart';
import '../../grading/grader.dart';
import '../theme/tokens.dart';
import 'highlight.dart';
import 'prose.dart';

/// What the examiner says about one attempt, escalating with the attempt number (docs/knowledge/GRADING.md):
///   attempt 1: score, which rubric points are missing, every wrong sentence quoted with its correction;
///   attempt 2: plus a hint for each missing point, red-flag feedback and what to re-read;
///   attempt 3 or a pass: plus the model answer with every rubric point and why it matters.
class ExaminerCard extends StatelessWidget {
  const ExaminerCard({
    super.key,
    required this.result,
    required this.attemptNo,
    required this.step,
    required this.resolver,
  });

  final GradeResult result;

  /// 1-based examined attempt this result belongs to.
  final int attemptNo;
  final StepData step;
  final Resolver resolver;

  bool get _showHints => attemptNo >= 2;
  bool get _showModel => result.passed || attemptNo >= 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final children = <Widget>[];

    if (result.status == GradeStatus.noAttempt) {
      children.add(RuledNote(
        key: const ValueKey('examiner_no_attempt'),
        title: "That's fine. Here is a way in",
        icon: Icons.lightbulb_outline_rounded,
        rule: c.highlighter,
        background: c.stickyNote,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          if (step.analysisPointer != null)
            Prose('Where to look: ${step.analysisPointer!}', resolver: resolver, style: t.bodyMedium),
          for (final h in _hints(all: _showHints)) _Bullet(h, icon: Icons.tips_and_updates_outlined),
          Text(
            _showModel
                ? 'Read the model answer below, then write it in your own words.'
                : (attemptNo == 1
                    ? 'Write what you can, even a rough first try. Two tries left before the answer is shown.'
                    : 'Write what you can, even a rough first try. One try left before the answer is shown.'),
            style: t.bodySmall,
          ),
        ]),
      ));
    } else if (result.graded) {
      children.add(_ScoreHeader(result));
      if (result.summary.isNotEmpty) children.add(Text(result.summary, style: t.bodyLarge));
      children.add(_PointsList(result.points, showHints: _showHints));
      if (result.errors.isNotEmpty) {
        children.add(SectionTitle('Where your explanation goes wrong', icon: Icons.edit_note_rounded));
        for (final e in result.errors) {
          children.add(_ErrorNote(e));
        }
      }
      if (result.flags.isNotEmpty) {
        children.add(SectionTitle('Red flags', icon: Icons.flag_outlined));
        for (final f in result.flags) {
          children.add(RuledNote(
            rule: c.bad,
            background: c.badContainer,
            title: f.critical ? 'Critical: blocks a pass' : 'Costs points',
            icon: Icons.report_gmailerrorred_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              if (f.quote.isNotEmpty) Text('"${f.quote}"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              // A flag's explanation is attempt-2 help; on attempt 1 the quote alone points at it.
              if (_showHints || _showModel) Text(f.feedback, style: t.bodyMedium),
            ]),
          ));
        }
      }
      if (result.strengths.isNotEmpty) {
        children.add(SectionTitle('What you did well', icon: Icons.thumb_up_alt_outlined));
        for (final s in result.strengths) {
          children.add(_Bullet(s, icon: Icons.check_rounded, color: c.good));
        }
      }
      if (!result.passed && !_showModel) {
        children.add(Text(
          attemptNo == 1
              ? 'Rewrite your answer and submit again. On the next try you also get a hint for each missing point.'
              : 'One more try before the model answer is shown.',
          style: t.bodySmall,
        ));
      }
    }

    if (!result.passed && _showHints && step.json['redo_step'] != null) {
      children.add(RuledNote(
        title: 'Before you rewrite',
        icon: Icons.replay_rounded,
        child: Prose(step.json['redo_step'] as String, resolver: resolver, style: t.bodyMedium),
      ));
    }
    if (_showModel && step.modelAnswer != null) children.add(_ModelAnswer(step: step, resolver: resolver, passed: result.passed));

    return Column(
      key: const ValueKey('examiner_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: children,
    );
  }

  List<String> _hints({required bool all}) {
    final pts = (step.rubric?['points'] as List? ?? const []).cast<Map>();
    final hints = [for (final p in pts) if (p['hint'] != null) resolver.plain(p['hint'] as String)];
    return all ? hints : hints.take(1).toList();
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader(this.r);
  final GradeResult r;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final score = r.score ?? 0;
    final color = r.passed ? c.good : c.bad;
    return Container(
      key: const ValueKey('examiner_score'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: r.passed ? c.goodContainer : c.badContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(spacing: 10, children: [
          Icon(r.passed ? Icons.verified_rounded : Icons.pending_actions_rounded, color: color),
          Expanded(child: Text(r.passed ? 'Passed' : 'Not passed yet', style: t.titleMedium)),
          Text('${score.round()} / 100', style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            LinearProgressIndicator(value: score / 100, minHeight: 8, color: color, backgroundColor: c.paper),
            // The pass mark.
            Positioned.fill(
              child: Align(alignment: const Alignment(passMark / 50 - 1, 0), child: Container(width: 2, color: c.ink)),
            ),
          ]),
        ),
        Text('Pass mark ${passMark.round()}, with no critical red flag.', style: t.bodySmall),
      ]),
    );
  }
}

class _PointsList extends StatelessWidget {
  const _PointsList(this.points, {required this.showHints});
  final List<PointVerdict> points;
  final bool showHints;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          SectionTitle('What the examiner looked for', icon: Icons.checklist_rounded),
          for (final p in points)
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              Icon(
                switch (p.coverage) {
                  Coverage.full => Icons.check_circle_rounded,
                  Coverage.partial => Icons.contrast_rounded,
                  Coverage.none => Icons.cancel_outlined,
                },
                color: switch (p.coverage) {
                  Coverage.full => c.good,
                  Coverage.partial => c.inkSoft,
                  Coverage.none => c.bad,
                },
                semanticLabel: p.coverage.name,
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
                  Row(children: [
                    Expanded(child: Text(p.label, style: t.titleSmall)),
                    Text('${p.earned.round()} of ${p.weight.round()}', style: t.labelMedium?.copyWith(color: c.inkSoft)),
                  ]),
                  if (p.coverage != Coverage.full && p.missing.isNotEmpty) Text(p.missing, style: t.bodyMedium),
                  if (p.numberCapped) Text('The number for this point is missing or not the pipeline value.', style: t.bodySmall),
                  if (showHints && p.coverage != Coverage.full && p.hint != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: c.stickyNote, borderRadius: BorderRadius.circular(8)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                        Icon(Icons.tips_and_updates_outlined, size: 18, color: c.ink),
                        Expanded(child: Text('Hint: ${p.hint}', style: t.bodyMedium)),
                      ]),
                    ),
                ]),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.e);
  final PinpointedError e;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return RuledNote(
      rule: c.bad,
      background: c.paperRaised,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text('You wrote: "${e.quote}"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: c.inkSoft)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Icon(Icons.close_rounded, size: 18, color: c.bad),
          Expanded(child: Text(e.problem, style: t.bodyMedium)),
        ]),
        if (e.correction.isNotEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
            Icon(Icons.arrow_forward_rounded, size: 18, color: c.good),
            Expanded(child: Text(e.correction, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          ]),
      ]),
    );
  }
}

class _ModelAnswer extends StatelessWidget {
  const _ModelAnswer({required this.step, required this.resolver, required this.passed});
  final StepData step;
  final Resolver resolver;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('model_answer'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          SectionTitle(passed ? 'Compare with the model answer' : 'The model answer', icon: Icons.task_alt_rounded),
          Prose(step.modelAnswer!, resolver: resolver),
          const Divider(),
          for (final p in (step.rubric?['points'] as List? ?? const []).cast<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
                Text(p['label'] as String, style: t.titleSmall),
                if (p['why'] != null) Text(p['why'] as String, style: t.bodySmall),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {required this.icon, this.color});
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Icon(icon, size: 18, color: color ?? context.colors.ink),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]);
}
