import 'package:flutter/material.dart';

import 'choice_step.dart';
import 'code_steps.dart';
import 'free_text_step.dart';
import 'simple_steps.dart';
import 'step_common.dart';

/// Picks the widget for a step type (spec Prompt 4 step list plus the owner's challenge-mode types).
class StepView extends StatelessWidget {
  const StepView(this.scope, {super.key});
  final StepScope scope;

  @override
  Widget build(BuildContext context) => switch (scope.step.type) {
        'mcq' || 'multi_select' || 'kpi_builder' || 'code_predict' => ChoiceStep(scope),
        'order_steps' => OrderStep(scope),
        'numeric' => NumericStep(scope),
        'code_read' => CodeReadStep(scope),
        'code_fill' => CodeFillStep(scope),
        'code_fix' => CodeFixStep(scope),
        'concept_card' => ConceptCardStep(scope),
        _ when scope.step.isGraded => FreeTextStep(scope),
        final t => Text('Unsupported step type: $t'),
      };
}
