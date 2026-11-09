import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../widgets/phase_bar.dart';

/// Progress: per case, how far you got and how your attempts went (detailed analytics in Prompt 9).
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(progressTickProvider);
    final content = ref.read(contentDbProvider);
    final progress = ref.read(progressDbProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final c in content.cases()) ...() {
          final total = content.steps(c.id).length;
          final st = progress.caseState(c.id);
          final sum = progress.caseSummary(c.id);
          final rate = progress.firstTryRate(c.id);
          return [
            Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                  Text('P${c.number} · ${c.title}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(st == null ? 'Not started' : (st.completed ? 'Completed' : 'In progress'), style: TextStyle(color: cs.primary)),
                  Text('Steps reached: ${st == null ? 0 : st.maxIdx + 1} of $total'),
                  Text('Attempts recorded: ${sum.attempts}'),
                  Text('Checked steps solved: ${sum.checkedSolved}'),
                  Text('Written answers saved: ${sum.freeTextSaved} (graded from Prompt 6)'),
                  if (rate != null) Text('Right first time: ${(rate * 100).round()}%'),
                ]),
              ),
            ),
          ];
        }(),
        const SizedBox(height: 8),
        Text('Pass rates per attempt and your most common misconceptions appear here once the examiner is built.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Learn: concepts from the cases (full glossary cards with formulas arrive in Prompt 9).
class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.read(contentDbProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final c in content.cases()) ...[
          Text('P${c.number} · ${c.title}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final k in c.concepts) Chip(label: Text(k))]),
          const SizedBox(height: 16),
          Text('What this case teaches', style: t.titleSmall),
          for (final x in List<String>.from(c.debrief['concepts_learned'] as List))
            ListTile(dense: true, leading: const Icon(Icons.lightbulb_outline), title: Text(x)),
          Text('Mistakes it trains you out of', style: t.titleSmall),
          for (final x in List<String>.from(c.debrief['common_mistakes'] as List))
            ListTile(dense: true, leading: Icon(Icons.warning_amber_outlined, color: cs.error), title: Text(x)),
          const Divider(height: 32),
        ],
        Text('Glossary cards (plain meaning, formula, how it fools people) arrive in Prompt 9.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final content = ref.read(contentDbProvider);
    final meta = content.meta();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Theme', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
            ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
          ],
          selected: {mode},
          onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
        ),
        const SizedBox(height: 24),
        Text('Sources', style: t.titleSmall),
        Text('Only sources opened and checked by the pipeline are shown.', style: TextStyle(color: cs.onSurfaceVariant)),
        for (final s in content.sources())
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.title),
            subtitle: Text('“${s.quote}”\n${s.url}'),
            isThreeLine: true,
            trailing: VerifiedBadge(verified: s.verified),
          ),
        const SizedBox(height: 16),
        Text('Content bundle', style: t.titleSmall),
        Text('Built ${meta['built_utc']} · schema ${meta['bundle_schema_version']}', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: cs.error),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset all progress'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Reset all progress?'),
                content: const Text('This deletes every saved answer, attempt and position. It cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                ],
              ),
            );
            if (ok == true) {
              ref.read(progressDbProvider).resetProgress();
              ref.read(progressTickProvider.notifier).bump();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Progress reset')));
            }
          },
        ),
      ]),
    );
  }
}
