import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class AppEmptyWidget extends StatelessWidget {
  final String message;
  const AppEmptyWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 60, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
