import 'package:flutter/material.dart';

import '../steps/step_common.dart';
import 'code_view.dart';

/// "The code behind this step": the real pipeline lines a step talks about (owner request 2026-11-15), so a
/// question such as "the pipeline labels matches as fans, ghost…" can be answered by reading what it did.
/// The pipeline build refuses code that would reveal the answer of a later fill-the-blank or fix-the-bug step.
class CodeContext extends StatelessWidget {
  const CodeContext(this.scope, {super.key, this.showTitle = true});

  final StepScope scope;
  final bool showTitle;

  static const sectionKey = ValueKey('code_context');

  @override
  Widget build(BuildContext context) {
    final refs = scope.step.contextSnippets;
    if (refs.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Column(key: sectionKey, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      if (showTitle)
        Row(spacing: 8, children: [
          Icon(Icons.code_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
          Expanded(child: Text('The code behind this step', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      for (final r in refs)
        CodeView(
          scope.content.snippet(scope.caseId, r.file, r.name) ??
              (throw StateError('snippet ${r.file}:${r.name} missing from bundle')),
          label: '${r.name} in ${r.file}',
        ),
    ]);
  }

  /// Opens the same code in a sheet over the step, e.g. while writing an answer with the keyboard up.
  static Future<void> showSheet(BuildContext context, StepScope scope) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [CodeContext(scope)],
          ),
        ),
      );
}
