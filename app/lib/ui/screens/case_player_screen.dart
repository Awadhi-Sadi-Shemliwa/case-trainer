import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../engine/placeholders.dart';
import '../../learn/term_card.dart';
import '../../providers.dart';
import '../steps/step_common.dart';
import '../steps/step_view.dart';
import '../theme/tokens.dart';
import '../widgets/phase_bar.dart';

/// One step per screen, phase strip, resumes exactly where you left off. Unsubmitted input is kept as a draft
/// by each step (ui/steps/draft_saver.dart), so Back and Next never lose typing.
class CasePlayerScreen extends ConsumerStatefulWidget {
  const CasePlayerScreen({super.key, required this.caseId});
  final String caseId;

  @override
  ConsumerState<CasePlayerScreen> createState() => _CasePlayerScreenState();
}

class _CasePlayerScreenState extends ConsumerState<CasePlayerScreen> {
  late final CaseInfo _case;
  late final List<StepData> _steps;
  late final Resolver _resolver;
  late int _idx;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    final content = ref.read(contentDbProvider);
    _case = content.caseById(widget.caseId);
    _steps = content.steps(widget.caseId);
    _resolver = Resolver(content.results(widget.caseId), content.captured(widget.caseId));
    final saved = ref.read(progressDbProvider).caseState(widget.caseId);
    _idx = (saved?.stepIdx ?? 0).clamp(0, _steps.length - 1);
    // Always stamp the visit, so the cover's Continue picks the case you opened last.
    ref.read(progressDbProvider).saveCaseState(widget.caseId, _idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(progressTickProvider.notifier).bump();
    });
  }

  void _save({bool completed = false}) {
    ref.read(progressDbProvider).saveCaseState(widget.caseId, _idx, completed: completed);
    ref.read(progressTickProvider.notifier).bump();
  }

  void _go(int to) {
    FocusScope.of(context).unfocus();
    setState(() {
      _direction = to >= _idx ? 1 : -1;
      _idx = to;
    });
    _save();
  }

  void _finish() {
    _save(completed: true);
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Case completed: ${_case.title}')));
  }

  void _showMap() {
    final maxIdx = ref.read(progressDbProvider).caseState(widget.caseId)?.maxIdx ?? _idx;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        final t = Theme.of(ctx).textTheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text('Steps in this case', style: t.titleLarge),
            Text('Jump to any step you have reached.', style: t.bodySmall),
            const SizedBox(height: 8),
            for (final phase in phaseOrder.where((ph) => _steps.any((s) => s.phase == ph))) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(phaseLabels[phase]!, style: t.labelLarge?.copyWith(color: c.inkSoft)),
              ),
              for (final (i, s) in _steps.indexed.where((e) => e.$2.phase == phase))
                ListTile(
                  dense: true,
                  enabled: i <= maxIdx,
                  selected: i == _idx,
                  selectedTileColor: c.stickyNote,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Text('${i + 1}', style: t.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  title: Text(s.title),
                  subtitle: Text(stepTask(s.type)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _go(i);
                  },
                ),
            ],
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_idx];
    final last = _idx == _steps.length - 1;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final scope = StepScope(
      caseInfo: _case,
      step: step,
      resolver: _resolver,
      content: ref.read(contentDbProvider),
      progress: ref.read(progressDbProvider),
      grader: ref.read(graderProvider),
      onProgress: () => ref.read(progressTickProvider.notifier).bump(),
      linker: _case.domain == 'finance' ? ref.read(termLinkerProvider) : null,
      onTerm: (term) => showTermSheet(context, term),
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(spacing: 10, children: [
          Container(width: 4, height: 34, decoration: BoxDecoration(color: c.sector(_case.domain), borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('P${_case.number}, ${domainLabels[_case.domain]}', style: t.labelMedium?.copyWith(color: c.inkSoft)),
              Text(_case.title, overflow: TextOverflow.ellipsis, style: t.titleMedium),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            key: const ValueKey('step_map'),
            tooltip: 'All steps',
            onPressed: _showMap,
            icon: const Icon(Icons.format_list_numbered_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: PhaseBar(
              current: step.phase,
              phasesInCase: {for (final s in _steps) s.phase}.toList(),
              onTap: _showMap,
              trailing: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  _TaskTag(stepTask(step.type)),
                  Text('Step ${_idx + 1} of ${_steps.length}', style: t.labelMedium?.copyWith(color: c.inkSoft)),
                ],
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey('step_${step.id}');
                final dx = (incoming ? 0.08 : -0.08) * _direction;
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim), child: child),
                );
              },
              child: ListView(
                key: ValueKey('step_${step.id}'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [KeyedSubtree(key: ValueKey('stepview_${step.id}'), child: StepView(scope))],
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(spacing: 12, children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _idx == 0 ? null : () => _go(_idx - 1),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('next_button'),
                onPressed: last ? _finish : () => _go(_idx + 1),
                icon: Icon(last ? Icons.flag_rounded : Icons.arrow_forward_rounded),
                label: Text(last ? 'Finish' : 'Next'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TaskTag extends StatelessWidget {
  const _TaskTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.paperSunken, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.grid)),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
