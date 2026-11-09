import 'dart:convert';

import 'package:case_trainer/charts/chart_spec.dart';
import 'package:case_trainer/charts/chart_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'chart_fixtures.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));
  await tester.pump(); // let the FutureBuilder resolve
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('ChartSpec.parse', () {
    test('every bundled chart parses', () {
      final files = bundledChartFiles();
      expect(files, isNotEmpty);
      for (final e in files.entries) {
        final spec = ChartSpec.parse(jsonDecode(e.value) as Map<String, dynamic>);
        expect(spec.id, e.key);
      }
    });

    test('the recession chart keeps its recessions and zero line', () {
      final spec = ChartSpec.parse(jsonDecode(bundledChartFiles()['p50_spread_recessions']!) as Map<String, dynamic>);
      expect(spec.xAxis.kind, 'date');
      expect(spec.series, hasLength(2));
      expect(spec.shadedRegions, isNotEmpty);
      expect(spec.referenceLines.single.axis, 'y');
      expect(spec.series.first.x.first, isA<DateTime>());
    });

    test('every schema chart type parses from the test fixtures', () {
      final types = {for (final j in fixtureCharts().values) ChartSpec.parse(j).type};
      expect(types, chartTypes);
    });

    Map<String, dynamic> good() => jsonDecode(encode(fixtureCharts()['fx_scatter']!)) as Map<String, dynamic>;

    test('rejects malformed JSON', () {
      expect(() => ChartSpec.parse(good()..['schema_version'] = 2), throwsA(isA<ChartParseError>()));
      expect(() => ChartSpec.parse(good()..['type'] = 'pie'), throwsA(isA<ChartParseError>()));
      final mismatch = good();
      (mismatch['series'] as List).first['y'] = [1];
      expect(() => ChartSpec.parse(mismatch), throwsA(isA<ChartParseError>()));
      final noSeries = good()..['series'] = [];
      expect(() => ChartSpec.parse(noSeries), throwsA(isA<ChartParseError>()));
      final badRole = good();
      (badRole['series'] as List).first['role'] = 'guess';
      expect(() => ChartSpec.parse(badRole), throwsA(isA<ChartParseError>()));
    });
  });

  group('InteractiveChart', () {
    testWidgets('each bundled chart renders interactively with reset + full screen', (tester) async {
      for (final e in bundledChartFiles().entries) {
        await _pump(tester, InteractiveChart(e.key, loader: (_) async => e.value));
        expect(tester.takeException(), isNull, reason: e.key);
        expect(find.byType(SfCartesianChart), findsOneWidget, reason: e.key);
        expect(find.byKey(const ValueKey('chart_reset')), findsOneWidget);
        expect(find.byKey(const ValueKey('chart_fullscreen')), findsOneWidget);
        expect(find.byKey(const ValueKey('chart_fallback_note')), findsNothing);
      }
    });

    testWidgets('legend shows every series name of the recession chart', (tester) async {
      final raw = bundledChartFiles()['p50_spread_recessions']!;
      await _pump(tester, InteractiveChart('p50_spread_recessions', loader: (_) async => raw));
      final spec = ChartSpec.parse(jsonDecode(raw) as Map<String, dynamic>);
      for (final s in spec.series) {
        expect(find.text(s.name), findsOneWidget, reason: s.name);
      }
    });

    testWidgets('every schema chart type renders from fixtures', (tester) async {
      for (final e in fixtureCharts().entries) {
        await _pump(tester, InteractiveChart(e.key, loader: (_) async => encode(e.value)));
        expect(tester.takeException(), isNull, reason: e.key);
        expect(find.byKey(const ValueKey('chart_fallback_note')), findsNothing, reason: e.key);
      }
    });

    testWidgets('broken JSON falls back to the pipeline PNG', (tester) async {
      await _pump(tester, InteractiveChart('p50_roc', loader: (_) async => '{"schema_version": 99}'));
      expect(find.byKey(const ValueKey('chart_fallback_note')), findsOneWidget);
      expect(find.byType(SfCartesianChart), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
