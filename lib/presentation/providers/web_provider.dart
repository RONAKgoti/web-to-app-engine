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
    
    // Tier 1: Core App Experiences
    if (l.contains('cart') || l.contains('bag') || l.contains('shop') || l.contains('home')) return 100;
    if (l.contains('wishlist') || l.contains('favorite')) return 90;
    
    // Tier 2: E-commerce Categories
    if (l.contains('men') || l.contains('women') || l.contains('kid') || l.contains('boy') || l.contains('girl') || l.contains('infant')) return 80;
    if (l.contains('sale') || l.contains('offer') || l.contains('new') || l.contains('trend')) return 70;
    
    // Tier 3: General Action/Brand
    if (l.contains('profile') || l.contains('account') || l.contains('login') || l.contains('search')) return 60;
    
    // Tier 4: Corporate/Blog
    if (l.contains('service') || l.contains('about') || l.contains('news') || l.contains('blog') || l.contains('event')) return 40;
    
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
    var pillars = <WebItem>[];
    final seenLabels = <String>{};

    String stemWord(String l) {
      var modified = l.toLowerCase().trim();
      if (modified.endsWith('s') && modified.length > 3) {
        modified = modified.substring(0, modified.length - 1);
      }
      return modified.split(RegExp(r'[^a-zA-Z]')).first;
    }

    final sortedItems = List<WebItem>.from(items)
      ..sort((a, b) => _priorityScore(b.label).compareTo(_priorityScore(a.label)));

    for (final item in sortedItems) {
      final score = _priorityScore(item.label);
      if (score == -99) continue; // Skip trash completely
      
      final stem = stemWord(item.label);
      if (seenLabels.add(stem)) {
        pillars.add(item);
        if (pillars.length >= 4) break;
      }
    }

    if (pillars.length < 4) {
      for (final item in sortedItems) {
        final stem = stemWord(item.label);
        if (seenLabels.add(stem) && _priorityScore(item.label) != -99 && _priorityScore(item.label) != -10) {
          pillars.add(item);
          if (pillars.length >= 4) break;
        }
      }
    }
    
    if (pillars.isEmpty && items.isNotEmpty && _priorityScore(items.first.label) != -99) {
       pillars.add(items.first);
    }

    return pillars;
  }

  void resetMenu() {
    state = state.copyWith(stableMenu: [], isMenuLocked: false);
  }
}

final webProvider = StateNotifierProvider<WebNotifier, WebState>((ref) => WebNotifier());
