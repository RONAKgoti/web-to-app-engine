import 'package:flutter/material.dart';
import '../router/app_router.dart';
import 'core/theme/app_theme.dart';

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Expert Web-To-Native App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      builder: (context, child) {
        // Essential for ScreenUtil to work correctly in popups/builders
        return child!;
      },
    );
  }
}
