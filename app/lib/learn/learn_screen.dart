import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../ui/theme/tokens.dart';
import '../ui/widgets/highlight.dart';
import 'course.dart';

/// The Learn tab: Finance Foundations (ranked words in three tiers; Core ends with the measures every case uses),
/// reviews due today, word search and what each case teaches.
class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider);
    final p = ref.watch(courseProgressProvider);
    final content = ref.watch(contentDbProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final next = p.nextLesson;
    final books = {for (final s in content.sources()) s.key: s};

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text('Learn', style: t.displaySmall),
            const SizedBox(height: 4),
            Text(course.title, style: t.titleMedium),
            Text('${p.knownTotal} of ${course.terms.length} words known', key: const ValueKey('known_total'),
                style: t.bodyMedium?.copyWith(color: c.inkSoft)),
            const SizedBox(height: 12),
            _TierMeter(course: course, progress: p),
            const SizedBox(height: 16),
            _SearchBox(onTap: () => context.push('/learn/glossary')),
            const SizedBox(height: 16),
            if (p.due.isNotEmpty) ...[
              RuledNote(
                title: '${p.due.length} ${p.due.length == 1 ? 'word is' : 'words are'} due for review',
                icon: Icons.event_repeat_rounded,
                rule: c.highlighter,
                background: c.stickyNote,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const ValueKey('review_now'),
                    onPressed: () => context.push('/learn/review'),
                    child: const Text('Review now'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (next != null) _NextUp(lesson: next, course: course),
            for (final tier in course.tiers) ...[
              const SizedBox(height: 28),
              _TierHeader(tier: tier, course: course, progress: p),
              const SizedBox(height: 8),
              for (final (i, l) in course.lessonsOf(tier.id).indexed) ...[
                if (l.isMeasures && (i == 0 || !course.lessonsOf(tier.id)[i - 1].isMeasures))
                  Padding(
                    key: ValueKey('measures_heading_${tier.id}'),
                    padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text('Measures every case uses', style: t.titleMedium),
                      Text('Scores, errors, tests and data checks from all four cases. Their words are linked in every case.',
                          style: t.bodySmall?.copyWith(color: c.inkSoft)),
                    ]),
                  ),
                _LessonRow(
                  lesson: l,
                  passed: p.lessonPassed(l.id),
                  locked: !p.tierUnlocked(tier.id),
                  isNext: next?.id == l.id,
                  known: course.termsOf(l.id).where((w) => p.known(w.id)).length,
                  total: course.termsOf(l.id).length,
                  lockedHint: 'Pass every ${course.tiers[(tier.ord - 1).clamp(0, course.tiers.length - 1)].title.toLowerCase()} lesson to open this tier.',
                ),
              ],
              if (tier.readNext.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Read next', style: t.labelLarge?.copyWith(color: c.inkSoft)),
                for (final k in tier.readNext)
                  if (books[k] case final b?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${b.title}, by ${b.authorNames}', style: t.bodySmall),
                    ),
              ],
            ],
            const SizedBox(height: 32),
            Text('From the cases', style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('What each case teaches, and the mistakes it trains out of you.', style: t.bodyMedium?.copyWith(color: c.inkSoft)),
            const SizedBox(height: 8),
            for (final cs in content.cases())
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  leading: Icon(sectorIcon(cs.domain), color: c.sector(cs.domain)),
                  title: Text('P${cs.number}: ${cs.title}', style: t.titleSmall),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final k in cs.concepts) Chip(label: Text(k))]),
                    const SizedBox(height: 10),
                    Text('What it teaches', style: t.labelLarge),
                    for (final x in List<String>.from(cs.debrief['concepts_learned'] as List))
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(x, style: t.bodyMedium)),
                    const SizedBox(height: 10),
                    Text('Mistakes it trains you out of', style: t.labelLarge),
                    for (final x in List<String>.from(cs.debrief['common_mistakes'] as List))
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(x, style: t.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.paperRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.grid)),
      child: InkWell(
        key: const ValueKey('open_glossary'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(spacing: 10, children: [
            Icon(Icons.search_rounded, color: c.inkSoft),
            Expanded(child: Text('Look up any word', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.inkMuted))),
          ]),
        ),
      ),
    );
  }
}

class _TierMeter extends StatelessWidget {
  const _TierMeter({required this.course, required this.progress});
  final Course course;
  final CourseProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(spacing: 6, children: [
      for (final tier in course.tiers)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: course.termsOfTier(tier.id).isEmpty ? 0 : progress.knownIn(tier.id) / course.termsOfTier(tier.id).length,
              minHeight: 8,
              color: c.ink,
              backgroundColor: progress.tierUnlocked(tier.id) ? c.grid : c.paperSunken,
            ),
          ),
        ),
    ]);
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({required this.lesson, required this.course});
  final GlossaryLesson lesson;
  final Course course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tier = course.tier(lesson.tier);
    return Container(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text('Next up: lesson ${lesson.number}, ${tier.title.toLowerCase()} tier', style: t.labelLarge?.copyWith(color: c.highlighter)),
        Text(lesson.title, style: t.headlineSmall?.copyWith(color: c.paper)),
        Text(lesson.blurb, style: t.bodyMedium?.copyWith(color: c.paper.withValues(alpha: 0.85))),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('start_next_lesson'),
            style: FilledButton.styleFrom(backgroundColor: c.highlighter, foregroundColor: c.onHighlighter),
            onPressed: () => context.push('/learn/lesson/${lesson.id}'),
            child: const Text('Start lesson'),
          ),
        ),
      ]),
    );
  }
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({required this.tier, required this.course, required this.progress});
  final GlossaryTier tier;
  final Course course;
  final CourseProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final unlocked = progress.tierUnlocked(tier.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
      Row(children: [
        Expanded(child: Text(tier.title, style: t.headlineSmall)),
        if (!unlocked) Icon(Icons.lock_outline_rounded, color: c.inkSoft),
        if (progress.tierComplete(tier.id)) Icon(Icons.verified_rounded, color: c.good),
      ]),
      Text(tier.blurb, style: t.bodyMedium?.copyWith(color: c.inkSoft)),
      Text('${progress.knownIn(tier.id)} of ${course.termsOfTier(tier.id).length} words known',
          style: t.labelMedium?.copyWith(color: c.inkSoft)),
    ]);
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.lesson,
    required this.passed,
    required this.locked,
    required this.isNext,
    required this.known,
    required this.total,
    required this.lockedHint,
  });

  final GlossaryLesson lesson;
  final bool passed;
  final bool locked;
  final bool isNext;
  final int known;
  final int total;
  final String lockedHint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = locked ? c.inkMuted : c.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isNext ? c.stickyNote : c.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isNext ? c.highlighter : c.grid, width: isNext ? 2 : 1),
        ),
        child: InkWell(
          key: ValueKey('lesson_${lesson.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: locked
              ? () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(lockedHint)))
              : () => context.push('/learn/lesson/${lesson.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(spacing: 12, children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: passed ? c.ink : Colors.transparent,
                  border: Border.all(color: passed ? c.ink : (locked ? c.grid : c.inkSoft), width: 1.5),
                ),
                child: passed
                    ? Icon(Icons.check_rounded, size: 20, color: c.paper)
                    : Text('${lesson.number}', style: t.titleSmall?.copyWith(color: fg)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(lesson.title, style: t.titleSmall?.copyWith(color: fg)),
                  Text(lesson.blurb, style: t.bodySmall?.copyWith(color: locked ? c.inkMuted : c.inkSoft), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (locked)
                Icon(Icons.lock_outline_rounded, size: 20, color: c.inkMuted)
              else
                Text('$known/$total', style: t.labelMedium?.copyWith(color: c.inkSoft, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Search every word, locked or not (useful in the middle of a case).
class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseProvider);
    final p = ref.watch(courseProgressProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final q = _q.trim().toLowerCase();
    // Names first, then the definition, then the rest of the card (so "Gini" also finds the ROC card, whose
    // finance note mentions it).
    bool inBody(GlossaryTerm w) =>
        [w.plain, w.usedFor ?? '', unmarked(w.inFinance ?? '')].any((s) => s.toLowerCase().contains(q));
    final hits = q.isEmpty
        ? [...course.terms]
        : [
            for (final w in course.terms)
              if (w.names.any((n) => n.toLowerCase().contains(q)) || w.short.toLowerCase().contains(q) || inBody(w)) w
          ]
      ..sort((a, b) {
        if (q.isEmpty) return a.rank.compareTo(b.rank);
        int score(GlossaryTerm w) => w.names.any((n) => n.toLowerCase() == q)
            ? 0
            : (w.names.any((n) => n.toLowerCase().startsWith(q))
                ? 1
                : (w.names.any((n) => n.toLowerCase().contains(q)) ? 2 : (w.short.toLowerCase().contains(q) ? 3 : 4)));
        final s = score(a).compareTo(score(b));
        return s != 0 ? s : a.rank.compareTo(b.rank);
      });
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('glossary_search'),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search ${course.terms.length} words',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: hits.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No word matches "$_q".', style: t.bodyLarge)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              itemCount: hits.length,
              separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) {
                final w = hits[i];
                return ListTile(
                  key: ValueKey('glossary_${w.id}'),
                  title: Text(w.term, style: t.titleSmall),
                  subtitle: Text(w.short, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  trailing: p.known(w.id) ? Icon(Icons.check_circle_rounded, color: c.good, semanticLabel: 'Known') : null,
                  onTap: () => context.push('/learn/term/${w.id}'),
                );
              },
            ),
    );
  }
}
