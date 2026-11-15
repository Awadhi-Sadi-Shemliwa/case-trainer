import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/content_db.dart';
import 'data/progress_db.dart';
import 'grading/grader.dart';
import 'learn/course.dart';
import 'learn/term_linker.dart';

/// Opened in main() before runApp and injected with overrides (tests inject their own).
final contentDbProvider = Provider<ContentDb>((ref) => throw UnimplementedError('override contentDbProvider'));
final progressDbProvider = Provider<ProgressDb>((ref) => throw UnimplementedError('override progressDbProvider'));
final graderProvider = Provider<Grader>((ref) => const StubGrader());

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

/// Finds glossary words in case text (used in finance cases).
final termLinkerProvider = Provider<TermLinker>((ref) => TermLinker(ref.watch(courseProvider)));

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
