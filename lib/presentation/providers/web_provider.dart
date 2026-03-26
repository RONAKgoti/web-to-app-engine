import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/web_item.dart';

class WebState {
  final String? initialUrl; // Root of the current domain
  final List<WebItem> menuItems; // Current page menu
  final List<WebItem> stableMenu; // Fixed app-wide menu
  final bool isLoading;
  final String? currentUrl;
  final String? targetUrl; // URL to navigate to
  final bool isMenuLocked;
  final String? activeMenuLabel;

  WebState({
    this.initialUrl,
    this.menuItems = const [],

    this.stableMenu = const [],
    this.isLoading = true,
    this.currentUrl,
    this.targetUrl,
    this.isMenuLocked = false,
    this.activeMenuLabel,
  });

  WebState copyWith({
    String? initialUrl,
    List<WebItem>? menuItems,
    List<WebItem>? stableMenu,
    bool? isLoading,
    String? currentUrl,
    String? targetUrl,
    bool? isMenuLocked,
    String? activeMenuLabel,
  }) {
    return WebState(
      initialUrl: initialUrl ?? this.initialUrl,
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
    
    // Tier 1: Core App Pillars (Massive Boost for E-commerce)
    if (l.contains('cart') || l.contains('bag') || l.contains('basket')) return 500;
    if (l.contains('profile') || l.contains('account') || l.contains('user') || l.contains('my account')) return 450;
    if (l.contains('category') || l.contains('categories') || l.contains('browse') || l.contains('shop')) return 400;
    if (l.contains('home')) return 350;
    
    // Tier 2: Search & Search Actions
    if (l.contains('search') || l.contains('/q=')) return 300;
    
    // Tier 3: Key Experience Pages
    if (l.contains('wishlist') || l.contains('favorite')) return 200;
    if (l.contains('sale') || l.contains('offer') || l.contains('deal') || l.contains('order')) return 150;
    
    // Tier 4: Major Categories (Variety)
    if (l.contains('men') || l.contains('women') || l.contains('kid')) return 100;
    
    // Tier 5: Everything else (Low priority)
    if (l.length >= 3 && l.length <= 12) return 50;
    
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
    final Set<String> seenPillarTypes = {}; // Force variety: Home, Cart, Profile, Category

    // Sort by priority first
    final sorted = List<WebItem>.from(items)
      ..sort((a, b) => _priorityScore(b.label).compareTo(_priorityScore(a.label)));

    // Phase 1: High-Priority Pillar Hunt (Diversity First)
    for (final item in sorted) {
      final label = item.label.toLowerCase().trim();
      final score = _priorityScore(item.label);
      
      String? type;
      if (score >= 500) type = 'cart';
      else if (score >= 450) type = 'profile';
      else if (score >= 400) type = 'category';
      else if (score >= 350) type = 'home';

      if (type != null && !seenPillarTypes.contains(type) && !seenLabels.contains(label)) {
        seenPillarTypes.add(type);
        seenLabels.add(label);
        pillars.add(item);
        if (pillars.length >= 4) break;
      }
    }

    // Phase 2: Fill remaining slots with high-quality experience items (Wishlist, Search, etc.)
    if (pillars.length < 4) {
      for (final item in sorted) {
        final label = item.label.toLowerCase().trim();
        if (!seenLabels.contains(label) && _priorityScore(label) >= 150) {
          seenLabels.add(label);
          pillars.add(item);
          if (pillars.length >= 4) break;
        }
      }
    }

    // Phase 3: Final fallback to unique sub-items
    if (pillars.length < 4) {
      for (final item in sorted) {
        final label = item.label.toLowerCase().trim();
        if (!seenLabels.contains(label) && _priorityScore(label) >= 0) {
          seenLabels.add(label);
          pillars.add(item);
          if (pillars.length >= 4) break;
        }
      }
    }

    return pillars;
  }




  void resetMenu() {
    state = state.copyWith(stableMenu: [], isMenuLocked: false);
  }
}

final webProvider = StateNotifierProvider<WebNotifier, WebState>((ref) => WebNotifier());
