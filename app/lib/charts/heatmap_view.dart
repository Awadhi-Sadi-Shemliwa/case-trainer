import 'package:flutter/material.dart';

import 'cartesian_builder.dart' show formatNum;
import 'chart_spec.dart';

/// Heatmap as a scrollable grid (Syncfusion's cartesian chart has no heatmap). Tap a cell for its value.
class HeatmapView extends StatelessWidget {
  const HeatmapView(this.spec, {super.key});
  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final h = spec.heatmap!;
    final vals = [for (final r in h.values) for (final v in r) ?v];
    final lo = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a < b ? a : b);
    final hi = vals.isEmpty ? 1.0 : vals.reduce((a, b) => a > b ? a : b);
    final cs = Theme.of(context).colorScheme;
    Color colour(double? v) {
      if (v == null) return cs.surfaceContainerHighest;
      final t = hi == lo ? 0.5 : (v - lo) / (hi - lo);
      return Color.lerp(const Color(0xFFE0F2F1), const Color(0xFF00525A), t)!;
    }

    const cell = 34.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (r, row) in h.values.indexed)
          Row(children: [
            SizedBox(width: 72, child: Text(h.yCategories[r], style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            for (final (c, v) in row.indexed)
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: '${h.yCategories[r]} · ${h.xCategories[c]}: ${v == null ? 'no value' : formatNum(v)} ${h.valueUnit ?? ''}',
                child: Container(width: cell, height: cell, margin: const EdgeInsets.all(1), color: colour(v)),
              ),
          ]),
        Row(children: [
          const SizedBox(width: 72),
          for (final x in h.xCategories)
            SizedBox(
              width: cell + 2,
              child: Text(x, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            ),
        ]),
      ]),
    );
  }
}
