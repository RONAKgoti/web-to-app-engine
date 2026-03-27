import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../shared/widgets/native_card.dart';

class BrowserHubScreen extends StatelessWidget {
  const BrowserHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('BrowserHub', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.sp)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SEARCH BAR
            NativeCard(
              padding: 4.r,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search or enter URL',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                  suffixIcon: Container(
                    margin: EdgeInsets.all(8.r),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
            SizedBox(height: 32.h),

            // QUICK LINKS
            Text(
              'Quick Links',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            SizedBox(height: 16.h),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16.h,
              crossAxisSpacing: 16.w,
              children: [
                _QuickLink(icon: Icons.language, label: 'Google', color: Colors.blue),
                _QuickLink(icon: Icons.shopping_bag, label: 'Amazon', color: Colors.orange),
                _QuickLink(icon: Icons.play_circle, label: 'YouTube', color: Colors.red),
                _QuickLink(icon: Icons.facebook, label: 'Facebook', color: Colors.blueAccent),
                _QuickLink(icon: Icons.work, label: 'LinkedIn', color: Colors.indigo),
                _QuickLink(icon: Icons.camera_alt, label: 'Instagram', color: Colors.pink),
                _QuickLink(icon: Icons.message, label: 'Twitter', color: Colors.lightBlue),
                _QuickLink(icon: Icons.more_horiz, label: 'More', color: Colors.grey),
              ],
            ),
            SizedBox(height: 32.h),

            // RECENT HISTORY
            Text(
              'Recently Visited',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            SizedBox(height: 16.h),
            NativeCard(
              padding: 0,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                separatorBuilder: (_, __) => Divider(height: 1, color: const Color(0xFFF1F5F9), indent: 56.w),
                itemBuilder: (context, index) {
                  final titles = ['Flutter Documentation', 'Riverpod Guide', 'GoRouter Navigation'];
                  final urls = ['docs.flutter.dev', 'riverpod.dev', 'pub.dev'];
                  return ListTile(
                    leading: Container(
                      padding: EdgeInsets.all(8.r),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: const Icon(Icons.history, color: Color(0xFF64748B), size: 20),
                    ),
                    title: Text(titles[index], style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
                    subtitle: Text(urls[index], style: TextStyle(fontSize: 12.sp, color: const Color(0xFF64748B))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickLink({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 50.r,
          height: 50.r,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Icon(icon, color: color, size: 24.sp),
        ),
        SizedBox(height: 8.h),
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
