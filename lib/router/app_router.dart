import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/ai_assistant_screen.dart';
import '../presentation/screens/browser_hub_screen.dart';
import '../presentation/screens/profile_screen.dart';
import '../presentation/widgets/main_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        // BRANCH: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                child: const HomeScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => 
                  FadeTransition(opacity: animation, child: child),
              ),
            ),
          ],
        ),

        // BRANCH: AI Assistant
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ai',
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                child: const AIAssistantScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => 
                  FadeTransition(opacity: animation, child: child),
              ),
            ),
          ],
        ),

        // BRANCH: BrowserHub
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hub',
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                child: const BrowserHubScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => 
                  FadeTransition(opacity: animation, child: child),
              ),
            ),
          ],
        ),

        // BRANCH: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                child: const ProfileScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => 
                  FadeTransition(opacity: animation, child: child),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
