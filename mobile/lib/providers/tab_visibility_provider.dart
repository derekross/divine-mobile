// ABOUTME: Tab visibility provider that manages active tab state for IndexedStack coordination
// ABOUTME: Provides reactive tab switching and visibility state management for video lifecycle

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tab_visibility_provider.g.dart';

@riverpod
class TabVisibility extends _$TabVisibility {
  @override
  int build() => 0; // Current active tab index

  void setActiveTab(int index) {
    state = index;
  }
}

// Tab-specific visibility providers
@riverpod
bool isFeedTabActive(Ref ref) {
  return ref.watch(tabVisibilityProvider) == 0;
}

@riverpod
bool isExploreTabActive(Ref ref) {
  return ref.watch(tabVisibilityProvider) == 2;
}

@riverpod
bool isProfileTabActive(Ref ref) {
  return ref.watch(tabVisibilityProvider) == 3;
}
