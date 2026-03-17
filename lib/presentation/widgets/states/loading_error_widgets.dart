import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/app_colors.dart';

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[200]!,
        highlightColor: Colors.grey[50]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShimmerBlock(height: 30, width: 200), // Title
            const SizedBox(height: 20),
            _buildShimmerBlock(height: 180, width: double.infinity), // Banner
            const SizedBox(height: 30),
            _buildShimmerBlock(height: 20, width: double.infinity),
            const SizedBox(height: 10),
            _buildShimmerBlock(height: 20, width: double.infinity),
            const SizedBox(height: 10),
            _buildShimmerBlock(height: 20, width: 250),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(child: _buildShimmerBlock(height: 120)),
                const SizedBox(width: 16),
                Expanded(child: _buildShimmerBlock(height: 120)),
              ],
            ),
            const SizedBox(height: 16),
            _buildShimmerBlock(height: 120, width: double.infinity),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerBlock({required double height, double? width}) {
    return Container(
      width: width,
      height: height,
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
