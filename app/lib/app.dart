import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'ui/screens/case_player_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/other_screens.dart';

const _seed = Color(0xFF0B6B74);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    materialTapTargetSize: MaterialTapTargetSize.padded, // 48dp+ touch targets
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 1),
  );
}

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => _Shell(shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/learn', builder: (_, _) => const LearnScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
          ],
        ),
        GoRoute(path: '/case/:id', builder: (_, state) => CasePlayerScreen(caseId: state.pathParameters['id']!)),
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
            NavigationDestination(icon: Icon(Icons.cases_outlined), selectedIcon: Icon(Icons.cases), label: 'Cases'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
            NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Learn'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

class CaseTrainerApp extends ConsumerStatefulWidget {
  const CaseTrainerApp({super.key});

  @override
  ConsumerState<CaseTrainerApp> createState() => _CaseTrainerAppState();
}

class _CaseTrainerAppState extends ConsumerState<CaseTrainerApp> {
  late final GoRouter _router = buildRouter();

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
