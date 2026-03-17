import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class NativeCard extends StatelessWidget {
  final Widget child;
  final double? padding;

  const NativeCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(padding ?? 16.0),
        child: child,
      ),
    );
  }
}
