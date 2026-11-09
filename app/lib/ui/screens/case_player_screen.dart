import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../engine/placeholders.dart';
import '../../providers.dart';
import '../steps/step_common.dart';
import '../steps/step_view.dart';
import '../widgets/phase_bar.dart';

/// One step per screen, phase progress bar, resumes exactly where you left off.
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
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final content = ref.read(contentDbProvider);
    _case = content.caseById(widget.caseId);
    _steps = content.steps(widget.caseId);
    _resolver = Resolver(content.results(widget.caseId), content.captured(widget.caseId));
    final saved = ref.read(progressDbProvider).caseState(widget.caseId);
    _idx = (saved?.stepIdx ?? 0).clamp(0, _steps.length - 1);
    if (saved == null) {
      // Providers can't change during initState: write now, notify listeners after the first frame.
      ref.read(progressDbProvider).saveCaseState(widget.caseId, _idx);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(progressTickProvider.notifier).bump();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _save({bool completed = false}) {
    ref.read(progressDbProvider).saveCaseState(widget.caseId, _idx, completed: completed);
    ref.read(progressTickProvider.notifier).bump();
  }

  void _go(int to) {
    FocusScope.of(context).unfocus();
    setState(() => _idx = to);
    _save();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _finish() {
    _save(completed: true);
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Case completed: ${_case.title}')));
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_idx];
    final last = _idx == _steps.length - 1;
    final scope = StepScope(
      caseInfo: _case,
      step: step,
      resolver: _resolver,
      content: ref.read(contentDbProvider),
      progress: ref.read(progressDbProvider),
      grader: ref.read(graderProvider),
      onProgress: () => ref.read(progressTickProvider.notifier).bump(),
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('P${_case.number} · ${_case.title}', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
          Text('Step ${_idx + 1} of ${_steps.length}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      body: SafeArea(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            PhaseBar(current: step.phase, phasesInCase: {for (final s in _steps) s.phase}.toList()),
            const SizedBox(height: 16),
            KeyedSubtree(key: ValueKey('step_${step.id}'), child: StepView(scope)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(spacing: 12, children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _idx == 0 ? null : () => _go(_idx - 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('next_button'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: last ? _finish : () => _go(_idx + 1),
                icon: Icon(last ? Icons.flag : Icons.arrow_forward),
                label: Text(last ? 'Finish' : 'Next'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
