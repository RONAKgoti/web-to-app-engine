import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/web_item.dart';

class WebState {
  final List<WebItem> menuItems;
  final bool isLoading;
  final String? currentUrl;

  WebState({this.menuItems = const [], this.isLoading = true, this.currentUrl});

  WebState copyWith({List<WebItem>? menuItems, bool? isLoading, String? currentUrl}) {
    return WebState(
      menuItems: menuItems ?? this.menuItems,
      isLoading: isLoading ?? this.isLoading,
      currentUrl: currentUrl ?? this.currentUrl,
    );
  }
}

class WebNotifier extends StateNotifier<WebState> {
  WebNotifier() : super(WebState());

  void setUrl(String url) {
    state = state.copyWith(currentUrl: url);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void updateMenu(List<WebItem> items) {
    state = state.copyWith(menuItems: items);
  }
}

final webProvider = StateNotifierProvider<WebNotifier, WebState>((ref) => WebNotifier());
