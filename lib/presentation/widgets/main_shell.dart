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
    final Set<String> usedUrls = {};

    // 1. ALWAYS ADD HOME AT START
    final String homeUrl = webState.initialUrl ?? '/';
    navItems.add(_NavItem(
      label: 'Home',
      icon: _iconForLabel('home', isActive: false),
      activeIcon: _iconForLabel('home', isActive: true),
      url: homeUrl,
    ));
    usedUrls.add(homeUrl.toLowerCase().replaceAll(RegExp(r'/$'), ''));

    // 2. ADD STABLE ITEMS
    final displaySource = webState.stableMenu.isNotEmpty ? webState.stableMenu : webState.menuItems;
    
    for (final webItem in displaySource) {
      final urlNorm = webItem.url.toLowerCase().replaceAll(RegExp(r'/$'), '');
      if (usedUrls.contains(urlNorm)) continue;
      if (webItem.label.toLowerCase() == 'home') continue;

      navItems.add(_NavItem(
        label: webItem.label,
        icon: _iconForLabel(webItem.label, isActive: false),
        activeIcon: _iconForLabel(webItem.label, isActive: true),
        url: webItem.url,
      ));
      
      usedUrls.add(urlNorm);
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
                // Determine Active State (Normalized comparison)
                final String normCurrent = currentUrl?.toLowerCase().replaceAll(RegExp(r'/$'), '') ?? '';
                final String normItem = item.url.toLowerCase().replaceAll(RegExp(r'/$'), '');
                final bool isActive = normCurrent == normItem || 
                                     (item.label == 'Home' && normCurrent == webState.initialUrl?.toLowerCase().replaceAll(RegExp(r'/$'), ''));
                
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
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
                          size: isActive ? 22 : 20, 
                        ),
                        const SizedBox(height: 3),
                        Text(
                          displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                            fontSize: 8.5, 
                            fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                          ),
                        ),
                        if (isActive)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 3.5,
                            height: 3.5,
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

IconData _iconForLabel(String label, {bool isActive = false}) {
  final text = label.toLowerCase();
  
  // E-commerce & Retail (Premium Outlined/Filled)
  if (text.contains('wishlist') || text.contains('favorite')) {
    return isActive ? Icons.favorite_rounded : Icons.favorite_border_rounded;
  }
  if (text.contains('cart') || text.contains('bag') || text.contains('basket')) {
    return isActive ? Icons.shopping_bag_rounded : Icons.shopping_bag_outlined;
  }
  if (text.contains('shop') || text.contains('store')) {
    return isActive ? Icons.store_rounded : Icons.store_outlined;
  }
  if (text.contains('search')) {
    return isActive ? Icons.search_rounded : Icons.search_rounded;
  }
  if (text.contains('account') || text.contains('profile') || text.contains('user') || text.contains('person')) {
    return isActive ? Icons.person_rounded : Icons.person_outline_rounded;
  }
  if (text.contains('category') || text.contains('categories') || text.contains('browse')) {
    return isActive ? Icons.dashboard_rounded : Icons.dashboard_outlined;
  }
  if (text.contains('deals') || text.contains('offer') || text.contains('sale')) {
    return isActive ? Icons.local_offer_rounded : Icons.local_offer_outlined;
  }
  if (text.contains('order') || text.contains('history')) {
    return isActive ? Icons.inventory_2_rounded : Icons.inventory_2_outlined;
  }

  // Corporate & Digital Solutions
  if (text.contains('about')) return isActive ? Icons.info_rounded : Icons.info_outline_rounded;
  if (text.contains('service')) return isActive ? Icons.miscellaneous_services_rounded : Icons.miscellaneous_services_outlined;
  if (text.contains('solution') || text.contains('ai')) return isActive ? Icons.psychology_rounded : Icons.psychology_outlined;
  if (text.contains('contact') || text.contains('mail') || text.contains('reach')) return isActive ? Icons.alternate_email_rounded : Icons.alternate_email_rounded;
  
  if (text.contains('home')) return isActive ? Icons.home_rounded : Icons.home_outlined;
  
  return isActive ? Icons.auto_awesome_mosaic_rounded : Icons.auto_awesome_mosaic_outlined;
}
