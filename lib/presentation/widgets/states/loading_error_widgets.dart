import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/app_colors.dart';

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          children: List.generate(5, (index) => _buildShimmerItem()),
        ),
      ),
    );
  }

  Widget _buildShimmerItem() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class ErrorWidgetCustom extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorWidgetCustom({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: AppColors.error),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.textPrimary)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}
