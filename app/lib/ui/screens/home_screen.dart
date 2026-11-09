import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(progressTickProvider);
    final content = ref.watch(contentDbProvider);
    final cases = content.cases();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text('Case Trainer', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Real data, real decisions. Predict the data, justify every cleaning step, challenge the plan, then decide.',
                style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            for (final d in domainOrder) ...[
              const SizedBox(height: 24),
              Text(domainLabels[d]!.toUpperCase(), style: t.labelLarge?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...() {
                final inDomain = cases.where((c) => c.domain == d).toList();
                if (inDomain.isEmpty) {
                  return [
                    Text('No cases yet. They are built in later batches.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ];
                }
                return [for (final c in inDomain) _CaseCard(c)];
              }(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaseCard extends ConsumerWidget {
  const _CaseCard(this.c);
  final CaseInfo c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final total = ref.read(contentDbProvider).steps(c.id).length;
    final st = ref.read(progressDbProvider).caseState(c.id);
    final reached = st == null ? 0 : st.maxIdx + 1;
    final label = st == null ? 'Start' : (st.completed ? 'Review' : 'Continue');
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/case/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Row(spacing: 8, children: [
              _Chip('P${c.number}', cs.primaryContainer, cs.onPrimaryContainer),
              _Chip('Tier ${c.tier}', cs.secondaryContainer, cs.onSecondaryContainer),
              const Spacer(),
              Text(label, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right, color: cs.primary),
            ]),
            Text(c.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text(c.decisionMaker, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in c.concepts.take(5)) _Chip(k, cs.surfaceContainerHighest, cs.onSurface),
              if (c.concepts.length > 5) _Chip('+${c.concepts.length - 5} more', cs.surfaceContainerHighest, cs.onSurfaceVariant),
            ]),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: total == 0 ? 0 : reached / total, minHeight: 6),
            ),
            Text('$reached of $total steps reached', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );
}
