import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../grading/claude_client.dart';
import '../../providers.dart';
import '../theme/tokens.dart';
import '../widgets/highlight.dart';
import '../widgets/phase_bar.dart';

/// Progress: how far each case got and how attempts went, plus the finance course.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(progressTickProvider);
    final content = ref.read(contentDbProvider);
    final progress = ref.read(progressDbProvider);
    final course = ref.watch(courseProvider);
    final p = ref.watch(courseProgressProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
          Text('Progress', style: t.displaySmall),
          const SizedBox(height: 20),
          SectionTitle('Cases', icon: Icons.folder_open_rounded),
          const SizedBox(height: 8),
          for (final cs in content.cases()) ...() {
            final steps = content.steps(cs.id);
            final st = progress.caseState(cs.id);
            final sum = progress.caseSummary(cs.id);
            final rate = progress.firstTryRate(cs.id);
            final reached = st == null ? 0 : st.maxIdx + 1;
            return [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: c.sector(cs.domain), width: 5))),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                    Row(spacing: 8, children: [
                      Icon(sectorIcon(cs.domain), size: 18, color: c.inkSoft),
                      Expanded(
                        child: Text('P${cs.number}, ${domainLabels[cs.domain]}',
                            overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: c.inkSoft)),
                      ),
                      Flexible(
                        child: Text(st == null ? 'Not started' : (st.completed ? 'Completed' : 'In progress'),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    Text(cs.title, style: t.titleLarge),
                    StepTicks(total: steps.length, reached: reached, color: c.sector(cs.domain)),
                    Wrap(spacing: 18, runSpacing: 6, children: [
                      _Stat('Steps reached', '$reached of ${steps.length}'),
                      _Stat('Attempts', '${sum.attempts}'),
                      _Stat('Checked steps solved', '${sum.checkedSolved}'),
                      _Stat('Written answers', '${sum.freeTextSaved}'),
                      if (rate != null) _Stat('Right first time', '${(rate * 100).round()}%'),
                    ]),
                  ]),
                ),
              ),
            ];
          }(),
          const SizedBox(height: 16),
          SectionTitle('Finance Foundations', icon: Icons.menu_book_rounded),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                Text('${p.knownTotal} of ${course.terms.length} words known', style: t.titleMedium),
                for (final tier in course.tiers)
                  Row(spacing: 12, children: [
                    SizedBox(width: 110, child: Text(tier.title, style: t.bodyMedium)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: course.termsOfTier(tier.id).isEmpty ? 0 : p.knownIn(tier.id) / course.termsOfTier(tier.id).length,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    Text(p.tierUnlocked(tier.id) ? '${p.knownIn(tier.id)}' : 'locked', style: t.labelMedium),
                  ]),
                Text(
                  '${course.lessons.where((l) => p.lessonPassed(l.id)).length} of ${course.lessons.length} lessons passed, '
                  '${p.due.length} ${p.due.length == 1 ? 'word' : 'words'} due for review',
                  style: t.bodySmall,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      Text(label, style: t.bodySmall),
    ]);
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final cover = ref.watch(showCoverProvider);
    final content = ref.read(contentDbProvider);
    final meta = content.meta();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
          Text('Settings', style: t.displaySmall),
          const SizedBox(height: 20),
          SectionTitle('Appearance', icon: Icons.palette_outlined),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
          SwitchListTile(
            key: const ValueKey('cover_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Show the cover when the app opens'),
            subtitle: const Text('The cover draws the four cases\' real curves and has a Continue button.'),
            value: cover,
            onChanged: (v) => ref.read(showCoverProvider.notifier).set(v),
          ),
          const SizedBox(height: 20),
          const ExaminerSettings(),
          const SizedBox(height: 20),
          SectionTitle('Your data', icon: Icons.storage_rounded),
          const SizedBox(height: 4),
          Text('Everything you type is saved on this phone only.', style: t.bodySmall),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.bad, side: BorderSide(color: c.bad)),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset case progress'),
            onPressed: () async {
              if (!await _confirm(context, 'Reset case progress?',
                  'This deletes every saved answer, draft, attempt and position in the cases. Finance learning is kept. It cannot be undone.',
                  'Reset cases')) {
                return;
              }
              ref.read(progressDbProvider).resetProgress();
              ref.read(progressTickProvider.notifier).bump();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Case progress reset')));
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.bad, side: BorderSide(color: c.bad)),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset finance learning'),
            onPressed: () async {
              if (!await _confirm(context, 'Reset finance learning?',
                  'This forgets which words you know, your lesson scores and your review schedule. Case answers are kept.',
                  'Reset learning')) {
                return;
              }
              ref.read(progressDbProvider).resetLearning();
              ref.read(progressTickProvider.notifier).bump();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Finance learning reset')));
            },
          ),
          const SizedBox(height: 28),
          SectionTitle('Sources', icon: Icons.verified_outlined),
          const SizedBox(height: 4),
          Text('Only sources the pipeline opened and checked are shown, each with a short quote.', style: t.bodySmall),
          for (final s in content.sources())
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.title, style: t.titleSmall),
              subtitle: Text('${s.authorNames}\n"${s.quote}"\n${s.url}', style: t.bodySmall),
              isThreeLine: true,
              trailing: VerifiedBadge(verified: s.verified),
            ),
          const SizedBox(height: 16),
          SectionTitle('Content bundle', icon: Icons.inventory_2_outlined),
          Text('Built ${meta['built_utc']}, schema version ${meta['bundle_schema_version']}', style: t.bodySmall),
          const SizedBox(height: 8),
          Text('Fonts: Archivo and JetBrains Mono, both under the SIL Open Font License.', style: t.bodySmall),
        ]),
      ),
    );
  }
}

/// The Claude examiner's key: the one built into this install, or one pasted here (kept on the phone only).
class ExaminerSettings extends ConsumerStatefulWidget {
  const ExaminerSettings({super.key});

  @override
  ConsumerState<ExaminerSettings> createState() => _ExaminerSettingsState();
}

class _ExaminerSettingsState extends ConsumerState<ExaminerSettings> {
  String? _check;
  bool _checking = false;

  String _tail(String k) => k.length <= 4 ? '' : ' ending ${k.substring(k.length - 4)}';

  Future<void> _paste() async {
    final ctl = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claude API key'),
        content: TextField(
          key: const ValueKey('api_key_field'),
          controller: ctl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: 'Paste the key here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (key == null || key.isEmpty) return;
    ref.read(progressDbProvider).setSetting(apiKeySetting, key);
    setState(() => _check = null);
  }

  Future<void> _test() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    final msg = await ref.read(claudeClientProvider).checkKey();
    if (mounted) {
      setState(() {
        _checking = false;
        _check = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = ref.read(progressDbProvider);
    final pasted = p.setting(apiKeySetting)?.trim() ?? '';
    final key = currentApiKey(p);
    final where = pasted.isNotEmpty
        ? 'Using the key you pasted here${_tail(key)}.'
        : (key.isNotEmpty ? 'Using the key built into this install${_tail(key)}.' : 'No key: answers are saved but not graded.');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      SectionTitle('Examiner', icon: Icons.fact_check_outlined),
      Text('Written answers are graded by Claude ($graderModel); report summaries by $summaryModel. The key stays on this phone.',
          style: t.bodySmall),
      () {
        final u = p.examinerUsage();
        return Text(
          u.calls == 0 ? 'Nothing graded yet.' : '${u.calls} answers graded, about \$${u.cost.toStringAsFixed(2)} of API credit used.',
          key: const ValueKey('api_usage'),
          style: t.bodySmall,
        );
      }(),
      Text(where, key: const ValueKey('api_key_status'), style: t.bodyMedium),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.key_rounded), label: const Text('Paste a new key')),
        if (pasted.isNotEmpty)
          TextButton(
            onPressed: () {
              p.setSetting(apiKeySetting, '');
              setState(() => _check = null);
            },
            child: const Text('Use the built-in key'),
          ),
        OutlinedButton.icon(
          onPressed: key.isEmpty || _checking ? null : _test,
          icon: const Icon(Icons.wifi_tethering_rounded),
          label: Text(_checking ? 'Checking…' : 'Test the connection'),
        ),
      ]),
      if (_check != null) Text(_check!, key: const ValueKey('api_key_check'), style: t.bodyMedium),
    ]);
  }
}
