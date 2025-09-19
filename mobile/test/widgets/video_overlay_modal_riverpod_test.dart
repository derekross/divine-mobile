// ABOUTME: Tests for VideoOverlayModal Riverpod migration ensuring proper provider integration
// ABOUTME: Verifies widget builds with Riverpod providers and manages video state correctly

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/state/video_manager_state.dart';
import 'package:openvine/widgets/video_overlay_modal.dart';

// Mock classes for Riverpod VideoManager - using VideoManager directly instead of IVideoManager interface
class MockVideoManager extends Mock implements VideoManager {
  @override
  VideoManagerState build() => const VideoManagerState();
}

void main() {
  late MockVideoManager mockVideoManager;
  late List<VideoEvent> testVideoList;
  late VideoEvent testStartingVideo;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(VideoEvent(
      id: 'fallback-id',
      pubkey: 'fallback-pubkey',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/
          1000, // Unix timestamp in seconds
      content: '',
      timestamp: DateTime.now(),
    ));
  });

  setUp(() {
    mockVideoManager = MockVideoManager();

    // Create test data
    final now = DateTime.now();
    testStartingVideo = VideoEvent(
      id: 'video-1',
      pubkey: 'test-pubkey',
      createdAt:
          now.millisecondsSinceEpoch ~/ 1000, // Unix timestamp in seconds
      content: 'Test video 1',
      timestamp: now,
    );

    testVideoList = [
      testStartingVideo,
      VideoEvent(
        id: 'video-2',
        pubkey: 'test-pubkey',
        createdAt:
            now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                1000,
        content: 'Test video 2',
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      VideoEvent(
        id: 'video-3',
        pubkey: 'test-pubkey',
        createdAt:
            now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/
                1000,
        content: 'Test video 3',
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
    ];
  });

  group('VideoOverlayModal Riverpod Migration', () {
    testWidgets('should build with Riverpod providers',
        (WidgetTester tester) async {
      // This test should PASS because the widget now uses ref.read() properly

      // Arrange
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Clean override using VideoManager directly (no IVideoManager interface)
            videoManagerProvider.overrideWith(() => mockVideoManager),
          ],
          child: MaterialApp(
            home: VideoOverlayModal(
              startingVideo: testStartingVideo,
              videoList: testVideoList,
              contextTitle: 'Test Context',
            ),
          ),
        ),
      );

      // Act & Assert
      expect(find.byType(VideoOverlayModal), findsOneWidget);
      expect(find.text('Test Context'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('should access VideoManager through ref.read()',
        (WidgetTester tester) async {
      // This test should PASS because the widget now uses ref.read() correctly

      // Arrange
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Clean override using VideoManager directly (no IVideoManager interface)
            videoManagerProvider.overrideWith(() => mockVideoManager),
          ],
          child: MaterialApp(
            home: VideoOverlayModal(
              startingVideo: testStartingVideo,
              videoList: testVideoList,
              contextTitle: 'Test Context',
            ),
          ),
        ),
      );

      // Wait for the widget to initialize
      await tester.pumpAndSettle();

      // Assert that the mock VideoManager methods were called
      // This should pass because the widget now uses the Riverpod provider
      verify(() => mockVideoManager.addVideoEvent(any()))
          .called(greaterThan(0));
      verify(() => mockVideoManager.preloadVideo(any())).called(1);
    });

    testWidgets('should handle video initialization and cleanup',
        (WidgetTester tester) async {
      // This test should PASS because video cleanup now uses Riverpod

      // Arrange
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Clean override using VideoManager directly (no IVideoManager interface)
            videoManagerProvider.overrideWith(() => mockVideoManager),
          ],
          child: MaterialApp(
            home: VideoOverlayModal(
              startingVideo: testStartingVideo,
              videoList: testVideoList,
              contextTitle: 'Test Context',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Act - dispose the widget
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Assert that cleanup was called
      // This should pass because the widget now uses Riverpod provider for cleanup
      verify(() => mockVideoManager.pauseAllVideos()).called(1);
    });

    testWidgets('should handle page navigation correctly',
        (WidgetTester tester) async {
      // This test should PASS because page changes now use Riverpod

      // Arrange
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Clean override using VideoManager directly (no IVideoManager interface)
            videoManagerProvider.overrideWith(() => mockVideoManager),
          ],
          child: MaterialApp(
            home: VideoOverlayModal(
              startingVideo: testStartingVideo,
              videoList: testVideoList,
              contextTitle: 'Test Context',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Act - simulate page change by swiping
      final pageView = find.byType(PageView);
      expect(pageView, findsOneWidget);

      await tester.drag(
          pageView, const Offset(0, -300)); // Swipe up to next video
      await tester.pumpAndSettle();

      // Assert that video manager methods were called for the new video
      // This should pass because page changes now use Riverpod provider
      verify(() => mockVideoManager.addVideoEvent(any()))
          .called(greaterThan(3));
      verify(() => mockVideoManager.preloadVideo('video-2')).called(1);
    });

    test('showVideoOverlay helper function should work with Riverpod context',
        () {
      // This test verifies the helper function doesn't break with Riverpod
      // Should pass regardless since it just creates a route

      expect(() {
        // Mock BuildContext
        final context = MockBuildContext();

        showVideoOverlay(
          context: context,
          startingVideo: testStartingVideo,
          videoList: testVideoList,
          contextTitle: 'Test Context',
        );
      }, returnsNormally);
    });
  });
}

// Mock BuildContext for testing
class MockBuildContext extends Mock implements BuildContext {}
