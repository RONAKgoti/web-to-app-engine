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
    if (url.isEmpty || url == '/' || url == '#') return "ROOT";
    try {
      final uri = Uri.parse(url.toLowerCase().trim());
      String host = uri.host.replaceAll('www.', ''); 
      String path = uri.path;
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      
      if (path.isEmpty || path == '/index.php' || path == '/index.html' || 
          path == '/home' || path == '/default.aspx' || path == '/shop' || path == '/en') {
        path = "ROOT";
      }
      return "$host$path";
    } catch (_) {
      String clean = url.toLowerCase().trim().replaceAll(RegExp(r'/$'), '');
      if (clean == '' || clean == '#' || clean == '/') return "ROOT";
      return clean;
    }
  }

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    final List<_NavItem> navItems = [];
    final Set<String> usedNormalizedUrls = {};
    final Set<String> usedLabels = {};

    // 1. FIXED PRIMARY 'HOME' (The ONLY Home)
    final String rawHomeUrl = webState.initialUrl ?? '/';
    final String homeNorm = _normalizeUrl(rawHomeUrl);
    
    navItems.add(_NavItem(
      label: 'Home',
      icon: _iconForLabel('home', isActive: false),
      activeIcon: _iconForLabel('home', isActive: true),
      url: rawHomeUrl,
    ));
    usedNormalizedUrls.add(homeNorm);
    usedLabels.add('home');
    usedLabels.add('welcome');

    // 2. SCRAPED MENU ITEMS (CLEANED)
    final displaySource = webState.stableMenu.isNotEmpty ? webState.stableMenu : webState.menuItems;
    
    for (final webItem in displaySource) {
      final itemNorm = _normalizeUrl(webItem.url);
      final String labelRaw = webItem.label.toLowerCase().trim();
      
      // SKIP HOME-related elements
      if (labelRaw.contains('home') || labelRaw == 'welcome' || labelRaw == 'index') continue;
      
      // SKIP duplicates
      if (usedNormalizedUrls.contains(itemNorm) || usedLabels.contains(labelRaw)) continue;
      
      // SKIP empty/broken
      if (itemNorm.isEmpty || itemNorm == 'ROOT' || labelRaw.length < 2) continue;

      navItems.add(_NavItem(
        label: webItem.label,
        icon: _iconForLabel(webItem.label, isActive: false),
        activeIcon: _iconForLabel(webItem.label, isActive: true),
        url: webItem.url,
      ));
      
      usedNormalizedUrls.add(itemNorm);
      usedLabels.add(labelRaw);
      if (navItems.length >= 5) break; 
    }

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: widget.navigationShell),
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

    // Premium Floating Logic
    final double verticalMargin = bottomInset > 0 ? bottomInset + 4 : 20;

    return Container(
      height: 68,
      margin: EdgeInsets.fromLTRB(16, 0, 16, verticalMargin),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.92),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: finalItems.length == 1 ? MainAxisAlignment.center : MainAxisAlignment.spaceEvenly,
              children: finalItems.map((item) {
                final String normCurrent = _normalizeUrl(currentUrl ?? '');
                final String normItem = _normalizeUrl(item.url);
                final String homeNorm = _normalizeUrl(webState.initialUrl ?? '');

                bool isActive = false;
                if (item.label == 'Home') {
                  isActive = normCurrent == normItem || normCurrent == homeNorm || normCurrent == "ROOT";
                } else {
                  isActive = normCurrent == normItem || (normCurrent != "ROOT" && normCurrent.startsWith("$normItem/"));
                }
                
                String displayLabel = item.label;
                if (displayLabel.length > 10) displayLabel = displayLabel.split(' ').first;

                return Expanded(
                  child: InkWell(
                    onTap: () {
                      if (!isActive) {
                        HapticFeedback.lightImpact();
                        ref.read(webProvider.notifier).loadUrl(item.url, label: item.label);
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.45),
                          size: isActive ? 24 : 22, 
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                            fontSize: 8.5, 
                            fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
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
  
  if (text.contains('wishlist') || text.contains('favorite')) return isActive ? Icons.favorite_rounded : Icons.favorite_border_rounded;
  if (text.contains('cart') || text.contains('bag') || text.contains('basket')) return isActive ? Icons.shopping_bag_rounded : Icons.shopping_bag_outlined;
  if (text.contains('shop') || text.contains('store')) return isActive ? Icons.store_rounded : Icons.store_outlined;
  if (text.contains('search')) return isActive ? Icons.search_rounded : Icons.search_rounded;
  if (text.contains('account') || text.contains('profile') || text.contains('user') || text.contains('person')) return isActive ? Icons.person_rounded : Icons.person_outline_rounded;
  if (text.contains('category') || text.contains('categories') || text.contains('browse')) return isActive ? Icons.dashboard_rounded : Icons.dashboard_outlined;
  if (text.contains('deals') || text.contains('offer') || text.contains('sale')) return isActive ? Icons.local_offer_rounded : Icons.local_offer_outlined;
  if (text.contains('order') || text.contains('history')) return isActive ? Icons.inventory_2_rounded : Icons.inventory_2_outlined;
  if (text.contains('about')) return isActive ? Icons.info_rounded : Icons.info_outline_rounded;
  if (text.contains('service')) return isActive ? Icons.miscellaneous_services_rounded : Icons.miscellaneous_services_outlined;
  if (text.contains('solution') || text.contains('ai')) return isActive ? Icons.psychology_rounded : Icons.psychology_outlined;
  if (text.contains('home')) return isActive ? Icons.home_rounded : Icons.home_outlined;
  return isActive ? Icons.auto_awesome_mosaic_rounded : Icons.auto_awesome_mosaic_outlined;
}
