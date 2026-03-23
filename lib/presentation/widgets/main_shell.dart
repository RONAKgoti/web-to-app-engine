import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/web_provider.dart';

/// ─────────────────────────────────────────────────────────────
/// ULTRA-PREMIUM UNIVERSAL WEB-TO-APP SHELL
/// ─────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int branchIndex; // 0=Home, 1=AI, 2=Hub, 3=Profile
  final String? url;     // null = App branch, non-null = website URL
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.branchIndex,
    this.url,
  });
}

class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webState = ref.watch(webProvider);
    final width = MediaQuery.sizeOf(context).width;

    if (width < 600) {
      return MobileShell(
        navigationShell: navigationShell,
        stableMenu: webState.stableMenu,
        ref: ref,
      );
    } else {
      return _TabletDesktopShell(
        navigationShell: navigationShell,
        stableMenu: webState.stableMenu,
        ref: ref,
      );
    }
  }
}

class MobileShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final List<dynamic> stableMenu;
  final WidgetRef ref;

  const MobileShell({
    super.key,
    required this.navigationShell,
    required this.stableMenu,
    required this.ref,
  });

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  
  // ── Smart Tab highlight logic ───────────────────────────────
  int _calculateSelectedIndex(List<_NavItem> finalItems) {
    final curBranch = widget.navigationShell.currentIndex;
    final webState = widget.ref.read(webProvider);
    final currentUrl = webState.currentUrl;

    // 1. If we are in the WebView branch (Home), check for URL exact match
    if (curBranch == 0 && currentUrl != null) {
      for (int i = 0; i < finalItems.length; i++) {
        final itemUrl = finalItems[i].url;
        if (itemUrl != null) {
          final itKey = itemUrl.toLowerCase().replaceAll(RegExp(r'/$'), '');
          final curKey = currentUrl.toLowerCase().replaceAll(RegExp(r'/$'), '');
          if (itKey == curKey) return i;
          // If current page is home and it's home item
          if (itKey.isEmpty && curKey.isEmpty) return i;
        }
      }
    }

    // 2. Otherwise, match by branch index (for AI, Hub, Profile)
    for (int i = 0; i < finalItems.length; i++) {
        if (finalItems[i].branchIndex == curBranch && finalItems[i].url == null) {
          return i;
        }
    }
    
    // Default to the first item (Home/Index 0)
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // ── NAVIGATION BRAIN: Dynamic Slots ────────────────────────
    // Slot 1: ALWAYS HOME (The Website Root)
    final items = <_NavItem>[
      const _NavItem(
        icon: Icons.home_outlined, 
        activeIcon: Icons.home_rounded, 
        label: 'Home', 
        branchIndex: 0,
        url: '', // Indicator for root
      ),
    ];

    // Slots 2-6: DYNAMICALLY populate from website categories ONLY
    final availableWebItems = widget.stableMenu;
    for (int i = 0; i < availableWebItems.length; i++) {
      if (items.length >= 6) break;
      final webItem = availableWebItems[i];
      // Skip home if it's duplicated in scraped menu
      if (webItem.label.toLowerCase() == 'home') continue;

      items.add(_NavItem(
        icon: _iconForLabel(webItem.label),
        activeIcon: _iconForLabel(webItem.label),
        label: webItem.label,
        branchIndex: 0,
        url: webItem.url,
      ));
    }

    // FALLBACK: Only if website has literally NOTHING, add one app feature
    if (items.length < 2) {
      items.add(const _NavItem(icon: Icons.assistant_outlined, activeIcon: Icons.assistant_rounded, label: 'AI Tools', branchIndex: 1));
      items.add(const _NavItem(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: 'Hub', branchIndex: 2));
    }

    final finalItems = items;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent, // Background translucent
      body: Stack(
        children: [
          // THE PRIMARY CONTENT BENEATH BAR
          Positioned.fill(child: widget.navigationShell),
          
          // THE FLOATING BAR ON TOP (Guaranteed unique)
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildGlassFloatingBar(finalItems),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassFloatingBar(List<_NavItem> finalItems) {
    // Determine bottom padding for safe areas (iPhone notch etc.)
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    
    return Container(
      height: 64 + (bottomInset > 0 ? 12 : 0),
      margin: EdgeInsets.fromLTRB(16, 0, 16, (bottomInset > 0 ? bottomInset : 20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: -10,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(finalItems.length, (index) {
                final item = finalItems[index];
                final isSelected = index == _calculateSelectedIndex(finalItems);
                
                // Sanitized label for UI
                String label = item.label;
                if (label.length > 10) label = label.split(' ').first;
                if (label.length > 10) label = label.substring(0, 9);

                return Expanded(
                  child: _NavTile(
                    item: item,
                    label: label,
                    isSelected: isSelected,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (item.url != null) {
                        widget.navigationShell.goBranch(0);
                        if (item.url!.isEmpty) {
                          widget.ref.read(webProvider.notifier).loadUrl('HOME');
                        } else {
                          widget.ref.read(webProvider.notifier).loadUrl(item.url!);
                        }
                      } else {
                        widget.navigationShell.goBranch(item.branchIndex);
                      }
                    },
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTile({required this.item, required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.all(isSelected ? 6 : 4),
                child: Icon(
                  isSelected ? item.activeIcon : item.icon,
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.4),
                  size: isSelected ? 22 : 20,
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3),
                  fontSize: 8.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (isSelected)
               Container(
                 margin: const EdgeInsets.only(top: 4),
                 width: 4,
                 height: 4,
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
        ],
      ),
    );
  }
}

class _TabletDesktopShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final List<dynamic> stableMenu;
  final WidgetRef ref;

  const _TabletDesktopShell({
    required this.navigationShell, 
    required this.stableMenu,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: const Color(0xFF0F172A),
            unselectedIconTheme: const IconThemeData(color: Colors.white24),
            selectedIconTheme: const IconThemeData(color: Colors.white),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white24),
            selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(index),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text('Home')),
              NavigationRailDestination(icon: Icon(Icons.assistant_outlined), selectedIcon: Icon(Icons.assistant_rounded), label: Text('AI Tools')),
              NavigationRailDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: Text('Hub')),
              NavigationRailDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: Text('Profile')),
            ],
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

IconData _iconForLabel(String label) {
  final text = label.toLowerCase();
  if (text.contains('shop') || text.contains('store')) return Icons.shopping_bag_outlined;
  if (text.contains('cart')) return Icons.shopping_cart_outlined;
  if (text.contains('service')) return Icons.grid_view_outlined;
  if (text.contains('product')) return Icons.inventory_2_outlined;
  if (text.contains('about')) return Icons.info_outline_rounded;
  if (text.contains('contact')) return Icons.support_agent_rounded;
  if (text.contains('blog') || text.contains('news')) return Icons.article_outlined;
  if (text.contains('pricing') || text.contains('plan')) return Icons.payments_outlined;
  return Icons.auto_awesome_mosaic_outlined;
}
