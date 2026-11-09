import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/content_db.dart';
import 'data/progress_db.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sw = Stopwatch()..start();
  final content = await ContentDb.openBundled();
  final progress = await ProgressDb.open();
  debugPrint('[CaseTrainer] databases ready in ${sw.elapsedMilliseconds} ms');
  runApp(ProviderScope(
    overrides: [
      contentDbProvider.overrideWithValue(content),
      progressDbProvider.overrideWithValue(progress),
    ],
    child: const CaseTrainerApp(),
  ));
}
