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
      if (l.contains('.in') || l.contains('.com') || l.contains('.org') || l.length <= 2) return false;
      if (l == 'menu' || l == 'more' || l == 'navigation' || l == 'sidebar' || l == 'back' || l == 'close') return false;
      
      final pillarKeywords = [
        // E-commerce & Retail
        'shop', 'store', 'cart', 'product', 'offer', 'deal', 'sale', 'new', 'collection', 'brand',
        'men', 'women', 'kid', 'infant', 'boy', 'girl', 'beauty', 'accessories', 'fashion',
        // Corporate & Business
        'service', 'contact', 'about', 'company', 'career', 'team', 'solution', 'platform', 'feature', 'resource',
        // Portfolio & Freelance
        'portfolio', 'work', 'project', 'resume', 'hire', 'gallery',
        // Blog & Media
        'blog', 'news', 'article', 'story', 'insight', 'editorial',
        // Events & Entertainment
        'event', 'ticket', 'booking', 'schedule', 'show', 'movie',
        // General Utility
        'home', 'login', 'account', 'profile'
      ];
      
      for (final kw in pillarKeywords) {
        if (l.contains(kw)) return true;
      }
      return false;
    }

    // Try to find matching pillars first
    for (final item in items) {
      if (isPillar(item.label) && seenLabels.add(item.label.toLowerCase())) {
        pillars.add(item);
        if (pillars.length >= 4) break;
      }
    }

    // Fill remaining space with whatever looks decent (Only if < 4)
    if (pillars.length < 4) {
      for (final item in items) {
        final l = item.label.toLowerCase();
        if (l.length >= 3 && !l.contains('.in') && !l.contains('.com')) {
          if (seenLabels.add(l)) {
            pillars.add(item);
            if (pillars.length >= 4) break;
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
