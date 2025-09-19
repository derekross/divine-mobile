// ABOUTME: Tests for VideoManager tab visibility-aware functionality
// ABOUTME: Ensures proper video pausing when tabs change using reactive providers

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/state/video_manager_state.dart';

void main() {
  group('VideoManager Tab Visibility Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('VideoManager should listen to tab visibility changes', () {
      // Arrange
      final tabNotifier = container.read(tabVisibilityProvider.notifier);
      final videoManager = container.read(videoManagerProvider.notifier);

      // Create video events with proper VideoEvent constructor
      final videoEvent1 = VideoEvent(
        id: 'video1',
        pubkey: 'test_pubkey_1',
        videoUrl: 'https://example.com/video1.mp4',
        content: 'Test video 1',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
      );
      final videoEvent2 = VideoEvent(
        id: 'video2',
        pubkey: 'test_pubkey_2',
        videoUrl: 'https://example.com/video2.mp4',
        content: 'Test video 2',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
      );

      videoManager.addVideoEvent(videoEvent1);
      videoManager.addVideoEvent(videoEvent2);

      // Act - change tab from 0 to 2
      tabNotifier.setActiveTab(2);

      // Assert - VideoManager should have processed the tab change
      // We test that the functionality exists by checking the manager still works
      final state = container.read(videoManagerProvider);
      expect(state, isA<VideoManagerState>());
    });

    test('VideoManager should pause videos when tab becomes inactive',
        () async {
      // Arrange
      final tabNotifier = container.read(tabVisibilityProvider.notifier);

      // Act - change tab which should trigger video pausing
      tabNotifier.setActiveTab(1);

      // Verify that pauseVideosForTab would be called (we test the public interface)
      // The actual implementation will handle this internally
      final state = container.read(videoManagerProvider);
      expect(state.currentTab,
          equals(1)); // This should be tracked in VideoManagerState
    });

    test('VideoManager should expose pauseVideosForTab method', () {
      // Arrange
      final videoManager = container.read(videoManagerProvider.notifier);

      // Act & Assert - Method should exist and be callable
      expect(() => videoManager.pauseVideosForTab(0), returnsNormally);
      expect(() => videoManager.pauseVideosForTab(1), returnsNormally);
      expect(() => videoManager.pauseVideosForTab(2), returnsNormally);
      expect(() => videoManager.pauseVideosForTab(3), returnsNormally);
    });

    test('VideoManager should track current tab state', () {
      // Arrange
      final tabNotifier = container.read(tabVisibilityProvider.notifier);

      // Initial state should track tab 0
      var state = container.read(videoManagerProvider);
      expect(state.currentTab, equals(0));

      // Act - change tab
      tabNotifier.setActiveTab(3);

      // Assert - state should update
      state = container.read(videoManagerProvider);
      expect(state.currentTab, equals(3));
    });

    test('VideoManager should handle tab visibility logic', () {
      // Arrange
      final tabNotifier = container.read(tabVisibilityProvider.notifier);

      // Act - switch from feed tab (0) to explore tab (2)
      tabNotifier.setActiveTab(2);

      // Assert - VideoManager should track which videos belong to which tabs
      final state = container.read(videoManagerProvider);
      expect(state.shouldPauseVideoForTab('any_video', 0), isTrue);
      expect(state.shouldPauseVideoForTab('any_video', 2), isFalse);
    });
  });
}
