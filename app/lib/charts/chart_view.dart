import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../ui/steps/step_common.dart' show ChartImage;
import 'cartesian_builder.dart';
import 'chart_spec.dart';
import 'heatmap_view.dart';

typedef ChartJsonLoader = Future<String> Function(String chartId);

Future<String> bundledChartJson(String chartId) => rootBundle.loadString('assets/content/charts/$chartId.json');

/// Loads a pipeline chart JSON and renders it interactively; falls back to the PNG (and logs why)
/// if the JSON cannot be loaded or parsed (spec Prompt 5 §3).
class InteractiveChart extends StatefulWidget {
  const InteractiveChart(this.chartId, {super.key, this.loader = bundledChartJson, this.height = 340});

  final String chartId;
  final ChartJsonLoader loader;
  final double height;

  /// Excluded by the no-hard-coded-numbers test: chart labels come from pipeline JSON.
  static const chartKey = ValueKey('chart_view');

  @override
  State<InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<InteractiveChart> {
  late final Future<ChartSpec> _spec = _load();

  Future<ChartSpec> _load() async {
    final raw = await widget.loader(widget.chartId);
    return ChartSpec.parse(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: InteractiveChart.chartKey,
        child: FutureBuilder<ChartSpec>(
          future: _spec,
          builder: (context, snap) {
            if (snap.hasError) {
              debugPrint('[CaseTrainer] chart ${widget.chartId} fallback to PNG: ${snap.error}');
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                ChartImage(widget.chartId),
                Text('Interactive chart unavailable, showing the static image.',
                    key: const ValueKey('chart_fallback_note'),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]);
            }
            if (!snap.hasData) return SizedBox(height: widget.height, child: const Center(child: CircularProgressIndicator()));
            return ChartPanel(snap.data!, height: widget.height);
          },
        ),
      );
}

/// Title, toolbar (reset view, full screen), the chart and its source note.
class ChartPanel extends StatefulWidget {
  const ChartPanel(this.spec, {super.key, this.height = 340, this.fullScreen = false});
  final ChartSpec spec;
  final double height;
  final bool fullScreen;

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel> {
  late final ZoomPanBehavior _zoom = ZoomPanBehavior(enablePinching: true, enablePanning: true, zoomMode: ZoomMode.x, maximumZoomLevel: 0.02);
  late final TooltipBehavior _tooltip;
  late CartesianBuilder _builder;

  ChartSpec get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(
      enable: true,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) => _builder.tooltip(data as ChartPt),
    );
  }

  void _openFullScreen() => Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FullScreenChart(spec),
      ));

  @override
  Widget build(BuildContext context) {
    _builder = CartesianBuilder(spec, context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isHeat = spec.type == 'heatmap';
    final chart = isHeat
        ? HeatmapView(spec)
        : SfCartesianChart(
            key: const ValueKey('sf_chart'),
            primaryXAxis: _builder.xAxis(),
            primaryYAxis: _builder.yAxis(),
            series: _builder.series(),
            annotations: _builder.annotations(),
            zoomPanBehavior: _zoom,
            tooltipBehavior: _tooltip,
            legend: const Legend(isVisible: true, position: LegendPosition.bottom, toggleSeriesVisibility: true, overflowMode: LegendItemOverflowMode.wrap),
            plotAreaBorderWidth: 0.6,
          );
    final shadedLabel = spec.shadedRegions.isEmpty ? null : spec.shadedRegions.first.label;

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (spec.subtitle != null) Text(spec.subtitle!, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        if (!isHeat)
          IconButton(
            key: const ValueKey('chart_reset'),
            tooltip: 'Reset view',
            icon: const Icon(Icons.restart_alt),
            onPressed: _zoom.reset,
          ),
        if (!widget.fullScreen)
          IconButton(
            key: const ValueKey('chart_fullscreen'),
            tooltip: 'Full screen',
            icon: const Icon(Icons.fullscreen),
            onPressed: _openFullScreen,
          ),
      ]),
      // Heatmaps size to their rows (a fixed box overflows with many categories); full screen scrolls vertically.
      if (widget.fullScreen)
        Expanded(child: isHeat ? SingleChildScrollView(child: chart) : chart)
      else if (isHeat)
        chart
      else
        SizedBox(height: widget.height, child: chart),
      Wrap(spacing: 12, children: [
        if (shadedLabel != null) Text('Grey bands: $shadedLabel', style: t.labelSmall),
        if (!isHeat) Text('Pinch to zoom · drag to pan · tap a point · tap legend to hide a series', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
      Text(spec.sourceNote, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
    ]);

    if (widget.fullScreen) return body;
    return Card.outlined(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 4, 8), child: body));
  }
}

/// Full-screen landscape view of the same chart with the same interactions.
class FullScreenChart extends StatefulWidget {
  const FullScreenChart(this.spec, {super.key});
  final ChartSpec spec;

  @override
  State<FullScreenChart> createState() => _FullScreenChartState();
}

class _FullScreenChartState extends State<FullScreenChart> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []); // back to the app default
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 4, 48, 4), child: ChartPanel(widget.spec, fullScreen: true)),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                key: const ValueKey('chart_close'),
                tooltip: 'Close full screen',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ]),
        ),
      );
}
