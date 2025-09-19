// ABOUTME: Mock VideoManagerNotifier for tests that bypasses actual video controller creation
// ABOUTME: Provides a simplified implementation that doesn't require real video files

import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/state/video_manager_state.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/models/video_state.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'test_video_controller.dart';

/// Mock implementation of VideoManager for tests
class MockVideoManager extends VideoManager {
  @override
  Future<void> preloadVideo(String videoId,
      {PreloadPriority priority = PreloadPriority.nearby}) async {
    final currentState = state;

    // For testing, we'll assume the video exists if we're asked to preload it
    // In a real implementation, this would check the _videoEvents map
    final videoEvent = VideoEvent(
      id: videoId,
      pubkey: 'test-pubkey',
      createdAt: 1234567890,
      content: 'Test video',
      timestamp: DateTime.now(),
      videoUrl: 'https://example.com/test.mp4',
    );

    // Check if already loaded
    if (currentState.hasController(videoId)) {
      return;
    }

    // Create test controller instead of real one
    final controller = TestVideoPlayerController(videoEvent.videoUrl ?? '');

    // Create states
    final videoState = VideoState(
      event: videoEvent,
      loadingState: VideoLoadingState.loading,
    );

    final controllerState = VideoControllerState(
      videoId: videoId,
      controller: controller,
      state: videoState,
      createdAt: DateTime.now(),
      priority: priority,
    );

    // Add to state
    state = currentState.copyWith(
      controllers: {...currentState.controllers, videoId: controllerState},
    );

    // Simulate initialization
    await controller.initialize();

    // Update to ready state
    final readyState = videoState.toReady();
    final readyControllerState = controllerState.copyWith(
      state: readyState,
      lastAccessedAt: DateTime.now(),
    );

    state = state.copyWith(
      controllers: {...state.controllers, videoId: readyControllerState},
    );
  }

  @override
  void pauseVideo(String videoId) {
    final controllerState = state.getController(videoId);
    if (controllerState != null) {
      (controllerState.controller as TestVideoPlayerController).pause();
    }
  }

  @override
  void resumeVideo(String videoId) {
    final controllerState = state.getController(videoId);
    if (controllerState != null) {
      (controllerState.controller as TestVideoPlayerController).play();
    }
  }
}
