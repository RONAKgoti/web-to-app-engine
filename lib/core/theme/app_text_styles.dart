import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  static TextStyle get displayLarge => GoogleFonts.outfit(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineMedium => GoogleFonts.outfit(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyLarge => GoogleFonts.outfit(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelSmall => GoogleFonts.outfit(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}
