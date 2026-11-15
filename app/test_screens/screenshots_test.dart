// Design-review screenshots: renders real screens with the real bundled fonts and writes PNGs.
// Not part of `flutter test` (lives outside test/). Run:
//   SCREENSHOT_DIR=<folder> flutter test test_screens/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:case_trainer/app.dart';
import 'package:case_trainer/data/content_db.dart';
import 'package:case_trainer/data/progress_db.dart';
import 'package:case_trainer/providers.dart';
import 'package:case_trainer/ui/widgets/prose.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['SCREENSHOT_DIR'];
final _flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\awadh\dev\flutter';

Future<void> _family(String name, List<String> files) async {
  final loader = FontLoader(name);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  await _family('Archivo', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Archivo-$w.ttf']);
  await _family('ArchivoCondensed', [for (final w in ['SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/ArchivoCondensed-$w.ttf']);
  await _family('JetBrainsMono', ['assets/fonts/JetBrainsMono-Regular.ttf', 'assets/fonts/JetBrainsMono-SemiBold.ttf']);
  await _family('MaterialIcons', ['$_flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
}

void main() {
  if (_out == null) {
    test('screenshots skipped (set SCREENSHOT_DIR)', () {});
    return;
  }
  late ContentDb content;
  setUpAll(() async {
    content = ContentDb.openFile(contentAsset);
    await _loadFonts();
  });

  final key = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.6);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<ProgressDb> pump(WidgetTester tester, {required bool cover, ThemeMode mode = ThemeMode.light, void Function(ProgressDb)? seed}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final progress = ProgressDb.inMemory()..setSetting('theme_mode', mode.name);
    seed?.call(progress);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ProviderScope(
        overrides: [contentDbProvider.overrideWithValue(content), progressDbProvider.overrideWithValue(progress)],
        child: CaseTrainerApp(showCover: cover),
      ),
    ));
    await tester.pump(const Duration(seconds: 3));
    return progress;
  }

  testWidgets('cover light', (tester) async {
    await pump(tester, cover: true, seed: (p) => p.saveCaseState('p50_yield_curve', 8));
    await shot(tester, '01_cover_light');
  });

  testWidgets('cover dark', (tester) async {
    await pump(tester, cover: true, mode: ThemeMode.dark, seed: (p) => p.saveCaseState('p50_yield_curve', 8));
    await shot(tester, '02_cover_dark');
  });

  testWidgets('home', (tester) async {
    await pump(tester, cover: false, seed: (p) => p.saveCaseState('p50_yield_curve', 8));
    await shot(tester, '03_home');
  });

  testWidgets('learn', (tester) async {
    await pump(tester, cover: false);
    await tester.tap(find.text('Learn'));
    await shot(tester, '04_learn');
  });

  testWidgets('lesson word card', (tester) async {
    await pump(tester, cover: false);
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start_next_lesson')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson_next')));
    await shot(tester, '05_lesson_equity');
  });

  testWidgets('quick check', (tester) async {
    await pump(tester, cover: false);
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start_next_lesson')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const ValueKey('lesson_next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('start_check')));
    await tester.pumpAndSettle();
    final first = content.course().termsOf('core_01_money').first;
    await tester.tap(find.byKey(ValueKey('quiz_option_${first.id}')));
    await shot(tester, '06_quick_check');
  });

  testWidgets('p50 brief with word links', (tester) async {
    await pump(tester, cover: false, seed: (p) => p.saveCaseState('p50_yield_curve', 0));
    await tester.tap(find.byKey(const ValueKey('resume_case')));
    await shot(tester, '07_p50_brief');
    final links = [for (final e in find.byType(RichText).evaluate()) ...termLinksIn(e.widget as RichText)];
    links.firstWhere((l) => l.text == 'recession').recognizer.onTap!();
    await shot(tester, '08_term_sheet');
  });

  testWidgets('p34 justification with code', (tester) async {
    final idx = content.steps('p34_home_adv').indexWhere((s) => s.id == 's07_justify_period');
    await pump(tester, cover: false, seed: (p) => p.saveCaseState('p34_home_adv', idx));
    await tester.tap(find.byKey(const ValueKey('resume_case')));
    await shot(tester, '09_p34_code');
  });

  testWidgets('progress', (tester) async {
    await pump(tester, cover: false, seed: (p) => p.saveCaseState('p50_yield_curve', 8));
    await tester.tap(find.text('Progress'));
    await shot(tester, '10_progress');
  });
}
