import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

class SmartModule {
  final String id;
  final String label;
  final IconData icon;
  final String? url;

  SmartModule({required this.id, required this.label, required this.icon, this.url});
}

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

final appProvider = StateNotifierProvider<AppNotifier, AppState>((ref) => AppNotifier());
final tabIndexProvider = StateProvider<int>((ref) => 0);
