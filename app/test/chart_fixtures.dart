// Tiny, obviously-fake chart fixtures used ONLY by tests, to exercise every chart type in the schema
// (spec Prompt 2 rule: test fixtures live inside tests; they never reach the app bundle).
import 'dart:convert';
import 'dart:io';

Map<String, dynamic> _base(String id, String type, {String xKind = 'number'}) => {
      'schema_version': 1,
      'id': id,
      'type': type,
      'title': 'Fixture $type',
      'subtitle': null,
      'x_axis': {'title': 'X', 'unit': null, 'kind': xKind, 'min': null, 'max': null},
      'y_axis': {'title': 'Y', 'unit': 'u', 'kind': 'number', 'min': null, 'max': null},
      'series': <Map<String, dynamic>>[],
      'shaded_regions': <Map<String, dynamic>>[],
      'annotations': <Map<String, dynamic>>[],
      'reference_lines': <Map<String, dynamic>>[],
      'histogram': null,
      'box': null,
      'heatmap': null,
      'source_note': 'fixture',
      'result_keys': <String>[],
    };

Map<String, dynamic> _series(String name, List x, List y, {String role = 'data'}) =>
    {'name': name, 'x': x, 'y': y, 'unit': 'u', 'role': role, 'original_points': x.length};

Map<String, Map<String, dynamic>> fixtureCharts() => {
      'fx_line_date': _base('fx_line_date', 'line', xKind: 'date')
        ..['series'] = [_series('a', ['2020-01-01', '2020-02-01', '2020-03-01'], [1.0, null, 2.0])]
        ..['shaded_regions'] = [{'start': '2020-01-01', 'end': '2020-02-01', 'label': 'band'}]
        ..['reference_lines'] = [{'axis': 'y', 'value': 0, 'label': 'zero'}]
        ..['annotations'] = [{'x': '2020-02-01', 'y': 1.5, 'text': 'note'}],
      'fx_scatter': _base('fx_scatter', 'scatter')
        ..['series'] = [_series('dots', [1, 2, 3], [0, 1, 0]), _series('fit', [1, 3], [0.2, 0.8], role: 'fitted')]
        ..['reference_lines'] = [{'axis': 'x', 'value': 2, 'label': 'x line'}],
      'fx_bar': _base('fx_bar', 'bar', xKind: 'category')..['series'] = [_series('s', ['a', 'b'], [1, 2])],
      'fx_stacked': _base('fx_stacked', 'stacked_bar', xKind: 'category')
        ..['series'] = [_series('s1', ['a', 'b'], [1, 2]), _series('s2', ['a', 'b'], [3, 1])],
      'fx_hist': _base('fx_hist', 'histogram')
        ..['histogram'] = {'bin_edges': [0, 1, 2, 3], 'counts': {'g': [1, 4, 2]}},
      'fx_box': _base('fx_box', 'box', xKind: 'category')
        ..['box'] = [
          {'category': 'a', 'whisker_low': 0, 'q1': 1, 'median': 2, 'q3': 3, 'whisker_high': 4, 'outliers': [6]},
          {'category': 'b', 'whisker_low': 1, 'q1': 2, 'median': 2.5, 'q3': 3, 'whisker_high': 5, 'outliers': []},
        ],
      'fx_heat': _base('fx_heat', 'heatmap', xKind: 'category')
        ..['heatmap'] = {'x_categories': ['h1', 'h2'], 'y_categories': ['r1', 'r2'], 'values': [[1, 2], [null, 4]], 'value_unit': 'min'},
    };

/// The real chart files in the bundle (tests run with cwd = app/).
Map<String, String> bundledChartFiles() => {
      for (final f in Directory('assets/content/charts').listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
        f.uri.pathSegments.last.replaceAll('.json', ''): f.readAsStringSync()
    };

String encode(Map<String, dynamic> j) => jsonEncode(j);
