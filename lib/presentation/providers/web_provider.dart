import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/web_item.dart';

class WebState {
  final List<WebItem> menuItems; // Current page menu
  final List<WebItem> stableMenu; // Fixed app-wide menu
  final bool isLoading;
  final String? currentUrl;
  final String? targetUrl; // URL to navigate to
  final bool isMenuLocked;
  final String? activeMenuLabel;

  WebState({
    this.menuItems = const [],
    this.stableMenu = const [],
    this.isLoading = true,
    this.currentUrl,
    this.targetUrl,
    this.isMenuLocked = false,
    this.activeMenuLabel,
  });

  WebState copyWith({
    List<WebItem>? menuItems,
    List<WebItem>? stableMenu,
    bool? isLoading,
    String? currentUrl,
    String? targetUrl,
    bool? isMenuLocked,
    String? activeMenuLabel,
  }) {
    return WebState(
      menuItems: menuItems ?? this.menuItems,
      stableMenu: stableMenu ?? this.stableMenu,
      isLoading: isLoading ?? this.isLoading,
      currentUrl: currentUrl ?? this.currentUrl,
      targetUrl: targetUrl ?? this.targetUrl,
      isMenuLocked: isMenuLocked ?? this.isMenuLocked,
      activeMenuLabel: activeMenuLabel ?? this.activeMenuLabel,
    );
  }
}

class WebNotifier extends StateNotifier<WebState> {
  WebNotifier() : super(WebState());

  void setUrl(String url) {
    state = state.copyWith(currentUrl: url, targetUrl: null);
  }

  void loadUrl(String url, {String? label}) {
    // If 'HOME' is passed, we indicate a return to index 0/root
    state = state.copyWith(targetUrl: url, activeMenuLabel: label ?? state.activeMenuLabel);
  }

  void setActiveMenuLabel(String label) {
    state = state.copyWith(activeMenuLabel: label);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void updateMenu(List<WebItem> items) {
    if (items.isEmpty) return;

    // 1. Update current page menu
    state = state.copyWith(menuItems: items);

    // 2. STABILIZATION: Lock the menu forever ONLY when a robust menu is harvested
    if (!state.isMenuLocked && items.length >= 3) {
      final bestCandidates = _selectBestPillars(items);
      // Don't lock if we just scraped a cookie banner with 2 text links
      if (bestCandidates.length >= 2) {
        state = state.copyWith(
          stableMenu: bestCandidates,
          isMenuLocked: true, // Permanent lock for stability
        );
      }
    }
  }

  List<WebItem> _selectBestPillars(List<WebItem> items) {
    var pillars = <WebItem>[];
    final seenLabels = <String>{};

    String stemWord(String l) {
      // Basic stemming to treat "kids" & "kid", "infants" & "infant" as same
      var modified = l.toLowerCase().trim();
      if (modified.endsWith('s') && modified.length > 3) {
        modified = modified.substring(0, modified.length - 1);
      }
      return modified.split(RegExp(r'[^a-zA-Z]')).first;
    }

    int priorityScore(String label) {
      final l = label.toLowerCase();
      // Absolute junk (skip instantly)
      if (l.contains('faq') || l.contains('t&c') || l.contains('term') || l.contains('policy') || l.contains('privacy')) return -99;
      if (l.contains('.in') || l.contains('.com') || l.length <= 2) return -99;
      if (l == 'menu' || l == 'more' || l == 'navigation' || l == 'sidebar' || l == 'back' || l == 'close' || l == 'skip') return -99;
      
      // Tier 1: Core App Experiences
      if (l.contains('cart') || l.contains('bag') || l.contains('shop') || l.contains('home')) return 100;
      // Tier 2: E-commerce Categories
      if (l.contains('men') || l.contains('women') || l.contains('kid') || l.contains('boy') || l.contains('girl') || l.contains('infant')) return 80;
      // Tier 3: General Action/Brand
      if (l.contains('profile') || l.contains('account') || l.contains('login') || l.contains('search')) return 60;
      // Tier 4: Corporate/Blog
      if (l.contains('service') || l.contains('contact') || l.contains('about') || l.contains('news') || l.contains('blog') || l.contains('event')) return 40;
      
      return 0;
    }

    // Sort all items strictly by their priority score so best buttons win
    final sortedItems = List<WebItem>.from(items)
      ..sort((a, b) => priorityScore(b.label).compareTo(priorityScore(a.label)));

    for (final item in sortedItems) {
      final score = priorityScore(item.label);
      if (score == -99) continue; // Skip trash
      
      final stem = stemWord(item.label);
      if (seenLabels.add(stem)) {
        pillars.add(item);
        if (pillars.length >= 4) break;
      }
    }

    // Fallback if we couldn't find 4 good items
    if (pillars.length < 4) {
      for (final item in sortedItems) {
        final stem = stemWord(item.label);
        if (seenLabels.add(stem) && priorityScore(item.label) != -99) {
          pillars.add(item);
          if (pillars.length >= 4) break;
        }
      }
    }
    
    // Safety Fallback if the whole website was weird
    if (pillars.isEmpty && items.isNotEmpty) {
       pillars.add(items.first);
    }

    return pillars;
  }

  void resetMenu() {
    state = state.copyWith(stableMenu: [], isMenuLocked: false);
  }
}

final webProvider = StateNotifierProvider<WebNotifier, WebState>((ref) => WebNotifier());
