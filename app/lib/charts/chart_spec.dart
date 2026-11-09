/// Strict Dart model of the chart JSON written by pipeline/common/charts.py (schema_version 1).
///
/// Parsing never guesses: anything unexpected throws [ChartParseError], and the view then falls back
/// to the pipeline's PNG (spec Prompt 5 §3). The phone never computes chart data; it only draws it.
library;

const chartSchemaVersion = 1;
const chartTypes = {'line', 'scatter', 'histogram', 'box', 'bar', 'stacked_bar', 'heatmap'};

class ChartParseError implements Exception {
  ChartParseError(this.message);
  final String message;
  @override
  String toString() => 'ChartParseError: $message';
}

T _req<T>(Map<String, dynamic> j, String key, String where) {
  final v = j[key];
  if (v is! T) throw ChartParseError('$where.$key: expected $T, got ${v.runtimeType}');
  return v;
}

double? _numOrNull(Object? v, String where) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  throw ChartParseError('$where: expected number or null, got ${v.runtimeType}');
}

class SpecAxis {
  SpecAxis(Map<String, dynamic> j, String where)
      : title = _req<String>(j, 'title', where),
        unit = j['unit'] as String?,
        kind = _req<String>(j, 'kind', where),
        min = _numOrNull(j['min'], '$where.min'),
        max = _numOrNull(j['max'], '$where.max') {
    if (!{'number', 'date', 'category'}.contains(kind)) throw ChartParseError('$where.kind: unknown "$kind"');
  }
  final String title;
  final String? unit;
  final String kind;
  final double? min;
  final double? max;

  String get label => unit == null ? title : '$title ($unit)';
}

class SpecSeries {
  SpecSeries(Map<String, dynamic> j, String xKind, String where)
      : name = _req<String>(j, 'name', where),
        unit = j['unit'] as String?,
        role = _req<String>(j, 'role', where),
        x = _parseX(_req<List>(j, 'x', where), xKind, where),
        y = [for (final (i, v) in _req<List>(j, 'y', where).indexed) _numOrNull(v, '$where.y[$i]')] {
    if (x.length != y.length) throw ChartParseError('$where: x has ${x.length} values, y has ${y.length}');
    if (!{'data', 'fitted', 'benchmark'}.contains(role)) throw ChartParseError('$where.role: unknown "$role"');
  }

  final String name;
  final String? unit;
  final String role;
  final List<Object> x; // DateTime, double or String depending on the x-axis kind
  final List<double?> y;

  static List<Object> _parseX(List raw, String kind, String where) => [
        for (final (i, v) in raw.indexed)
          switch (kind) {
            'date' => v is String
                ? (DateTime.tryParse(v) ?? (throw ChartParseError('$where.x[$i]: bad date "$v"')))
                : throw ChartParseError('$where.x[$i]: date must be a string'),
            'number' => v is num ? v.toDouble() : throw ChartParseError('$where.x[$i]: expected number'),
            _ => '$v',
          }
      ];
}

class ShadedRegion {
  ShadedRegion(this.start, this.end, this.label);
  final Object start;
  final Object end;
  final String label;
}

class ReferenceLine {
  ReferenceLine(this.axis, this.value, this.label);
  final String axis; // 'x' or 'y'
  final Object value;
  final String label;
}

class Annotation {
  Annotation(this.x, this.y, this.text);
  final Object x;
  final double y;
  final String text;
}

class HistogramData {
  HistogramData(this.binEdges, this.counts);
  final List<double> binEdges;
  final Map<String, List<int>> counts;
}

class BoxStat {
  BoxStat(Map<String, dynamic> j, String where)
      : category = _req<String>(j, 'category', where),
        whiskerLow = _numOrNull(j['whisker_low'], where)!,
        q1 = _numOrNull(j['q1'], where)!,
        median = _numOrNull(j['median'], where)!,
        q3 = _numOrNull(j['q3'], where)!,
        whiskerHigh = _numOrNull(j['whisker_high'], where)!,
        outliers = [for (final o in (j['outliers'] as List? ?? const [])) (o as num).toDouble()];
  final String category;
  final double whiskerLow, q1, median, q3, whiskerHigh;
  final List<double> outliers;
}

class HeatmapData {
  HeatmapData(this.xCategories, this.yCategories, this.values, this.valueUnit);
  final List<String> xCategories;
  final List<String> yCategories;
  final List<List<double?>> values;
  final String? valueUnit;
}

class ChartSpec {
  ChartSpec._({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.xAxis,
    required this.yAxis,
    required this.series,
    required this.shadedRegions,
    required this.referenceLines,
    required this.annotations,
    required this.histogram,
    required this.box,
    required this.heatmap,
    required this.sourceNote,
    required this.resultKeys,
  });

  final String id;
  final String type;
  final String title;
  final String? subtitle;
  final SpecAxis xAxis;
  final SpecAxis yAxis;
  final List<SpecSeries> series;
  final List<ShadedRegion> shadedRegions;
  final List<ReferenceLine> referenceLines;
  final List<Annotation> annotations;
  final HistogramData? histogram;
  final List<BoxStat>? box;
  final HeatmapData? heatmap;
  final String sourceNote;
  final List<String> resultKeys;

  /// Total plotted points (for the performance note in docs).
  int get pointCount => series.fold(0, (n, s) => n + s.x.length);

  factory ChartSpec.parse(Map<String, dynamic> j) {
    final version = j['schema_version'];
    if (version != chartSchemaVersion) throw ChartParseError('schema_version $version not supported (expected $chartSchemaVersion)');
    final id = _req<String>(j, 'id', 'chart');
    final type = _req<String>(j, 'type', id);
    if (!chartTypes.contains(type)) throw ChartParseError('$id: unknown chart type "$type"');
    final xAxis = SpecAxis(_req<Map<String, dynamic>>(j, 'x_axis', id), '$id.x_axis');
    final yAxis = SpecAxis(_req<Map<String, dynamic>>(j, 'y_axis', id), '$id.y_axis');

    Object point(Object? v, String where) => switch (xAxis.kind) {
          'date' => DateTime.tryParse('$v') ?? (throw ChartParseError('$where: bad date "$v"')),
          'number' => v is num ? v.toDouble() : throw ChartParseError('$where: expected number'),
          _ => '$v',
        };

    final series = [
      for (final (i, s) in (j['series'] as List? ?? const []).indexed)
        SpecSeries(s as Map<String, dynamic>, xAxis.kind, '$id.series[$i]')
    ];
    final shaded = [
      for (final (i, r) in (j['shaded_regions'] as List? ?? const []).indexed)
        ShadedRegion(point((r as Map)['start'], '$id.shaded[$i].start'), point(r['end'], '$id.shaded[$i].end'), '${r['label']}')
    ];
    final refs = [
      for (final (i, r) in (j['reference_lines'] as List? ?? const []).indexed)
        () {
          final m = r as Map<String, dynamic>;
          final axis = _req<String>(m, 'axis', '$id.ref[$i]');
          if (axis != 'x' && axis != 'y') throw ChartParseError('$id.ref[$i].axis: "$axis"');
          final value = axis == 'x' ? point(m['value'], '$id.ref[$i].value') : (_numOrNull(m['value'], '$id.ref[$i].value') as Object);
          return ReferenceLine(axis, value, '${m['label']}');
        }()
    ];
    final anns = [
      for (final (i, a) in (j['annotations'] as List? ?? const []).indexed)
        Annotation(point((a as Map)['x'], '$id.ann[$i].x'), _numOrNull(a['y'], '$id.ann[$i].y')!, '${a['text']}')
    ];

    HistogramData? hist;
    if (j['histogram'] is Map) {
      final h = j['histogram'] as Map<String, dynamic>;
      final edges = [for (final e in _req<List>(h, 'bin_edges', '$id.histogram')) (e as num).toDouble()];
      final counts = <String, List<int>>{
        for (final e in _req<Map<String, dynamic>>(h, 'counts', '$id.histogram').entries) e.key: [for (final c in e.value as List) (c as num).toInt()]
      };
      for (final e in counts.entries) {
        if (e.value.length != edges.length - 1) throw ChartParseError('$id.histogram.${e.key}: needs ${edges.length - 1} counts');
      }
      hist = HistogramData(edges, counts);
    }
    final box = j['box'] is List ? [for (final (i, b) in (j['box'] as List).indexed) BoxStat(b as Map<String, dynamic>, '$id.box[$i]')] : null;
    HeatmapData? heat;
    if (j['heatmap'] is Map) {
      final h = j['heatmap'] as Map<String, dynamic>;
      final xc = List<String>.from(_req<List>(h, 'x_categories', '$id.heatmap'));
      final yc = List<String>.from(_req<List>(h, 'y_categories', '$id.heatmap'));
      final vals = [
        for (final (r, row) in _req<List>(h, 'values', '$id.heatmap').indexed)
          [for (final (c, v) in (row as List).indexed) _numOrNull(v, '$id.heatmap.values[$r][$c]')]
      ];
      if (vals.length != yc.length || vals.any((r) => r.length != xc.length)) {
        throw ChartParseError('$id.heatmap: values must be ${yc.length} x ${xc.length}');
      }
      heat = HeatmapData(xc, yc, vals, h['value_unit'] as String?);
    }

    switch (type) {
      case 'line' || 'scatter' || 'bar' || 'stacked_bar' when series.isEmpty:
        throw ChartParseError('$id: $type chart needs series');
      case 'histogram' when hist == null:
        throw ChartParseError('$id: histogram chart needs histogram');
      case 'box' when box == null || box.isEmpty:
        throw ChartParseError('$id: box chart needs box stats');
      case 'heatmap' when heat == null:
        throw ChartParseError('$id: heatmap chart needs heatmap');
    }

    return ChartSpec._(
      id: id,
      type: type,
      title: _req<String>(j, 'title', id),
      subtitle: j['subtitle'] as String?,
      xAxis: xAxis,
      yAxis: yAxis,
      series: series,
      shadedRegions: shaded,
      referenceLines: refs,
      annotations: anns,
      histogram: hist,
      box: box,
      heatmap: heat,
      sourceNote: _req<String>(j, 'source_note', id),
      resultKeys: List<String>.from(j['result_keys'] as List? ?? const []),
    );
  }
}
