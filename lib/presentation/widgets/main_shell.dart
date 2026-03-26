import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/web_provider.dart';

/// ─────────────────────────────────────────────────────────────
/// ULTRA-PREMIUM NATIVE-FIRST APP SHELL (NO FLOATING, NO OVERLAP)
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

    // 1. ADD FIXED HOME
    final String rawHomeUrl = webState.initialUrl ?? '/';
    navItems.add(_NavItem(
      label: 'Home',
      icon: _iconForLabel('home', isActive: false),
      activeIcon: _iconForLabel('home', isActive: true),
      url: rawHomeUrl,
    ));
    usedNormalizedUrls.add(_normalizeUrl(rawHomeUrl));
    usedLabels.add('home');

    // 2. SCRAPED MENU ITEMS (STABLE SOURCE)
    final displaySource = webState.stableMenu.isNotEmpty ? webState.stableMenu : webState.menuItems;
    for (final webItem in displaySource) {
      final itemNorm = _normalizeUrl(webItem.url);
      final String labelRaw = webItem.label.toLowerCase().trim();
      
      if (labelRaw.contains('home') || labelRaw == 'index') continue;
      if (usedNormalizedUrls.contains(itemNorm) || usedLabels.contains(labelRaw)) continue;
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
      backgroundColor: Colors.white,
      // ─────────────────────────────────────────────────────────────
      // NATIVE HEADER (SMALL LOGO AS REQUESTED)
      // ─────────────────────────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // NANO LOGO
                  Image.asset(
                    'assets/images/logo.png',
                    height: 28, // Reduced size for professionalism
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.auto_awesome, color: Color(0xFF0F172A), size: 24),
                  ),
                  const Spacer(),
                  // Search/Action Icon (Small & Sleek)
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // ─────────────────────────────────────────────────────────────
      // NATIVE BOTTOM NAVIGATION BAR (SMALL & PROFESSIONAL)
      // ─────────────────────────────────────────────────────────────
      bottomNavigationBar: (!isKeyboardVisible && navItems.isNotEmpty)
          ? Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A), // Premium Dark
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Container(
                  height: 60, // Slimmer profile
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: navItems.map((item) {
                      final String normCurrent = _normalizeUrl(webState.currentUrl ?? '');
                      final String normItem = _normalizeUrl(item.url);
                      final String homeNorm = _normalizeUrl(webState.initialUrl ?? '');

                      bool isActive = false;
                      if (item.label == 'Home') {
                        isActive = normCurrent == normItem || normCurrent == homeNorm || normCurrent == "ROOT";
                      } else {
                        isActive = normCurrent == normItem || (normCurrent != "ROOT" && normCurrent.startsWith("$normItem/"));
                      }

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
                                color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                                size: isActive ? 22 : 20, // Nano scaling
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isActive ? Colors.white : Colors.white.withOpacity(0.35),
                                  fontSize: 8.5, // Professional small text
                                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                                  letterSpacing: 0.1,
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
                                    boxShadow: [
                                      BoxShadow(color: Colors.white, blurRadius: 4),
                                    ],
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
            )
          : null,
      body: widget.navigationShell,
    );
  }
}

IconData _iconForLabel(String label, {bool isActive = false}) {
  final text = label.toLowerCase();
  
  if (text.contains('wishlist') || text.contains('favorite')) return isActive ? Icons.favorite_rounded : Icons.favorite_border_rounded;
  if (text.contains('cart') || text.contains('bag') || text.contains('basket')) return isActive ? Icons.shopping_bag_rounded : Icons.shopping_bag_outlined;
  if (text.contains('shop') || text.contains('store')) return isActive ? Icons.store_rounded : Icons.store_outlined;
  if (text.contains('search')) return isActive ? Icons.search_rounded : Icons.search_rounded;
  if (text.contains('account') || text.contains('profile') || text.contains('user') || text.contains('person') || text.contains('you')) return isActive ? Icons.person_rounded : Icons.person_outline_rounded;
  if (text.contains('category') || text.contains('categories') || text.contains('browse') || text.contains('menu')) return isActive ? Icons.dashboard_rounded : Icons.dashboard_outlined;
  if (text.contains('deals') || text.contains('offer') || text.contains('sale')) return isActive ? Icons.local_offer_rounded : Icons.local_offer_outlined;
  if (text.contains('order') || text.contains('history')) return isActive ? Icons.inventory_2_rounded : Icons.inventory_2_outlined;
  if (text.contains('about')) return isActive ? Icons.info_rounded : Icons.info_outline_rounded;
  if (text.contains('service')) return isActive ? Icons.miscellaneous_services_rounded : Icons.miscellaneous_services_outlined;
  if (text.contains('solution') || text.contains('ai')) return isActive ? Icons.psychology_rounded : Icons.psychology_outlined;
  if (text.startsWith('home')) return isActive ? Icons.home_rounded : Icons.home_outlined;
  return isActive ? Icons.auto_awesome_mosaic_rounded : Icons.auto_awesome_mosaic_outlined;
}
