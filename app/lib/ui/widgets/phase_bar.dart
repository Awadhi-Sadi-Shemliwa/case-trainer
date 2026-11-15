import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/tokens.dart';

/// Brief → Frame → Predict → Data → Explore → Model → Decide → Debrief, as a segmented strip: done phases in
/// ink, the current one highlighted, the rest on the grid. The current phase is named underneath.
class PhaseBar extends StatelessWidget {
  const PhaseBar({super.key, required this.current, required this.phasesInCase, this.trailing, this.onTap});

  final String current;
  final List<String> phasesInCase;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final phases = phaseOrder.where(phasesInCase.contains).toList();
    final ci = phases.indexOf(current);
    return Semantics(
      label: 'Phase ${phaseLabels[current]}, ${ci + 1} of ${phases.length}',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Row(spacing: 3, children: [
              for (var i = 0; i < phases.length; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i < ci ? c.ink : (i == ci ? c.highlighter : c.grid),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Flexible(
                child: Text(phaseLabels[current]!,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: trailing)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Small ticks, one per step: reached steps in the sector colour, the rest on the grid.
class StepTicks extends StatelessWidget {
  const StepTicks({super.key, required this.total, required this.reached, required this.color});

  final int total;
  final int reached;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$reached of $total steps reached',
      child: Row(spacing: 2, children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(color: i < reached ? color : c.grid, borderRadius: BorderRadius.circular(2)),
            ),
          ),
      ]),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = verified ? c.goodContainer : c.badContainer;
    final fg = verified ? c.good : c.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        Icon(verified ? Icons.verified_outlined : Icons.help_outline, size: 14, color: fg),
        Text(verified ? 'Verified' : 'Unverified', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// What a step asks you to do, in a word or two.
String stepTask(String type) => switch (type) {
      'mcq' => 'Choose one',
      'multi_select' || 'kpi_builder' => 'Choose all that apply',
      'order_steps' => 'Put in order',
      'numeric' => 'Type a number',
      'code_read' => 'Read the code',
      'code_predict' => 'Predict the output',
      'code_fill' => 'Fill the blanks',
      'code_fix' => 'Fix the bug',
      'concept_card' => 'Read',
      'data_expectation' => 'Predict the data',
      'cleaning_justification' => 'Justify the cleaning',
      'plan_challenge' => 'Challenge the plan',
      'decision_threshold' => 'Set the trigger',
      _ => 'Write',
    };
