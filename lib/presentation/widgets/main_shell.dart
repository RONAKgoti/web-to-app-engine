import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/web_provider.dart';

/// ─────────────────────────────────────────────────────────────
/// ULTRA-PREMIUM UNIVERSAL WEB-TO-APP SHELL (REPAIRED & RESTORED)
/// ─────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String url;
  
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.url,
  });
}

class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  
  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    // ── Build Dynamic Navigation Items ──
    final List<_NavItem> navItems = [];
    final Set<String> usedLabels = {'home'};

    // 1. ALWAYS ADD HOME AT START (Fixed root)
    navItems.add(_NavItem(
      label: 'Home',
      icon: Icons.home_rounded,
      activeIcon: Icons.home_rounded,
      url: webState.initialUrl ?? '/',
    ));

    // 2. ADD DYNAMIC SCRAPED ITEMS (Max 4 more for total 5)
    for (final webItem in webState.menuItems) {
      final label = webItem.label.trim();
      final labelLower = label.toLowerCase();
      
      if (usedLabels.contains(labelLower)) continue;
      if (webItem.url == webState.initialUrl) continue;

      navItems.add(_NavItem(
        label: label,
        icon: _iconForLabel(label),
        activeIcon: _iconForLabel(label),
        url: webItem.url,
      ));
      
      usedLabels.add(labelLower);
      if (navItems.length >= 5) break; 
    }

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // MAIN WEB CONTENT (WebView)
          Positioned.fill(child: widget.navigationShell),
          
          // FLOATING GLASS BAR (Only if keyboard is hidden)
          if (!isKeyboardVisible && navItems.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildGlassFloatingBar(navItems),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassFloatingBar(List<_NavItem> finalItems) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final webState = ref.watch(webProvider);
    final currentUrl = webState.currentUrl;

    return Container(
      height: 64 + (bottomInset > 0 ? 12 : 0),
      margin: EdgeInsets.fromLTRB(16, 0, 16, (bottomInset > 0 ? bottomInset : 20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.92),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: finalItems.map((item) {
                // Determine Active State (Exact match or Root Home)
                final bool isActive = currentUrl == item.url || (item.label == 'Home' && currentUrl == webState.initialUrl);
                
                String displayLabel = item.label;
                if (displayLabel.length > 10) displayLabel = displayLabel.split(' ').first;
                if (displayLabel.length > 10) displayLabel = displayLabel.substring(0, 9);

                return Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(webProvider.notifier).loadUrl(item.url, label: item.label);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                          size: isActive ? 24 : 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayLabel,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
                            fontSize: 9,
                            fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                          ),
                        ),
                        if (isActive)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconForLabel(String label) {
  final text = label.toLowerCase();
  
  // E-commerce & Retail
  if (text.contains('wishlist') || text.contains('favorite')) return Icons.favorite_border_rounded;
  if (text.contains('cart') || text.contains('bag') || text.contains('basket')) return Icons.shopping_cart_outlined;
  if (text.contains('shop') || text.contains('store')) return Icons.shopping_bag_outlined;
  if (text.contains('search')) return Icons.search_rounded;
  if (text.contains('account') || text.contains('profile') || text.contains('user') || text.contains('person')) return Icons.person_outline_rounded;
  if (text.contains('category') || text.contains('categories') || text.contains('browse')) return Icons.subject_rounded;
  if (text.contains('deals') || text.contains('offer') || text.contains('sale')) return Icons.local_offer_outlined;
  if (text.contains('order') || text.contains('history')) return Icons.local_mall_outlined;

  // Corporate & Digital Solutions (Specific for user site)
  if (text.contains('about')) return Icons.info_outline_rounded;
  if (text.contains('service')) return Icons.miscellaneous_services_outlined;
  if (text.contains('solution') || text.contains('ai')) return Icons.psychology_outlined;
  if (text.contains('salesforce')) return Icons.cloud_done_outlined;
  if (text.contains('contact') || text.contains('mail') || text.contains('reach')) return Icons.alternate_email_rounded;
  if (text.contains('blog') || text.contains('news')) return Icons.article_outlined;
  // High-Tier E-commerce Categories (Specificity)
  if (text.contains('infant') || text.contains('baby') || text.contains('kid')) return Icons.child_care_rounded;
  if (text.contains('bodysuit') || text.contains('romper')) return Icons.checkroom_rounded;
  if (text.contains('clothing') || text.contains('dress') || text.contains('wear')) return Icons.dry_cleaning_outlined;
  if (text.contains('shoe') || text.contains('footwear')) return Icons.directions_walk_rounded;
  if (text.contains('beauty') || text.contains('cosmetic')) return Icons.face_retouching_natural_rounded;
  if (text.contains('home') && text.length > 5) return Icons.home_repair_service_outlined; 
  
  if (text.contains('home')) return Icons.home_rounded;
  
  return Icons.auto_awesome_mosaic_outlined;
}


