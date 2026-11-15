import 'package:flutter/material.dart';

import '../../data/content_db.dart';
import '../../data/models.dart';
import '../../data/progress_db.dart';
import '../../engine/placeholders.dart';
import '../../grading/grader.dart';
import '../../learn/course.dart';
import '../../learn/term_linker.dart';
import '../theme/tokens.dart';
import '../widgets/code_context.dart';
import '../widgets/highlight.dart';
import '../widgets/prose.dart';

/// Everything a step widget needs, handed down by the case player.
class StepScope {
  StepScope({
    required this.caseInfo,
    required this.step,
    required this.resolver,
    required this.content,
    required this.progress,
    required this.grader,
    required this.onProgress,
    this.linker,
    this.onTerm,
  });

  final CaseInfo caseInfo;
  final StepData step;
  final Resolver resolver;
  final ContentDb content;
  final ProgressDb progress;
  final Grader grader;
  final VoidCallback onProgress;

  /// Finance words in step text become tappable when set (finance cases).
  final TermLinker? linker;
  final void Function(GlossaryTerm term)? onTerm;

  String get caseId => caseInfo.id;

  int record({required Object answer, required DateTime startedAt, bool? correct, double? score}) {
    final n = progress.recordAttempt(
        caseId: caseId, stepId: step.id, answer: answer, startedAt: startedAt, correct: correct, score: score);
    onProgress();
    return n;
  }
}

/// Number of failed attempts after which a checked step reveals its answer (mirrors the examiner's 3).
const revealAfterAttempts = 3;

class StepHeader extends StatelessWidget {
  const StepHeader(this.scope, {super.key});
  final StepScope scope;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = scope.step;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Text(s.title, style: t.headlineSmall),
      if (s.body != null) Prose(s.body!, resolver: scope.resolver, linker: scope.linker, onTerm: scope.onTerm),
      Prose(s.prompt,
          resolver: scope.resolver,
          style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          linker: scope.linker,
          onTerm: scope.onTerm),
      if (s.contextSnippets.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: CodeContext(scope)),
    ]);
  }
}

enum FeedbackKind { correct, wrong, info }

class FeedbackCard extends StatelessWidget {
  const FeedbackCard({super.key, required this.kind, required this.title, this.message, required this.resolver});

  final FeedbackKind kind;
  final String title;
  final String? message;
  final Resolver resolver;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (rule, bg, icon) = switch (kind) {
      FeedbackKind.correct => (c.good, c.goodContainer, Icons.check_circle_rounded),
      FeedbackKind.wrong => (c.bad, c.badContainer, Icons.highlight_off_rounded),
      FeedbackKind.info => (c.ink, c.paperRaised, Icons.info_outline_rounded),
    };
    return RuledNote(
      title: title,
      icon: icon,
      rule: rule,
      background: bg,
      child: message != null && message!.isNotEmpty
          ? Prose(message!, resolver: resolver, style: Theme.of(context).textTheme.bodyMedium)
          : const SizedBox.shrink(),
    );
  }
}

class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: onPressed,
        child: Text(label),
      );
}

/// Optional explanation template (spec §5) shown as a collapsible guide.
class ScaffoldGuide extends StatelessWidget {
  const ScaffoldGuide(this.scaffold, {super.key});
  final String scaffold;

  static const templates = {
    'chart_6q': [
      'What is plotted: axes, units, period',
      'Pattern: direction, shape, seasonality',
      'Strength: quote a number (slope, share, lead)',
      'Anomalies: outliers, gaps, regime changes',
      'What it can\'t show: causation, confounders, chance',
      'So what for the business',
    ],
    'cer': ['Claim in one sentence', 'Evidence: the numbers that support it', 'Reasoning: why that evidence supports the claim', 'One limitation'],
    'memo': ['Recommendation, with a number or range', 'Evidence: two or three numbers', 'Risk left over', 'Limitations', 'Next step'],
    'predict_data': ['Grain: what is one row?', 'Units', 'Frequency and coverage', 'How missing values will appear', 'Traps when you combine files'],
    'justify_clean': ['What was done', 'Why', 'Which alternative you rejected', 'What breaks if you skip it'],
    'challenge_plan': ['What the plan assumes', 'Why that fails here', 'Your fix', 'How you would check the fix worked'],
    'threshold': ['Trigger metric', 'Trigger value', 'Action', 'Expected error rate at that value'],
  };

  @override
  Widget build(BuildContext context) {
    final items = templates[scaffold];
    if (items == null) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.format_list_bulleted),
        title: const Text('How to structure your answer'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                const Text('•'),
                Expanded(child: Text(it)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Chart image from the pipeline (interactive charts arrive in Prompt 5). Pinch to zoom, tap for full screen.
class ChartImage extends StatelessWidget {
  const ChartImage(this.chartId, {super.key});
  final String chartId;

  String get asset => 'assets/content/charts/$chartId.png';

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Chart')),
            backgroundColor: Colors.white,
            body: InteractiveViewer(maxScale: 6, child: Center(child: Image.asset(asset))),
          ),
        )),
        child: Container(
          color: Colors.white,
          child: Stack(children: [
            Image.asset(asset, fit: BoxFit.contain),
            const Positioned(right: 8, top: 8, child: Icon(Icons.open_in_full, size: 20, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}
