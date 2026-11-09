// On-device: open P50 at the largest chart (s12, two series x 605 monthly points + recession bands)
// and pinch-zoom / pan it for several seconds inside a traced action.
// Run: flutter drive --profile -d <device> --driver=test_driver/perf_driver.dart --target=integration_test/chart_perf_test.dart
import 'package:case_trainer/app.dart';
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _case = 'p50_yield_curve';
const _chartStep = 's12_chart_spread';

Future<void> _pinch(WidgetTester tester, Offset c, {required bool zoomIn}) async {
  final dir = zoomIn ? 1.0 : -1.0;
  final a = await tester.startGesture(c - Offset(zoomIn ? 30 : 150, 0), pointer: 11);
  final b = await tester.startGesture(c + Offset(zoomIn ? 30 : 150, 0), pointer: 12);
  for (var i = 0; i < 20; i++) {
    await a.moveBy(Offset(-6 * dir, 0));
    await b.moveBy(Offset(6 * dir, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _pan(WidgetTester tester, Offset c, double dx) async {
  final g = await tester.startGesture(c, pointer: 13);
  for (var i = 0; i < 20; i++) {
    await g.moveBy(Offset(dx / 20, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('pinch-zoom and pan the largest chart', (tester) async {
    final content = await ContentDb.openBundled();
    final progress = ProgressDb.inMemory();
    final idx = content.steps(_case).indexWhere((s) => s.id == _chartStep);
    progress.saveCaseState(_case, idx);
    await tester.pumpWidget(ProviderScope(
      overrides: [contentDbProvider.overrideWithValue(content), progressDbProvider.overrideWithValue(progress)],
      child: const CaseTrainerApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(content.caseById(_case).title));
    await tester.pumpAndSettle();

    final chart = find.byKey(const ValueKey('sf_chart'));
    expect(chart, findsOneWidget);
    final c = tester.getCenter(chart);

    await binding.traceAction(() async {
      for (var round = 0; round < 4; round++) {
        await _pinch(tester, c, zoomIn: true);
        await _pan(tester, c, 220);
        await _pan(tester, c, -220);
        await _pinch(tester, c, zoomIn: false);
      }
    }, reportKey: 'chart_zoom_timeline');
  });
}
