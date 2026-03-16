import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

// ૧. મોડ્યુલ મોડેલ
class SmartModule {
  final String id;
  final String label;
  final IconData icon;
  final String? url;

  SmartModule({required this.id, required this.label, required this.icon, this.url});
}

// ૨. એપ સ્ટેટ (Expert Data Class)
class AppState {
  final List<SmartModule> activeTabs;
  final bool isLoading;
  final String? mainUrl;

  AppState({this.activeTabs = const [], this.isLoading = true, this.mainUrl});

  AppState copyWith({List<SmartModule>? activeTabs, bool? isLoading, String? mainUrl}) {
    return AppState(
      activeTabs: activeTabs ?? this.activeTabs,
      isLoading: isLoading ?? this.isLoading,
      mainUrl: mainUrl ?? this.mainUrl,
    );
  }
}

// ૩. સ્ટેટ નોટિફાયર (Expert Logic Handling)
class AppNotifier extends StateNotifier<AppState> {
  AppNotifier() : super(AppState());

  void setUrl(String url) {
    state = state.copyWith(mainUrl: url);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void updateTabs(List<SmartModule> tabs) {
    state = state.copyWith(activeTabs: tabs);
  }
}

// ૪. પ્રોવાઈડર્સ
final appProvider = StateNotifierProvider<AppNotifier, AppState>((ref) => AppNotifier());
final tabIndexProvider = StateProvider<int>((ref) => 0);
