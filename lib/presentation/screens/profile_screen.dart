import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../shared/widgets/native_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.sp)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.r),
        child: Column(
          children: [
            // USER HEADER
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100.r,
                    height: 100.r,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'JD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'John Doe',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'johndoe@example.com',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32.h),

            // SECTIONS
            _buildSection(
              title: 'Account Settings',
              items: [
                _ProfileItem(icon: Icons.person_outline, label: 'Edit Profile'),
                _ProfileItem(icon: Icons.notifications_none, label: 'Notifications'),
                _ProfileItem(icon: Icons.security, label: 'Privacy & Security'),
              ],
            ),
            SizedBox(height: 24.h),
            _buildSection(
              title: 'App Preferences',
              items: [
                _ProfileItem(icon: Icons.language_outlined, label: 'Language'),
                _ProfileItem(icon: Icons.dark_mode_outlined, label: 'Dark Mode'),
                _ProfileItem(icon: Icons.storage_outlined, label: 'Clear Cache'),
              ],
            ),
            SizedBox(height: 24.h),
            _buildSection(
              title: 'Support',
              items: [
                _ProfileItem(icon: Icons.help_outline, label: 'Help Center'),
                _ProfileItem(icon: Icons.info_outline, label: 'About App'),
                _ProfileItem(icon: Icons.logout, label: 'Logout', isDanger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<_ProfileItem> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.w, bottom: 12.h),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94A3B8),
              letterSpacing: 1.2,
            ),
          ),
        ),
        NativeCard(
          padding: 0,
          child: Column(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(
                      item.icon,
                      color: item.isDanger ? Colors.redAccent : const Color(0xFF0F172A),
                      size: 22.sp,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: item.isDanger ? Colors.redAccent : const Color(0xFF0F172A),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                    onTap: () {},
                  ),
                  if (idx < items.length - 1)
                    Divider(height: 1, color: const Color(0xFFF1F5F9), indent: 56.w),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ProfileItem {
  final IconData icon;
  final String label;
  final bool isDanger;
  _ProfileItem({required this.icon, required this.label, this.isDanger = false});
}
