import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../ui/theme/tokens.dart';
import '../ui/widgets/highlight.dart';
import 'course.dart';

/// Everything about one word: meaning, plain words, formula, a worked example, how it fools people, related
/// words, where the cases use it and which pages the definition was checked against.
class TermCard extends ConsumerWidget {
  const TermCard(this.term, {super.key, this.onRelated, this.compact = false});

  final GlossaryTerm term;

  /// Called for a related word (defaults to opening it in a sheet).
  final void Function(GlossaryTerm)? onRelated;

  /// Hides the "where you meet it" and source lists (used inside lessons, where space matters).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final course = ref.watch(courseProvider);
    final content = ref.watch(contentDbProvider);
    final lesson = course.lesson(term.lesson);
    final tier = course.tier(term.tier);
    final sourceTitles = {for (final s in content.sources()) s.key: s.title};
    final lessonSources = lesson.sources;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Text('Word ${term.rank} of ${course.terms.length}, ${tier.title.toLowerCase()} tier, ${lesson.title.toLowerCase()}',
          style: t.labelMedium?.copyWith(color: c.inkSoft)),
      Text(term.term, style: t.headlineMedium),
      Text(term.short, style: t.titleMedium?.copyWith(height: 1.4)),
      if (term.aliases.isNotEmpty)
        Text('Also called ${term.aliases.take(4).join(', ')}', style: t.bodySmall),
      const SizedBox(height: 2),
      SectionTitle('In plain words', icon: Icons.chat_bubble_outline_rounded),
      Text(term.plain, style: t.bodyLarge),
      if (term.formula != null) ...[
        SectionTitle('Formula', icon: Icons.functions_rounded),
        _Formula(term.formula!),
      ],
      if (term.exampleText != null) ...[
        SectionTitle('Worked example', icon: Icons.calculate_outlined, trailing: Text('made-up numbers', style: t.bodySmall)),
        MarkedText(term.exampleText!, style: t.bodyLarge),
      ],
      RuledNote(
        title: 'How it fools people',
        icon: Icons.report_gmailerrorred_rounded,
        rule: c.bad,
        background: c.badContainer.withValues(alpha: 0.55),
        child: Text(term.foolsYou, style: t.bodyMedium),
      ),
      if (term.related.isNotEmpty) ...[
        SectionTitle('Related words', icon: Icons.hub_outlined),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in term.related)
            if (course.byId[id] case final r?)
              ActionChip(
                label: Text(r.term),
                onPressed: () => onRelated != null ? onRelated!(r) : showTermSheet(context, r),
              ),
        ]),
      ],
      if (!compact && term.inCases.isNotEmpty) ...[
        SectionTitle('Where you meet it', icon: Icons.work_outline_rounded),
        for (final ref in term.inCases)
          Text('${_caseLabel(content.caseById(ref.caseId).number)}: ${content.stepTitle(ref.caseId, ref.stepId) ?? ref.stepId}',
              style: t.bodyMedium),
      ],
      if (!compact && (term.sources.isNotEmpty || lessonSources.isNotEmpty)) ...[
        SectionTitle('Checked against', icon: Icons.verified_outlined),
        for (final k in {...term.sources, ...lessonSources})
          if (sourceTitles[k] case final title?) Text(title, style: t.bodySmall),
      ],
    ]);
  }

  static String _caseLabel(int number) => 'P$number';
}

class _Formula extends StatelessWidget {
  const _Formula(this.f);
  final FormulaInfo f;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.paperSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.grid),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        if (f.image != null)
          Semantics(
            label: f.plain,
            image: true,
            child: ExcludeSemantics(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Image.asset(
                  'assets/content/${f.image}',
                  scale: 3.2,
                  color: c.ink,
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => Text(f.plain, style: t.titleMedium),
                ),
              ),
            ),
          ),
        Text(f.plain, style: t.bodySmall),
        for (final s in f.symbols)
          Text.rich(TextSpan(children: [
            TextSpan(text: '${s.symbol}: ', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            TextSpan(text: s.means, style: t.bodyMedium),
          ])),
      ]),
    );
  }
}

/// Opens a word in a sheet over whatever you are doing (a case step keeps its typed answer underneath).
Future<void> showTermSheet(BuildContext context, GlossaryTerm term) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            TermCard(term, onRelated: (r) {
              Navigator.of(ctx).pop();
              showTermSheet(context, r);
            }),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push('/learn/term/${term.id}');
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open in Learn'),
            ),
          ],
        ),
      ),
    );

/// A word on its own page (from search or "Open in Learn").
class TermScreen extends ConsumerWidget {
  const TermScreen({super.key, required this.termId});
  final String termId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(courseProvider).byId[termId];
    return Scaffold(
      appBar: AppBar(title: Text(term?.term ?? 'Word')),
      body: term == null
          ? const Center(child: Text('This word is not in the course.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [TermCard(term, onRelated: (r) => context.pushReplacement('/learn/term/${r.id}'))],
            ),
    );
  }
}
