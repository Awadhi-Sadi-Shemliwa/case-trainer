// The cover (owner request: "a cover page for the app") and the notebook theme's colour contrast.
import 'dart:math' as math;

import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/ui/theme/tokens.dart';
import 'package:case_trainer/ui/widgets/real_curves.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final (l1, l2) = (lum(a), lum(b));
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  late ContentDb content;
  setUpAll(() => content = realContent());
  tearDownAll(() => content.close());

  testWidgets('the cover draws every case\'s real curve and opens the cases', (tester) async {
    CurvePoints.clearCache();
    final progress = ProgressDb.inMemory();
    addTearDown(progress.close);
    await pumpApp(tester, content, progress, showCover: true);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('cover_curves')), findsOneWidget);
    expect(find.text('Real data, real decisions.'), findsOneWidget);
    for (final c in content.cases()) {
      expect(c.signatureChart, isNotNull, reason: c.id);
      final curve = await tester.runAsync(() => CurvePoints.load(c.signatureChart!));
      expect(curve, isNotNull, reason: '${c.id}: ${c.signatureChart} parses');
      expect(curve!.points.length, greaterThan(5));
    }
    await tester.tap(find.byKey(const ValueKey('cover_cases')));
    await tester.pumpAndSettle();
    expect(find.text('Cases'), findsWidgets);
  });

  testWidgets('Continue on the cover reopens the last case at its step', (tester) async {
    final progress = ProgressDb.inMemory();
    addTearDown(progress.close);
    final total = content.steps(p50).length;
    progress.saveCaseState(p50, 4);
    await pumpApp(tester, content, progress, showCover: true);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Continue P50, step 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cover_continue')));
    await tester.pumpAndSettle();
    expect(find.text('Step 5 of $total'), findsOneWidget);
  });

  group('contrast (WCAG AA)', () {
    for (final (name, c) in [('light', CaseColors.light), ('dark', CaseColors.dark)]) {
      test('$name: text pairs reach 4.5:1, controls 3:1', () {
        final text = {
          'ink on paper': (c.ink, c.paper),
          'ink on raised paper': (c.ink, c.paperRaised),
          'soft ink on paper': (c.inkSoft, c.paper),
          'soft ink on raised paper': (c.inkSoft, c.paperRaised),
          'number on highlighter': (c.onHighlighter, c.highlighter),
          'ink on sticky note': (c.ink, c.stickyNote),
          'code on code panel': (c.codeFg, c.codeBg),
          'button text on ink': (c.paper, c.ink),
          'ink on good tint': (c.ink, c.goodContainer),
          'ink on bad tint': (c.ink, c.badContainer),
        };
        for (final e in text.entries) {
          expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5), reason: '$name ${e.key}');
        }
        expect(contrast(c.inkMuted, c.paper), greaterThanOrEqualTo(3.0), reason: '$name muted hint text');
        expect(contrast(c.good, c.paper), greaterThanOrEqualTo(3.0), reason: '$name good icon');
        expect(contrast(c.bad, c.paper), greaterThanOrEqualTo(3.0), reason: '$name bad icon');
      });
    }
  });
}
