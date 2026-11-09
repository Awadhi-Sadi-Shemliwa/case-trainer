// Host side of the on-device chart performance run (spec Prompt 5 §4: measure, don't estimate).
// Writes build/chart_zoom_timeline.timeline_summary.json with frame build/raster times.
import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        final timeline = driver.Timeline.fromJson(data['chart_zoom_timeline'] as Map<String, dynamic>);
        final summary = driver.TimelineSummary.summarize(timeline);
        await summary.writeTimelineToFile('chart_zoom_timeline', pretty: true, includeSummary: true);
      },
    );
