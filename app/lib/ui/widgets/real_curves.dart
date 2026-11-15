import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../charts/chart_spec.dart';
import '../../charts/chart_view.dart' show ChartJsonLoader, bundledChartJson;

/// One series of a pipeline chart, reduced to points in 0..1 for drawing (scaling is drawing, not computing:
/// every point comes from the case's own chart JSON, parsed with the strict ChartSpec parser).
class CurvePoints {
  const CurvePoints(this.points);
  final List<Offset> points; // x and y in 0..1, y up

  static final Map<String, CurvePoints?> _done = {};

  /// First data series of [chartId], or null if the chart cannot be read (the caller just draws nothing).
  /// Parsed once; later calls return the finished result synchronously.
  static Future<CurvePoints?> load(String chartId, {ChartJsonLoader loader = bundledChartJson}) {
    if (_done.containsKey(chartId)) return SynchronousFuture(_done[chartId]);
    return _parse(chartId, loader).then((v) => _done[chartId] = v);
  }

  static Future<CurvePoints?> _parse(String chartId, ChartJsonLoader loader) async {
        try {
          final spec = ChartSpec.parse(jsonDecode(await loader(chartId)) as Map<String, dynamic>);
          final s = spec.series.firstWhere((s) => s.role == 'data', orElse: () => spec.series.first);
          final xs = <double>[], ys = <double>[];
          for (var i = 0; i < s.x.length; i++) {
            final y = s.y[i];
            if (y == null) continue;
            final x = s.x[i];
            xs.add(switch (x) { DateTime d => d.millisecondsSinceEpoch.toDouble(), double v => v, _ => i.toDouble() });
            ys.add(y);
          }
          if (xs.length < 2) return null;
          final (x0, x1) = (xs.reduce(math.min), xs.reduce(math.max));
          final (y0, y1) = (ys.reduce(math.min), ys.reduce(math.max));
          final dx = x1 - x0 == 0 ? 1.0 : x1 - x0, dy = y1 - y0 == 0 ? 1.0 : y1 - y0;
          return CurvePoints([for (var i = 0; i < xs.length; i++) Offset((xs[i] - x0) / dx, (ys[i] - y0) / dy)]);
        } catch (e) {
          debugPrint('[CaseTrainer] curve $chartId not drawn: $e');
          return null;
        }
  }

  /// Test hook: forget parsed curves.
  static void clearCache() => _done.clear();
}

/// Paints curves into lanes (one per curve) with a 2 px round line and an end marker ringed in the surface
/// colour, per the data-viz mark specs. [progress] runs 0..1 for the draw-on animation.
class CurvesPainter extends CustomPainter {
  CurvesPainter({
    required this.curves,
    required this.colors,
    required this.surface,
    this.progress = 1,
    this.lanes = true,
    this.strokeWidth = 2,
  });

  final List<CurvePoints?> curves;
  final List<Color> colors;
  final Color surface;
  final double progress;
  final bool lanes;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final n = curves.length;
    for (var k = 0; k < n; k++) {
      final curve = curves[k];
      if (curve == null) continue;
      // Each curve starts a little after the previous one: a single orchestrated draw-on.
      final local = ((progress * (1 + 0.35 * (n - 1)) - 0.35 * k)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final laneH = lanes ? size.height / n : size.height;
      final top = lanes ? laneH * k : 0.0;
      final padTop = lanes ? laneH * 0.10 + 22 : laneH * 0.12;
      final padBottom = laneH * 0.10;
      Offset map(Offset p) => Offset(p.dx * size.width, top + padTop + (1 - p.dy) * (laneH - padTop - padBottom));
      final path = Path()..moveTo(map(curve.points.first).dx, map(curve.points.first).dy);
      for (final p in curve.points.skip(1)) {
        final q = map(p);
        path.lineTo(q.dx, q.dy);
      }
      final metric = path.computeMetrics().firstOrNull;
      if (metric == null) continue;
      final shown = metric.extractPath(0, metric.length * local);
      canvas.drawPath(
        shown,
        Paint()
          ..color = colors[k]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      final tip = metric.getTangentForOffset(metric.length * local)?.position;
      if (tip != null) {
        canvas.drawCircle(tip, strokeWidth * 2 + 2, Paint()..color = surface);
        canvas.drawCircle(tip, strokeWidth * 2, Paint()..color = colors[k]);
      }
    }
  }

  @override
  bool shouldRepaint(CurvesPainter old) => old.progress != progress || old.curves != curves || old.colors != colors;
}

/// A small, real sparkline for a case card.
class RealSparkline extends StatelessWidget {
  const RealSparkline(this.chartId, {super.key, required this.color, this.height = 44});

  final String chartId;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: FutureBuilder<CurvePoints?>(
          future: CurvePoints.load(chartId),
          builder: (context, snap) => CustomPaint(
            size: Size.infinite,
            painter: CurvesPainter(
              curves: [snap.data],
              colors: [color],
              surface: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
              lanes: false,
              strokeWidth: 1.6,
            ),
          ),
        ),
      );
}
