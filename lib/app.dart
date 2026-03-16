import 'package:flutter/material.dart';
import '../router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Expert Web-To-Native App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.outfitTextTheme(),
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.appBarBg,
          elevation: 0,
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
