import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/web_item.dart';

class WebState {
  final String? initialUrl; // Root of the current domain
  final List<WebItem> menuItems; // Current page menu
  final List<WebItem> stableMenu; // Fixed app-wide menu
  final bool isLoading;
  final String? currentUrl;
  final String? targetUrl;
  final String? logoUrl;
  final bool isMenuLocked;
  final String? activeMenuLabel;
  final bool hasNativeWebBar;
  
  WebState({
    this.initialUrl,
    this.logoUrl,
    this.menuItems = const [],

    this.stableMenu = const [],
    this.isLoading = true,
    this.currentUrl,
    this.targetUrl,
    this.isMenuLocked = false,
    this.activeMenuLabel,
    this.hasNativeWebBar = false,
  });

  WebState copyWith({
    String? initialUrl,
    List<WebItem>? menuItems,
    List<WebItem>? stableMenu,
    bool? isLoading,
    String? currentUrl,
    String? targetUrl,
    String? logoUrl,
    bool? isMenuLocked,
    String? activeMenuLabel,
    bool? hasNativeWebBar,
  }) {
    return WebState(
      initialUrl: initialUrl ?? this.initialUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      menuItems: menuItems ?? this.menuItems,

      stableMenu: stableMenu ?? this.stableMenu,
      isLoading: isLoading ?? this.isLoading,
      currentUrl: currentUrl ?? this.currentUrl,
      targetUrl: targetUrl ?? this.targetUrl,
      isMenuLocked: isMenuLocked ?? this.isMenuLocked,
      activeMenuLabel: activeMenuLabel ?? this.activeMenuLabel,
      hasNativeWebBar: hasNativeWebBar ?? this.hasNativeWebBar,
    );
  }
}

final _defaultMainItems = [
  WebItem(label: 'Home', url: 'HOME', icon: Icons.home_rounded),
];

class WebNotifier extends StateNotifier<WebState> {
  WebNotifier() : super(WebState(stableMenu: _defaultMainItems));

  void setLogo(String? url) {
    if (url != state.logoUrl) {
      state = state.copyWith(logoUrl: url);
    }
  }

  void setUrl(String url) {
    if (state.initialUrl == null) {
      state = state.copyWith(initialUrl: url, currentUrl: url, targetUrl: null);
    } else {
      state = state.copyWith(currentUrl: url, targetUrl: null);
    }
  }


  void loadUrl(String url, {String? label}) {
    // If 'HOME' is passed, we indicate a return to index 0/root
    state = state.copyWith(targetUrl: url, activeMenuLabel: label ?? state.activeMenuLabel);
  }

  void setActiveMenuLabel(String label) {
    state = state.copyWith(activeMenuLabel: label);
  }

  void setHasNativeWebBar(bool show) {
    if (show != state.hasNativeWebBar) {
      state = state.copyWith(hasNativeWebBar: show);
    }
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  int _priorityScore(String label) {
    final l = label.toLowerCase();
    // Absolute junk (skip instantly)
    if (l.contains('faq') || l.contains('t&c') || l.contains('term') || l.contains('policy') || l.contains('privacy')) return -99;
    if (l.contains('shipping') || l.contains('track') || l.contains('cancellation') || l.contains('return') || l.contains('refund')) return -99;
    if (l.contains('cookie') || l.contains('legal') || l.contains('condition') || l.contains('grievance') || l.contains('disclaimer')) return -99;
    if (l.contains('.in') || l.contains('.com') || l.length <= 2) return -99;
    if (l == 'menu' || l == 'more' || l == 'navigation' || l == 'sidebar' || l == 'back' || l == 'close' || l == 'skip') return -99;
    
    // Low Priority / Generic
    if (l.contains('help') || l.contains('support') || l.contains('contact') || l.contains('investor') || l.contains('career')) return -10;
    
    // Tier 1: Core E-commerce Pillars (Ultra Priority) - Score BOOSTed!
    if (l.contains('cart') || l.contains('bag') || l.contains('basket') || l.contains('checkout')) return 1000;
    if (l.contains('profile') || l.contains('account') || l.contains('user') || l.contains('my account') || l == 'me' || l == 'login') return 950;
    if (l.contains('wishlist') || l.contains('favorite') || l.contains('saved')) return 900;
    if (l.contains('category') || l.contains('categories') || l.contains('explore') || l == 'all') return 850;
    if (l.contains('home') || l == 'home page') return 800;
    if (l.contains('shop') || l.contains('store') || l.contains('browse') || l == 'products') return 750;
    
    // Tier 2: Professional Content (Corporate/Business)
    if (l.contains('service') || l.contains('portfolio') || l.contains('solution')) return 400;
    if (l.contains('about') || l.contains('company')) return 350;
    
    return 0;
  }


  void updateMenu(List<WebItem> items) {
    if (items.isEmpty) return;

    state = state.copyWith(menuItems: items);

    final newCandidates = _selectBestPillars(items);
    
    int scoreMenu(List<WebItem> menu) {
        return menu.fold(0, (sum, item) => sum + _priorityScore(item.label));
    }

    final newScore = scoreMenu(newCandidates);
    final oldScore = scoreMenu(state.stableMenu);

    // Continuous Upgrade Logic: Always upgrade to a better menu! 
    // This prevents locking on garbage (like FAQ and Shipping) if Cart/Profile lazily loads 1 second later!
    if (newScore > oldScore || (state.stableMenu.isEmpty && newCandidates.length >= 2)) {
      state = state.copyWith(
        stableMenu: newCandidates,
        isMenuLocked: newScore >= 180, // Only permanently lock if we found highly premium buttons
      );
    }
  }

  List<WebItem> _selectBestPillars(List<WebItem> items) {
    if (items.isEmpty) return [];
    
    final List<WebItem> pillars = [];
    final Set<String> seenLabels = {};
    final Set<String> seenUrls = {};
    final Set<String> seenPillarTypes = {};

    // Sort by priority first
    final sorted = List<WebItem>.from(items)
      ..sort((a, b) => _priorityScore(b.label).compareTo(_priorityScore(a.label)));

    void addIfUnique(WebItem item, {String? type}) {
      final label = item.label.toLowerCase().trim();
      final urlNorm = item.url.toLowerCase().replaceAll(RegExp(r'/$'), '');
      if (seenLabels.contains(label) || seenUrls.contains(urlNorm)) return;
      
      if (type != null) seenPillarTypes.add(type);
      seenLabels.add(label);
      seenUrls.add(urlNorm);
      pillars.add(item);
    }

    // Phase 1: High-Priority Pillar Hunt (Diversity First)
    for (final item in sorted) {
      final score = _priorityScore(item.label);
      String? type;
      if (score >= 500) type = 'cart';
      else if (score >= 450) type = 'profile';
      else if (score >= 400) type = 'category';
      else if (score >= 350) type = 'home';

      if (type != null && !seenPillarTypes.contains(type)) {
        addIfUnique(item, type: type);
        if (pillars.length >= 4) break;
      }
    }

    // Phase 2: Fill remaining slots with high-quality experience items
    if (pillars.length < 4) {
      for (final item in sorted) {
        if (_priorityScore(item.label) >= 150) {
          addIfUnique(item);
          if (pillars.length >= 4) break;
        }
      }
    }

    // Phase 3: Final fallback to unique sub-items
    if (pillars.length < 4) {
      for (final item in sorted) {
        addIfUnique(item);
        if (pillars.length >= 4) break;
      }
    }

    return pillars;
  }




  void resetMenu() {
    state = state.copyWith(stableMenu: [], isMenuLocked: false);
  }
}

final webProvider = StateNotifierProvider<WebNotifier, WebState>((ref) => WebNotifier());
