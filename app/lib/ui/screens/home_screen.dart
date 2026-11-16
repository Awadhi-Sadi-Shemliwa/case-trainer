import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../engine/sector_slots.dart';
import '../../report/finish_flow.dart';
import '../../providers.dart';
import '../theme/tokens.dart';
import '../widgets/phase_bar.dart';
import '../widgets/real_curves.dart';

/// The case list: where you left off, the finance course, then each sector's case files.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(progressTickProvider);
    final content = ref.watch(contentDbProvider);
    final progress = ref.read(progressDbProvider);
    final cases = content.cases();
    final last = progress.lastOpenCase();
    final lastCase = last == null ? null : cases.where((c) => c.id == last.caseId).firstOrNull;
    final p = ref.watch(courseProgressProvider);
    final next = p.nextLesson;
    final c = context.colors;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text('Cases', style: t.displaySmall),
            const SizedBox(height: 6),
            Text('Real data, real decisions. Predict the data, justify every cleaning step, challenge the plan, then decide.',
                style: t.bodyMedium?.copyWith(color: c.inkSoft)),
            if (lastCase != null) ...[
              const SizedBox(height: 18),
              _Resume(info: lastCase, stepIdx: last!.stepIdx, total: content.steps(lastCase.id).length),
            ],
            if (next != null) ...[
              const SizedBox(height: 12),
              Material(
                color: c.stickyNote,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.highlighter)),
                child: InkWell(
                  key: const ValueKey('home_learn'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.go('/learn'),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(spacing: 12, children: [
                      Icon(Icons.menu_book_rounded, color: c.ink),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text('Finance Foundations', style: t.titleSmall),
                          Text('${p.knownTotal} of ${p.course.terms.length} words known. Next: ${next.title}.', style: t.bodySmall),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.ink),
                    ]),
                  ),
                ),
              ),
            ],
            for (final d in domainOrder) ...[
              const SizedBox(height: 28),
              Row(spacing: 8, children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: c.sector(d), shape: BoxShape.circle)),
                Icon(sectorIcon(d), size: 20, color: c.inkSoft),
                Text(domainLabels[d]!, style: t.headlineSmall),
              ]),
              const SizedBox(height: 10),
              ...() {
                final slot = sectorSlot(d, cases, content.catalog(), progress);
                return [
                  if (slot.active != null) _CaseCard(slot.active!),
                  if (slot.active == null && slot.preparing != null) _PreparingCard(slot.preparing!),
                  if (slot.active == null && slot.preparing == null)
                    Text('No cases yet. They are built in later batches.', style: t.bodyMedium?.copyWith(color: c.inkSoft)),
                  for (final f in slot.finished) _FinishedTile(f),
                ];
              }(),
            ],
          ],
        ),
      ),
    );
  }
}

class _Resume extends StatelessWidget {
  const _Resume({required this.info, required this.stepIdx, required this.total});
  final CaseInfo info;
  final int stepIdx;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text('Pick up where you left off', style: t.labelLarge?.copyWith(color: c.highlighter)),
        Text(info.title, style: t.titleLarge?.copyWith(color: c.paper)),
        Text('P${info.number}, step ${stepIdx + 1} of $total', style: t.bodyMedium?.copyWith(color: c.paper.withValues(alpha: 0.85))),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('resume_case'),
            style: FilledButton.styleFrom(backgroundColor: c.highlighter, foregroundColor: c.onHighlighter),
            onPressed: () => context.push('/case/${info.id}'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Continue'),
          ),
        ),
      ]),
    );
  }
}

class _CaseCard extends ConsumerWidget {
  const _CaseCard(this.info);
  final CaseInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final total = ref.read(contentDbProvider).steps(info.id).length;
    final st = ref.read(progressDbProvider).caseState(info.id);
    final reached = st == null ? 0 : st.maxIdx + 1;
    final label = st == null ? 'Start' : (st.completed ? 'Review' : 'Continue');
    final sector = c.sector(info.domain);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/case/${info.id}'),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: sector, width: 5))),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              Row(spacing: 8, children: [
                Text('P${info.number}', style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                Flexible(child: _Tag('Tier ${info.tier}')),
                const Spacer(),
                Flexible(
                  flex: 3,
                  child: Text(label,
                      textAlign: TextAlign.end, overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right_rounded, color: c.ink),
              ]),
              Text(info.title, style: t.titleLarge),
              Text('For: ${info.decisionMaker}', style: t.bodySmall),
              if (info.signatureChart != null)
                ExcludeSemantics(child: RealSparkline(info.signatureChart!, color: sector)),
              StepTicks(total: total, reached: reached, color: sector),
              Text('$reached of $total steps reached', style: t.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.paperSunken, borderRadius: BorderRadius.circular(6)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

/// The sector's next curriculum problem, not built yet (P33 after P34 in football).
class _PreparingCard extends StatelessWidget {
  const _PreparingCard(this.p);
  final CatalogProblem p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: ValueKey('preparing_${p.number}'),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c.sector(p.domain).withValues(alpha: 0.5), width: 5))),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Row(spacing: 8, children: [
              Text('P${p.number}', style: t.titleLarge),
              _Tag('Tier ${p.tier}'),
              const Spacer(),
              Text('Being prepared', style: t.labelLarge?.copyWith(color: c.inkSoft)),
            ]),
            Text(p.title, style: t.titleLarge),
            Text(p.summary, style: t.bodyMedium),
            Text('Up next in this sector. It opens here once it has been solved on real data.', style: t.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// A finished case: open it again, or share its report.
class _FinishedTile extends ConsumerWidget {
  const _FinishedTile(this.info);
  final CaseInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final report = ref.read(progressDbProvider).latestReport(info.id);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('finished_${info.id}'),
        leading: Icon(Icons.task_alt_rounded, color: c.good),
        title: Text('P${info.number}: ${info.title}'),
        subtitle: Text(report == null ? 'Finished' : 'Finished. Report: ${report.downloadName ?? 'saved in the app'}'),
        onTap: () => context.push('/case/${info.id}'),
        trailing: IconButton(
          tooltip: report == null ? 'Write the report' : 'Share the report',
          icon: Icon(report == null ? Icons.picture_as_pdf_outlined : Icons.ios_share_rounded),
          onPressed: () async {
            final path = report != null && File(report.filePath).existsSync() ? report.filePath : (await writeReport(ref, info)).path;
            await shareReport(path, info);
          },
        ),
      ),
    );
  }
}
