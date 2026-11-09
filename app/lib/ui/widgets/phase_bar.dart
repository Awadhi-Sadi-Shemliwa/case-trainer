import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Brief → Frame → Predict → Data → Explore → Model → Decide → Debrief, current phase highlighted.
class PhaseBar extends StatelessWidget {
  const PhaseBar({super.key, required this.current, required this.phasesInCase});

  final String current;
  final List<String> phasesInCase;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phases = phaseOrder.where(phasesInCase.contains).toList();
    final ci = phases.indexOf(current);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Row(spacing: 3, children: [
        for (var i = 0; i < phases.length; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              decoration: BoxDecoration(
                color: i < ci ? cs.primary : (i == ci ? cs.tertiary : cs.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ]),
      Text(phaseLabels[current]!.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.2, color: cs.tertiary, fontWeight: FontWeight.w700)),
    ]);
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = verified ? cs.primaryContainer : cs.errorContainer;
    final fg = verified ? cs.onPrimaryContainer : cs.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        Icon(verified ? Icons.verified_outlined : Icons.help_outline, size: 14, color: fg),
        Text(verified ? 'VERIFIED' : 'UNVERIFIED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}
