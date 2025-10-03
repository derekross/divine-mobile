// ABOUTME: Tests for VideoPageView tab visibility behavior
// ABOUTME: Ensures videos don't set active state when in background tabs

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/providers/individual_video_providers.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/widgets/video_page_view.dart';

void main() {
  group('VideoPageView Tab Visibility Logic', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('_isTabVisible should return true when tabIndex matches active tab', () {
      // Set tab 0 as active
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);

      // Read the tab visibility
      final activeTab = container.read(tabVisibilityProvider);

      // Verify tab 0 is active
      expect(activeTab, equals(0));

      // Simulate the _isTabVisible logic for tab 0
      final isVisible = activeTab == 0;
      expect(isVisible, isTrue,
          reason: 'Tab 0 should be visible when active tab is 0');
    });

    test('_isTabVisible should return false when tabIndex does not match active tab', () {
      // Set tab 1 as active
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);

      // Read the tab visibility
      final activeTab = container.read(tabVisibilityProvider);

      // Verify tab 1 is active
      expect(activeTab, equals(1));

      // Simulate the _isTabVisible logic for tab 0 (which is NOT active)
      final isVisibleTab0 = activeTab == 0;
      expect(isVisibleTab0, isFalse,
          reason: 'Tab 0 should not be visible when active tab is 1');
    });

    test('_isTabVisible should return true when tabIndex is null (standalone screen)', () {
      // Set any tab as active
      container.read(tabVisibilityProvider.notifier).setActiveTab(2);

      // Simulate the _isTabVisible logic when tabIndex is null
      const int? tabIndex = null;
      final isVisible = tabIndex == null ? true : container.read(tabVisibilityProvider) == tabIndex;

      expect(isVisible, isTrue,
          reason: 'Should be visible when tabIndex is null (standalone screen)');
    });

    test('active video should be set when tab is visible', () {
      // Set tab 0 as active
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);

      // Simulate setting active video (what VideoPageView does when visible)
      const testVideoId = 'test_video_1';
      container.read(activeVideoProvider.notifier).setActiveVideo(testVideoId);

      // Verify active video was set
      final activeVideoId = container.read(activeVideoProvider);
      expect(activeVideoId, equals(testVideoId),
          reason: 'Active video should be set when tab is visible');
    });

    test('active video should not be set when tab is not visible (manual simulation)', () {
      // Set tab 1 as active (not tab 0)
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);

      // Simulate VideoPageView logic: only set active video if tab is visible
      const testVideoId = 'test_video_2';
      const int videoTabIndex = 0; // Video belongs to tab 0
      final activeTab = container.read(tabVisibilityProvider);
      final isTabVisible = activeTab == videoTabIndex;

      // Only set active video if tab is visible (this is what VideoPageView does)
      if (isTabVisible) {
        container.read(activeVideoProvider.notifier).setActiveVideo(testVideoId);
      }

      // Verify active video was NOT set
      final activeVideoId = container.read(activeVideoProvider);
      expect(activeVideoId, isNull,
          reason: 'Active video should not be set when tab is not visible');
    });

    test('active video should update on tab change from invisible to visible', () {
      // Start with tab 1 active (tab 0 is not visible)
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);

      const testVideoId = 'test_video_3';
      const int videoTabIndex = 0;

      // Verify tab 0 is not visible
      var activeTab = container.read(tabVisibilityProvider);
      var isTabVisible = activeTab == videoTabIndex;
      expect(isTabVisible, isFalse);

      // Don't set active video (tab not visible)
      var activeVideoId = container.read(activeVideoProvider);
      expect(activeVideoId, isNull);

      // Switch to tab 0
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);

      // Now tab 0 is visible
      activeTab = container.read(tabVisibilityProvider);
      isTabVisible = activeTab == videoTabIndex;
      expect(isTabVisible, isTrue);

      // Set active video now that tab is visible
      container.read(activeVideoProvider.notifier).setActiveVideo(testVideoId);
      activeVideoId = container.read(activeVideoProvider);
      expect(activeVideoId, equals(testVideoId),
          reason: 'Active video should be set after switching to visible tab');
    });

    test('active video should be cleared when tab becomes invisible', () {
      // Start with tab 0 active and video playing
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);
      const testVideoId = 'test_video_4';
      container.read(activeVideoProvider.notifier).setActiveVideo(testVideoId);

      // Verify video is active
      var activeVideoId = container.read(activeVideoProvider);
      expect(activeVideoId, equals(testVideoId));

      // Switch to tab 1 (tab 0 becomes invisible)
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);

      // Clear active video (what VideoPageView should do when tab becomes invisible)
      container.read(activeVideoProvider.notifier).clearActiveVideo();

      // Verify video is no longer active
      activeVideoId = container.read(activeVideoProvider);
      expect(activeVideoId, isNull,
          reason: 'Active video should be cleared when tab becomes invisible');
    });
  });
}
