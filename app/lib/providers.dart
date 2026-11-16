import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/content_db.dart';
import 'data/progress_db.dart';
import 'grading/claude_client.dart';
import 'grading/claude_grader.dart';
import 'grading/grader.dart';
import 'learn/course.dart';
import 'learn/term_linker.dart';

/// Opened in main() before runApp and injected with overrides (tests inject their own).
final contentDbProvider = Provider<ContentDb>((ref) => throw UnimplementedError('override contentDbProvider'));
final progressDbProvider = Provider<ProgressDb>((ref) => throw UnimplementedError('override progressDbProvider'));

/// Settings key under which a pasted Claude API key is stored on the phone (overrides the built-in one).
const apiKeySetting = 'anthropic_api_key';

/// The key the examiner uses: Settings first, then the one baked in at build time (never in git).
String currentApiKey(ProgressDb p) {
  final s = p.setting(apiKeySetting)?.trim() ?? '';
  return s.isNotEmpty ? s : builtInApiKey;
}

final claudeClientProvider = Provider<ClaudeClient>((ref) {
  final progress = ref.watch(progressDbProvider);
  return ClaudeClient(apiKey: () => currentApiKey(progress));
});

/// The Claude examiner (owner decision 2026-11-16). Tests override this with a fake.
final graderProvider = Provider<Grader>((ref) => ClaudeGrader(
      ref.watch(claudeClientProvider),
      loadChart: (id) async {
        try {
          return jsonDecode(await rootBundle.loadString('assets/content/charts/$id.json')) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      },
    ));

/// Bumped after every progress write so screens that summarise progress rebuild.
class ProgressTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final progressTickProvider = NotifierProvider<ProgressTick, int>(ProgressTick.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final v = ref.read(progressDbProvider).setting('theme_mode');
    return ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
  }

  void set(ThemeMode mode) {
    ref.read(progressDbProvider).setSetting('theme_mode', mode.name);
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// The finance course from the bundle (fixed for the app's lifetime).
final courseProvider = Provider<Course>((ref) => ref.watch(contentDbProvider).course());

/// Finds every glossary word in case text (used in finance cases).
final termLinkerProvider = Provider<TermLinker>((ref) => TermLinker(ref.watch(courseProvider)));

/// Finds only the data-science measures (AUC, p-value, median...) in case text: used in the aviation, F1 and
/// football cases, where finance words would be out of place (owner request 2026-11-16).
final measureLinkerProvider = Provider<TermLinker>((ref) {
  final course = ref.watch(courseProvider);
  return TermLinker(course, where: course.isMeasure);
});

/// Learning state; recomputed whenever progress is written.
final courseProgressProvider = Provider<CourseProgress>((ref) {
  ref.watch(progressTickProvider);
  return CourseProgress(ref.watch(courseProvider), ref.watch(progressDbProvider));
});

/// Whether the cover opens on launch (Settings toggle; default on).
class ShowCoverNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(progressDbProvider).setting('show_cover') != 'false';

  void set(bool value) {
    ref.read(progressDbProvider).setSetting('show_cover', value ? 'true' : 'false');
    state = value;
  }
}

final showCoverProvider = NotifierProvider<ShowCoverNotifier, bool>(ShowCoverNotifier.new);
