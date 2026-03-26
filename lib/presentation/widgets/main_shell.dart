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

  String _normalizeUrl(String url) {
    if (url.isEmpty || url == '/') return "ROOT";
    try {
      final uri = Uri.parse(url.toLowerCase().trim());
      String host = uri.host.replaceAll('www.', ''); // Strip www for comparison
      String path = uri.path;
      
      // Remove trailing slash
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      
      // Clean index/home paths
      if (path.isEmpty || path == '/index.php' || path == '/index.html' || 
          path == '/home' || path == '/default.aspx' || path == '/shop') {
        path = "ROOT";
      }
      
      return "$host$path";
    } catch (_) {
      return url.toLowerCase().trim().replaceAll(RegExp(r'/$'), '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    // ── Build Dynamic Navigation Items ──
    final List<_NavItem> navItems = [];
    final Set<String> usedNormalizedUrls = {};

    // 1. ALWAYS ADD HOME AT START
    final String rawHomeUrl = webState.initialUrl ?? '/';
    final String homeNorm = _normalizeUrl(rawHomeUrl);
    
    navItems.add(_NavItem(
      label: 'Home',
      icon: _iconForLabel('home', isActive: false),
      activeIcon: _iconForLabel('home', isActive: true),
      url: rawHomeUrl,
    ));
    usedNormalizedUrls.add(homeNorm);

    // 2. ADD STABLE ITEMS
    final displaySource = webState.stableMenu.isNotEmpty ? webState.stableMenu : webState.menuItems;
    
    for (final webItem in displaySource) {
      final itemNorm = _normalizeUrl(webItem.url);
      
      // Skip if it matches Home or already added
      if (usedNormalizedUrls.contains(itemNorm)) continue;
      if (webItem.label.toLowerCase() == 'home') continue;
      if (itemNorm.isEmpty || itemNorm == 'localhost' || itemNorm == '') continue;

      navItems.add(_NavItem(
        label: webItem.label,
        icon: _iconForLabel(webItem.label, isActive: false),
        activeIcon: _iconForLabel(webItem.label, isActive: true),
        url: webItem.url,
      ));
      
      usedNormalizedUrls.add(itemNorm);
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

    // Adjusted padding for "niche ui" fix - ensure it sits perfectly
    final double verticalMargin = bottomInset > 0 ? bottomInset : 16;

    return Container(
      height: 68, // Fixed height for consistency
      margin: EdgeInsets.fromLTRB(12, 0, 12, verticalMargin),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.94),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                  spreadRadius: -5,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: finalItems.map((item) {
                // Better Active State Detection
                final String normCurrent = _normalizeUrl(currentUrl ?? '');
                final String normItem = _normalizeUrl(item.url);
                final String homeNorm = _normalizeUrl(webState.initialUrl ?? '');

                bool isActive = false;
                if (item.label == 'Home') {
                  isActive = normCurrent == normItem || normCurrent == homeNorm || normCurrent.isEmpty;
                } else {
                  // If current URL starts with item URL (handling sub-pages)
                  isActive = normCurrent == normItem || normCurrent.startsWith("$normItem/");
                }
                
                String displayLabel = item.label;
                if (displayLabel.length > 10) displayLabel = displayLabel.split(' ').first;
                if (displayLabel.length > 10) displayLabel = displayLabel.substring(0, 9);

                return Expanded(
                  child: InkWell(
                    // Removing highlight to keep it professional
                    highlightColor: Colors.transparent,
                    splashColor: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(30),
                    onTap: () {
                      if (!isActive) {
                        HapticFeedback.lightImpact();
                        ref.read(webProvider.notifier).loadUrl(item.url, label: item.label);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        // Add a subtle glow/hover to active item
                        color: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isActive ? item.activeIcon : item.icon,
                            color: isActive ? Colors.white : Colors.white.withOpacity(0.45),
                            size: isActive ? 24 : 22, 
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                              fontSize: 9, 
                              letterSpacing: -0.2,
                              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                            ),
                          ),
                          // Premium Dot Indicator
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(top: 4),
                            width: isActive ? 4 : 0,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
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
