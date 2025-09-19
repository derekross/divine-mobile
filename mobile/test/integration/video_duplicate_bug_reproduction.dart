// ABOUTME: Test to reproduce the exact duplicate video preload bug from user logs
// ABOUTME: Focuses on the specific scenario that causes duplicate "Starting preload" calls

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openvine/utils/unified_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Video Duplicate Bug Reproduction', () {
    setUp(() {
      // Mock SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('reproduces duplicate preload calls like in user logs',
        (tester) async {
      // Create the exact video ID from the user's logs
      final testVideo = VideoEvent(
        id: '3d55fd4c12345678', // Similar to the user's log: 3d55fd4c...
        pubkey: 'test-pubkey',
        content: 'Test video content',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
        videoUrl: 'https://test.cloudinary.com/video.mp4',
      );

      late ProviderContainer container;

      // Track preload calls to detect duplicates (like the user's logs showed)

      container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  // First VideoFeedItem
                  Expanded(
                    child: VideoFeedItem(
                      video: testVideo,
                      isActive: true,
                    ),
                  ),
                  // Second VideoFeedItem with the same video (potential duplicate scenario)
                  Expanded(
                    child: VideoFeedItem(
                      video: testVideo,
                      isActive: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Pump to let the UI initialize
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final videoManager = container.read(videoManagerProvider.notifier);
      final initialState = container.read(videoManagerProvider);

      Log.debug(
          '🔍 REPRODUCTION: Initial controller count: ${initialState.controllers.length}',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      // Reproduce the exact pattern from user logs - rapid preload calls
      Log.debug(
          '🔍 REPRODUCTION: Calling preloadVideo multiple times for ${testVideo.id.substring(0, 8)}...',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);

      await tester.pump();

      final finalState = container.read(videoManagerProvider);
      Log.debug(
          '🔍 REPRODUCTION: Final controller count: ${finalState.controllers.length}',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      // Check that we don't have duplicate controllers
      final videoControllers =
          finalState.controllers.keys.where((id) => id == testVideo.id).length;

      Log.debug(
          '🔍 REPRODUCTION: Controllers for video ${testVideo.id.substring(0, 8)}: $videoControllers',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      expect(
        videoControllers,
        equals(1),
        reason:
            'REPRODUCTION FAILED: Expected exactly 1 controller for video ${testVideo.id.substring(0, 8)}, '
            'but found $videoControllers controllers. This reproduces the duplicate bug from user logs!',
      );

      // Also verify total controller count is reasonable
      expect(
        finalState.controllers.length,
        lessThanOrEqualTo(2), // Should be at most 1 per unique video
        reason:
            'REPRODUCTION FAILED: Too many total controllers: ${finalState.controllers.length}',
      );

      container.dispose();
    });

    testWidgets('reproduces scroll-induced duplicate pattern', (tester) async {
      // Create videos like in the scroll scenario
      final video1 = VideoEvent(
        id: '3d55fd4c12345678',
        pubkey: 'test-pubkey',
        content: 'Video 1',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
        videoUrl: 'https://test.cloudinary.com/video1.mp4',
      );

      final video2 = VideoEvent(
        id: 'abc123def4567890',
        pubkey: 'test-pubkey',
        content: 'Video 2',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
        videoUrl: 'https://test.cloudinary.com/video2.mp4',
      );

      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PageView(
                children: [
                  VideoFeedItem(video: video1, isActive: true),
                  VideoFeedItem(video: video2, isActive: false),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final videoManager = container.read(videoManagerProvider.notifier);

      Log.debug(
          '🔍 SCROLL REPRODUCTION: Simulating scroll behavior that caused duplicates...',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      // Reproduce the scroll pattern that caused the duplicate logs
      // User showed logs where same video got "Starting preload" multiple times

      // Initial video load
      await videoManager.preloadVideo(video1.id);
      videoManager.resumeVideo(video1.id);

      // Simulate scroll to second video
      videoManager.pauseVideo(video1.id);
      await videoManager.preloadVideo(video2.id);
      videoManager.resumeVideo(video2.id);

      // Simulate scroll back to first video (this might trigger duplicate preload)
      videoManager.pauseVideo(video2.id);
      await videoManager
          .preloadVideo(video1.id); // This might be a duplicate call
      videoManager.resumeVideo(video1.id);

      await tester.pump();

      final finalState = container.read(videoManagerProvider);

      // Check each video has exactly one controller
      final video1Controllers =
          finalState.controllers.keys.where((id) => id == video1.id).length;
      final video2Controllers =
          finalState.controllers.keys.where((id) => id == video2.id).length;

      Log.debug(
          '🔍 SCROLL REPRODUCTION: Video1 controllers: $video1Controllers',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);
      Log.debug(
          '🔍 SCROLL REPRODUCTION: Video2 controllers: $video2Controllers',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);
      Log.debug(
          '🔍 SCROLL REPRODUCTION: Total controllers: ${finalState.controllers.length}',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      expect(video1Controllers, equals(1),
          reason: 'Video1 should have exactly 1 controller');
      expect(video2Controllers, equals(1),
          reason: 'Video2 should have exactly 1 controller');
      expect(finalState.controllers.length, equals(2),
          reason: 'Should have exactly 2 controllers total');

      container.dispose();
    });

    testWidgets('reproduces pause/resume duplicate pattern from logs',
        (tester) async {
      final testVideo = VideoEvent(
        id: '3d55fd4c12345678',
        pubkey: 'test-pubkey',
        content: 'Pause/Resume test video',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
        videoUrl: 'https://test.cloudinary.com/video.mp4',
      );

      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoFeedItem(
                video: testVideo,
                isActive: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final videoManager = container.read(videoManagerProvider.notifier);

      Log.debug(
          '🔍 PAUSE/RESUME REPRODUCTION: Testing pause/resume that user reported...',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);

      // Reproduce the exact pattern: pause the visible video but audio keeps going
      await videoManager.preloadVideo(testVideo.id);
      videoManager.resumeVideo(testVideo.id);

      Log.debug('🔍 PAUSE/RESUME REPRODUCTION: Pausing video...',
          name: 'VideoDuplicateBugTest', category: LogCategory.system);
      videoManager.pauseVideo(testVideo.id);

      // The bug: audio should stop but doesn't, indicating the pause didn't work on all instances
      // Let's check the controller state
      final state = container.read(videoManagerProvider);
      final controllerState = state.getController(testVideo.id);

      Log.debug(
          '🔍 PAUSE/RESUME REPRODUCTION: Controller exists: ${controllerState != null}',
          name: 'VideoDuplicateBugTest',
          category: LogCategory.system);
      if (controllerState != null) {
        Log.debug(
            '🔍 PAUSE/RESUME REPRODUCTION: Is playing: ${controllerState.controller.value.isPlaying}',
            name: 'VideoDuplicateBugTest',
            category: LogCategory.system);
      }

      // The video should be paused
      expect(
        controllerState?.controller.value.isPlaying,
        isFalse,
        reason:
            'PAUSE/RESUME BUG: Video should be paused but is still playing! '
            'This reproduces the audio-keeps-playing bug.',
      );

      container.dispose();
    });
  });
}
