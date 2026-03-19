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
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),

        // BRANCH: AI Assistant
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ai',
              builder: (context, state) => const AIAssistantScreen(),
            ),
          ],
        ),

        // BRANCH: BrowserHub
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hub',
              builder: (context, state) => const BrowserHubScreen(),
            ),
          ],
        ),

        // BRANCH: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
