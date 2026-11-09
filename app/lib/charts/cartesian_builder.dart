import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'chart_spec.dart';

/// One plotted value. Carries its series name and unit so the tooltip can show units (spec Prompt 5 §2).
class ChartPt {
  const ChartPt(this.x, this.y, {this.low, this.high, required this.series, this.unit});
  final Object x;
  final double? y;
  final double? low;
  final double? high;
  final String series;
  final String? unit;
}

const _benchmarkDash = <double>[6, 4];
const _palette = [Color(0xFF2563EB), Color(0xFFDC2626), Color(0xFF059669), Color(0xFFD97706), Color(0xFF7C3AED), Color(0xFF0891B2)];

String formatX(Object x, String kind) {
  if (x is DateTime) return '${x.year}-${x.month.toString().padLeft(2, '0')}';
  if (x is double) return formatNum(x);
  return '$x';
}

String formatNum(double v) {
  final a = v.abs();
  final s = a >= 100 ? v.toStringAsFixed(0) : (a >= 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(3));
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Maps a [ChartSpec] to Syncfusion series and axes. Pure function of the spec: no numbers are invented.
class CartesianBuilder {
  CartesianBuilder(this.spec, this.context);
  final ChartSpec spec;
  final BuildContext context;

  Color _c(int i) => _palette[i % _palette.length];

  List<ChartPt> _points(SpecSeries s) =>
      [for (var i = 0; i < s.x.length; i++) ChartPt(s.x[i], s.y[i], series: s.name, unit: s.unit ?? spec.yAxis.unit)];

  List<CartesianSeries<ChartPt, Object>> series() {
    switch (spec.type) {
      case 'line':
        return [for (final (i, s) in spec.series.indexed) _line(s, i)];
      case 'scatter':
        return [
          for (final (i, s) in spec.series.indexed)
            if (s.role == 'data')
              ScatterSeries<ChartPt, Object>(
                name: s.name,
                dataSource: _points(s),
                xValueMapper: (p, _) => p.x,
                yValueMapper: (p, _) => p.y,
                color: _c(i).withValues(alpha: 0.55),
                markerSettings: const MarkerSettings(height: 5, width: 5),
              )
            else
              _line(s, i),
        ];
      case 'bar':
        return [
          for (final (i, s) in spec.series.indexed)
            ColumnSeries<ChartPt, Object>(
                name: s.name, dataSource: _points(s), xValueMapper: (p, _) => p.x, yValueMapper: (p, _) => p.y, color: _c(i)),
        ];
      case 'stacked_bar':
        return [
          for (final (i, s) in spec.series.indexed)
            StackedColumnSeries<ChartPt, Object>(
                name: s.name, dataSource: _points(s), xValueMapper: (p, _) => p.x, yValueMapper: (p, _) => p.y, color: _c(i)),
        ];
      case 'histogram':
        final h = spec.histogram!;
        final centres = [for (var b = 0; b < h.binEdges.length - 1; b++) (h.binEdges[b] + h.binEdges[b + 1]) / 2];
        return [
          for (final (i, e) in h.counts.entries.indexed)
            ColumnSeries<ChartPt, Object>(
              name: e.key,
              dataSource: [for (var b = 0; b < centres.length; b++) ChartPt(centres[b], e.value[b].toDouble(), series: e.key, unit: 'count')],
              xValueMapper: (p, _) => p.x,
              yValueMapper: (p, _) => p.y,
              width: 1.0,
              spacing: 0,
              color: _c(i).withValues(alpha: 0.6),
              borderColor: _c(i),
              borderWidth: 0.5,
            ),
        ];
      case 'box':
        final stats = spec.box!;
        final unit = spec.yAxis.unit;
        return [
          HiloSeries<ChartPt, Object>(
            name: 'Whiskers',
            dataSource: [for (final b in stats) ChartPt(b.category, null, low: b.whiskerLow, high: b.whiskerHigh, series: 'Whiskers', unit: unit)],
            xValueMapper: (p, _) => p.x,
            lowValueMapper: (p, _) => p.low,
            highValueMapper: (p, _) => p.high,
            color: _c(0),
          ),
          RangeColumnSeries<ChartPt, Object>(
            name: 'Middle half (Q1 to Q3)',
            dataSource: [for (final b in stats) ChartPt(b.category, null, low: b.q1, high: b.q3, series: 'Middle half', unit: unit)],
            xValueMapper: (p, _) => p.x,
            lowValueMapper: (p, _) => p.low,
            highValueMapper: (p, _) => p.high,
            color: _c(0).withValues(alpha: 0.35),
            borderColor: _c(0),
            borderWidth: 1,
            width: 0.5,
          ),
          ScatterSeries<ChartPt, Object>(
            name: 'Median',
            dataSource: [for (final b in stats) ChartPt(b.category, b.median, series: 'Median', unit: unit)],
            xValueMapper: (p, _) => p.x,
            yValueMapper: (p, _) => p.y,
            color: _c(1),
            markerSettings: const MarkerSettings(shape: DataMarkerType.horizontalLine, height: 2, width: 22),
          ),
          ScatterSeries<ChartPt, Object>(
            name: 'Outliers',
            dataSource: [for (final b in stats) for (final o in b.outliers) ChartPt(b.category, o, series: 'Outliers', unit: unit)],
            xValueMapper: (p, _) => p.x,
            yValueMapper: (p, _) => p.y,
            color: _c(2),
            markerSettings: const MarkerSettings(height: 5, width: 5),
          ),
        ];
      default:
        throw ChartParseError('${spec.id}: ${spec.type} is not a cartesian chart');
    }
  }

  /// LineSeries, not FastLineSeries: measured on the S21+ while pinch-zooming the 2x605-point chart,
  /// FastLine made no difference (see docs/knowledge/ENVIRONMENT.md "Chart frame times").
  CartesianSeries<ChartPt, Object> _line(SpecSeries s, int i) => LineSeries<ChartPt, Object>(
        name: s.name,
        dataSource: _points(s),
        xValueMapper: (p, _) => p.x,
        yValueMapper: (p, _) => p.y,
        color: _c(i),
        width: s.role == 'data' ? 2 : 1.6,
        dashArray: s.role == 'data' ? null : _benchmarkDash,
        animationDuration: 0,
      );

  List<PlotBand> _bands(String axis) {
    final cs = Theme.of(context).colorScheme;
    return [
      if (axis == 'x')
        for (final r in spec.shadedRegions)
          PlotBand(start: r.start, end: r.end, color: cs.onSurface, opacity: 0.12, borderWidth: 0),
      for (final r in spec.referenceLines.where((r) => r.axis == axis))
        PlotBand(
          start: r.value,
          end: r.value,
          borderWidth: 1.2,
          borderColor: cs.onSurface.withValues(alpha: 0.7),
          dashArray: const [4, 4],
          color: Colors.transparent,
          text: r.label,
          textStyle: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          horizontalTextAlignment: TextAnchor.end,
          verticalTextAlignment: TextAnchor.start,
          shouldRenderAboveSeries: true,
        ),
    ];
  }

  ChartAxis xAxis() {
    final title = AxisTitle(text: spec.xAxis.label, textStyle: const TextStyle(fontSize: 11));
    if (spec.type == 'box' || spec.type == 'bar' || spec.type == 'stacked_bar' || spec.xAxis.kind == 'category') {
      return CategoryAxis(title: title, labelRotation: 0, plotBands: _bands('x'));
    }
    if (spec.xAxis.kind == 'date') {
      return DateTimeAxis(title: title, plotBands: _bands('x'), majorGridLines: const MajorGridLines(width: 0.4));
    }
    return NumericAxis(
      title: title,
      minimum: spec.xAxis.min,
      maximum: spec.xAxis.max,
      plotBands: _bands('x'),
      majorGridLines: const MajorGridLines(width: 0.4),
    );
  }

  ChartAxis yAxis() => NumericAxis(
        title: AxisTitle(text: spec.yAxis.label, textStyle: const TextStyle(fontSize: 11)),
        minimum: spec.yAxis.min,
        maximum: spec.yAxis.max,
        plotBands: _bands('y'),
        majorGridLines: const MajorGridLines(width: 0.4),
      );

  List<CartesianChartAnnotation> annotations() => [
        for (final a in spec.annotations)
          CartesianChartAnnotation(
            widget: Text(a.text, style: const TextStyle(fontSize: 10)),
            coordinateUnit: CoordinateUnit.point,
            x: a.x,
            y: a.y,
          ),
      ];

  /// Tooltip content: series, x and y with units.
  Widget tooltip(ChartPt p) {
    final y = p.low != null && p.high != null
        ? '${formatNum(p.low!)} to ${formatNum(p.high!)}'
        : (p.y == null ? 'no value' : formatNum(p.y!));
    final unit = p.unit == null ? '' : ' ${p.unit}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xEE1F2933), borderRadius: BorderRadius.circular(8)),
      child: Text('${p.series}\n${spec.xAxis.title}: ${formatX(p.x, spec.xAxis.kind)}\n${spec.yAxis.title}: $y$unit',
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
