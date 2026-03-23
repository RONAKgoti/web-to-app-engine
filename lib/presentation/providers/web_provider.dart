import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/web_item.dart';

class WebState {
  final List<WebItem> menuItems; // Current page menu
  final List<WebItem> stableMenu; // Fixed app-wide menu
  final bool isLoading;
  final String? currentUrl;
  final String? targetUrl; // URL to navigate to
  final bool isMenuLocked;

  WebState({
    this.menuItems = const [],
    this.stableMenu = const [],
    this.isLoading = true,
    this.currentUrl,
    this.targetUrl,
    this.isMenuLocked = false,
  });

  WebState copyWith({
    List<WebItem>? menuItems,
    List<WebItem>? stableMenu,
    bool? isLoading,
    String? currentUrl,
    String? targetUrl,
    bool? isMenuLocked,
  }) {
    return WebState(
      menuItems: menuItems ?? this.menuItems,
      stableMenu: stableMenu ?? this.stableMenu,
      isLoading: isLoading ?? this.isLoading,
      currentUrl: currentUrl ?? this.currentUrl,
      targetUrl: targetUrl ?? this.targetUrl,
      isMenuLocked: isMenuLocked ?? this.isMenuLocked,
    );
  }
}

class WebNotifier extends StateNotifier<WebState> {
  WebNotifier() : super(WebState());

  void setUrl(String url) {
    state = state.copyWith(currentUrl: url, targetUrl: null);
  }

  void loadUrl(String url) {
    // If 'HOME' is passed, we indicate a return to index 0/root
    state = state.copyWith(targetUrl: url);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void updateMenu(List<WebItem> items) {
    if (items.isEmpty) return;

    // 1. Update current page menu
    state = state.copyWith(menuItems: items);

    // 2. STABILIZATION: Lock the menu forever once the first decent menu is found
    if (!state.isMenuLocked && items.length >= 2) {
      final bestCandidates = _selectBestPillars(items);
      state = state.copyWith(
        stableMenu: bestCandidates,
        isMenuLocked: true, // Permanent lock for stability
      );
    }
  }

  List<WebItem> _selectBestPillars(List<WebItem> items) {
    final pillars = <WebItem>[];
    final seenLabels = <String>{};

    bool isPillar(String label) {
      final l = label.toLowerCase();
      // Reject trash labels
      if (l.contains('.in') || l.contains('.com') || l.contains('.org') || l.length < 3) return false;
      if (l == 'menu' || l == 'more' || l == 'navigation' || l == 'sidebar') return false;
      
      return l.contains('shop') || l.contains('store') || l.contains('cart') || 
             l.contains('service') || l.contains('contact') || l.contains('about') ||
             l.contains('product') || l.contains('home');
    }

    // Try to find matching pillars first
    for (final item in items) {
      if (isPillar(item.label) && seenLabels.add(item.label.toLowerCase())) {
        pillars.add(item);
        if (pillars.length >= 4) break;
      }
    }

    // Fill remaining space with whatever looks decent
    if (pillars.length < 2) {
      for (final item in items) {
        final l = item.label.toLowerCase();
        if (l.length >= 3 && !l.contains('.in') && !l.contains('.com')) {
          if (seenLabels.add(l)) {
            pillars.add(item);
            if (pillars.length >= 2) break;
          }
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
