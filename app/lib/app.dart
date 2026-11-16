import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'learn/learn_screen.dart';
import 'learn/lesson_screen.dart';
import 'learn/term_card.dart';
import 'providers.dart';
import 'ui/screens/case_player_screen.dart';
import 'ui/screens/cover_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/other_screens.dart';
import 'ui/theme/app_theme.dart';

export 'ui/theme/app_theme.dart' show buildTheme;

GoRouter buildRouter({bool showCover = true}) => GoRouter(
      initialLocation: showCover ? '/cover' : '/',
      routes: [
        GoRoute(path: '/cover', builder: (_, _) => const CoverScreen()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => _Shell(shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/learn', builder: (_, _) => const LearnScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
          ],
        ),
        GoRoute(path: '/case/:id', builder: (_, state) => CasePlayerScreen(caseId: state.pathParameters['id']!)),
        GoRoute(path: '/learn/lesson/:id', builder: (_, state) => LessonScreen(lessonId: state.pathParameters['id']!)),
        GoRoute(path: '/learn/review', builder: (_, _) => const ReviewScreen()),
        GoRoute(path: '/learn/glossary', builder: (_, _) => const GlossaryScreen()),
        GoRoute(path: '/learn/term/:id', builder: (_, state) => TermScreen(termId: state.pathParameters['id']!)),
      ],
    );

class _Shell extends StatelessWidget {
  const _Shell(this.shell);
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_open_rounded), label: 'Cases'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Learn'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Progress'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
          ],
        ),
      );
}

class CaseTrainerApp extends ConsumerStatefulWidget {
  const CaseTrainerApp({super.key, this.showCover});

  /// Overrides the Settings choice (tests start on the case list).
  final bool? showCover;

  @override
  ConsumerState<CaseTrainerApp> createState() => _CaseTrainerAppState();
}

class _CaseTrainerAppState extends ConsumerState<CaseTrainerApp> {
  late final GoRouter _router = buildRouter(showCover: widget.showCover ?? ref.read(showCoverProvider));

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Case Trainer',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: _router,
      );
}
