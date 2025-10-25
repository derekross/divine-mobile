// ABOUTME: Integration test for VideoMetricsTracker marking videos as seen
// ABOUTME: Validates end-to-end flow of video viewing and persistence

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/seen_videos_service.dart';
import 'package:openvine/widgets/video_metrics_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'video_metrics_tracking_test.mocks.dart';

@GenerateMocks([VideoPlayerController])
void main() {
  group('VideoMetricsTracker Integration', () {
    late MockVideoPlayerController mockController;
    late SeenVideosService seenVideosService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      seenVideosService = SeenVideosService();
      await seenVideosService.initialize();

      mockController = MockVideoPlayerController();

      // Setup controller mock
      when(mockController.value).thenReturn(VideoPlayerValue(
        duration: const Duration(seconds: 30),
        isInitialized: true,
        isPlaying: true,
      ));
    });

    tearDown(() {
      seenVideosService.dispose();
    });

    testWidgets('marks video as seen when playing', (tester) async {
      final now = DateTime.now();
      final video = VideoEvent(
        id: 'test_video_123',
        pubkey: 'test_pubkey',
        content: 'Test video',
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        timestamp: now,
      );

      final container = ProviderContainer(
        overrides: [
          seenVideosServiceProvider.overrideWithValue(seenVideosService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoMetricsTracker(
                video: video,
                controller: mockController,
                child: const Text('Video Player'),
              ),
            ),
          ),
        ),
      );

      // Wait for tracking to initialize
      await tester.pumpAndSettle();

      // Simulate video disposal (which triggers end event)
      await tester.pumpWidget(Container());

      // Wait for async operations
      await tester.pumpAndSettle();

      // Video should be marked as seen
      expect(seenVideosService.hasSeenVideo('test_video_123'), isTrue);
    });

    testWidgets('tracks loop count', (tester) async {
      final now = DateTime.now();
      final video = VideoEvent(
        id: 'looping_video',
        pubkey: 'test_pubkey',
        content: 'Looping video',
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        timestamp: now,
      );

      final container = ProviderContainer(
        overrides: [
          seenVideosServiceProvider.overrideWithValue(seenVideosService),
        ],
      );
      addTearDown(container.dispose);

      // Simulate video looping by changing position
      var position = const Duration(seconds: 0);
      when(mockController.value).thenAnswer((_) => VideoPlayerValue(
        duration: const Duration(seconds: 10),
        position: position,
        isInitialized: true,
        isPlaying: true,
      ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoMetricsTracker(
                video: video,
                controller: mockController,
                child: const Text('Video Player'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Simulate loop: position jumps from end to start
      position = const Duration(seconds: 9, milliseconds: 500);
      await tester.pump(const Duration(milliseconds: 500));

      position = const Duration(milliseconds: 100);
      await tester.pump(const Duration(milliseconds: 100));

      // Dispose to trigger end event
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();

      // Verify video was tracked
      expect(seenVideosService.hasSeenVideo('looping_video'), isTrue);
    });

    testWidgets('does not mark as seen if video errors', (tester) async {
      final now = DateTime.now();
      final video = VideoEvent(
        id: 'error_video',
        pubkey: 'test-pubkey',
        content: 'Error video',
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        timestamp: now,
        videoUrl: 'https://example.com/error_video.mp4',
      );

      when(mockController.value).thenReturn(VideoPlayerValue.erroneous('Network error'));

      final container = ProviderContainer(
        overrides: [
          seenVideosServiceProvider.overrideWithValue(seenVideosService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoMetricsTracker(
                video: video,
                controller: mockController,
                child: const Text('Video Player'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Dispose immediately
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();

      // Video should not be marked as seen (no watch duration)
      expect(seenVideosService.hasSeenVideo('error_video'), isFalse);
    });
  });
}
