// ABOUTME: Test to reproduce duplicate video preload/resume bug
// ABOUTME: Verifies that video preloading and resume operations don't create duplicates

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/nostr_service.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';
import '../builders/test_video_event_builder.dart';

// Helper function to create test videos
VideoEvent createTestVideo({String? id, String? title}) {
  return TestVideoEventBuilder.create(id: id, title: title);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock platform plugins as per project testing standards
  const MethodChannel prefsChannel =
      MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    prefsChannel,
    (MethodCall methodCall) async {
      if (methodCall.method == 'getAll') return <String, dynamic>{};
      if (methodCall.method == 'setString' ||
          methodCall.method == 'setStringList') return true;
      return null;
    },
  );

  // Mock connectivity plugin
  const MethodChannel connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    connectivityChannel,
    (MethodCall methodCall) async {
      if (methodCall.method == 'check') return ['wifi'];
      return null;
    },
  );

  // Mock secure storage
  const MethodChannel secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    secureStorageChannel,
    (MethodCall methodCall) async {
      if (methodCall.method == 'write') return null;
      if (methodCall.method == 'read') return null;
      if (methodCall.method == 'readAll') return <String, String>{};
      return null;
    },
  );

  group('Video Duplicate Preload Bug', () {
    late ProviderContainer container;
    late NostrKeyManager keyManager;
    late NostrService nostrService;

    setUpAll(() async {
      // Mock SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});

      // Initialize real services as per project requirements
      keyManager = NostrKeyManager();
      await keyManager.initialize();

      if (!keyManager.hasKeys) {
        await keyManager.generateKeys();
      }

      nostrService = NostrService(keyManager);
      await nostrService.initialize();
    });

    setUp(() {
      // Create container with real service overrides
      container = ProviderContainer(
        overrides: [
          nostrKeyManagerProvider.overrideWithValue(keyManager),
          nostrServiceProvider.overrideWithValue(nostrService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('should not create duplicate preload calls for same video',
        (tester) async {
      // Create test video
      final testVideo = createTestVideo();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  return VideoFeedItem(
                    video: testVideo,
                    isActive: true,
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Wait for initial setup
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Get the video manager
      final videoManager = container.read(videoManagerProvider.notifier);

      // Track the initial state
      final initialState = container.read(videoManagerProvider);
      final initialControllerCount = initialState.controllers.length;

      // Call preloadVideo multiple times for the same video ID
      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);

      await tester.pump();

      // Check final state - should not have duplicate controllers
      final finalState = container.read(videoManagerProvider);
      final finalControllerCount = finalState.controllers.length;

      // Should only have one additional controller for our video
      expect(
        finalControllerCount - initialControllerCount,
        lessThanOrEqualTo(1),
        reason:
            'Expected at most 1 new controller for video ${testVideo.id.substring(0, 8)}, '
            'but found ${finalControllerCount - initialControllerCount} new controllers. '
            'This indicates duplicate controller creation.',
      );

      // Check that we only have one controller for this specific video
      final videoControllers =
          finalState.controllers.keys.where((id) => id == testVideo.id).length;

      expect(
        videoControllers,
        equals(1),
        reason:
            'Expected exactly 1 controller for video ${testVideo.id.substring(0, 8)}, '
            'but found $videoControllers controllers. This indicates duplicate controllers.',
      );
    });

    testWidgets('should not create duplicate resume calls during video scroll',
        (tester) async {
      // Create test videos
      final video1 = createTestVideo();
      final video2 = VideoEvent(
        id: 'test-video-2',
        pubkey: 'test-pubkey',
        content: 'Test video 2',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        timestamp: DateTime.now(),
        videoUrl: 'https://test.cloudinary.com/video2.mp4',
        thumbnailUrl: 'https://test.cloudinary.com/thumb2.jpg',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PageView(
                children: [
                  Consumer(
                    builder: (context, ref, child) {
                      return VideoFeedItem(
                        video: video1,
                        isActive: true,
                      );
                    },
                  ),
                  Consumer(
                    builder: (context, ref, child) {
                      return VideoFeedItem(
                        video: video2,
                        isActive: false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final videoManager = container.read(videoManagerProvider.notifier);

      // Track state changes during scroll simulation
      final initialState = container.read(videoManagerProvider);

      // Simulate scroll behavior that triggers preload/resume
      await videoManager.preloadVideo(video1.id);
      videoManager.resumeVideo(video1.id);

      // Simulate scroll to next video (should pause first, preload/resume second)
      videoManager.pauseVideo(video1.id);
      await videoManager.preloadVideo(video2.id);
      videoManager.resumeVideo(video2.id);

      // Simulate scroll back (should pause second, resume first)
      videoManager.pauseVideo(video2.id);
      videoManager.resumeVideo(video1.id);

      await tester.pump();

      // Check that we don't create duplicate controllers during scroll
      final finalState = container.read(videoManagerProvider);

      expect(
        finalState.controllers.length,
        lessThanOrEqualTo(initialState.controllers.length + 2),
        reason: 'Expected at most 2 new controllers (video1 + video2), '
            'but found ${finalState.controllers.length - initialState.controllers.length} new controllers. '
            'This indicates duplicate controller creation during scroll.',
      );

      // Verify each video has exactly one controller
      final video1Controllers =
          finalState.controllers.keys.where((id) => id == video1.id).length;
      final video2Controllers =
          finalState.controllers.keys.where((id) => id == video2.id).length;

      expect(video1Controllers, equals(1),
          reason: 'Video1 should have exactly 1 controller');
      expect(video2Controllers, equals(1),
          reason: 'Video2 should have exactly 1 controller');
    });

    test('video manager state should not allow duplicate controllers',
        () async {
      final testVideo = createTestVideo();

      final videoManager = container.read(videoManagerProvider.notifier);
      final initialState = container.read(videoManagerProvider);

      // Verify no controller exists initially
      expect(initialState.hasController(testVideo.id), isFalse);

      // Simulate adding the video multiple times (like from feed sync)
      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);

      final finalState = container.read(videoManagerProvider);

      // Should only have one controller for the video
      expect(
          finalState.controllers.keys.where((id) => id == testVideo.id).length,
          equals(1));
    });

    testWidgets('rapid scroll should not create duplicate operations',
        (tester) async {
      // Create multiple test videos
      final videos = List.generate(
          5,
          (index) => VideoEvent(
                id: 'test-video-$index',
                pubkey: 'test-pubkey',
                content: 'Test video $index',
                createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                timestamp: DateTime.now(),
                videoUrl: 'https://test.cloudinary.com/video$index.mp4',
                thumbnailUrl: 'https://test.cloudinary.com/thumb$index.jpg',
              ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PageView.builder(
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  return Consumer(
                    builder: (context, ref, child) {
                      return VideoFeedItem(
                        video: videos[index],
                        isActive: index == 0, // Only first is active initially
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final videoManager = container.read(videoManagerProvider.notifier);
      final initialState = container.read(videoManagerProvider);

      // Simulate rapid scrolling through videos
      for (int i = 0; i < videos.length; i++) {
        if (i > 0) {
          // Pause previous video
          videoManager.pauseVideo(videos[i - 1].id);
        }

        // Preload and resume current video
        await videoManager.preloadVideo(videos[i].id);
        videoManager.resumeVideo(videos[i].id);

        // Small delay to simulate scroll timing
        await tester.pump(const Duration(milliseconds: 50));
      }

      final finalState = container.read(videoManagerProvider);

      // Check that each video has exactly one controller (no duplicates)
      for (final video in videos) {
        final videoControllers =
            finalState.controllers.keys.where((id) => id == video.id).length;

        expect(
          videoControllers,
          equals(1),
          reason:
              'Video ${video.id.substring(0, 8)} should have exactly 1 controller, '
              'but found $videoControllers controllers. This indicates duplicate controller creation.',
        );
      }

      // Total controllers should not exceed number of videos
      final totalNewControllers =
          finalState.controllers.length - initialState.controllers.length;
      expect(
        totalNewControllers,
        lessThanOrEqualTo(videos.length),
        reason:
            'Expected at most ${videos.length} new controllers for ${videos.length} videos, '
            'but found $totalNewControllers new controllers.',
      );
    });
  });
}
