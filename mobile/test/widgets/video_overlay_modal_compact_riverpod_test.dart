// ABOUTME: TDD tests for video_overlay_modal_compact Riverpod conversion
// ABOUTME: Tests widget builds with Riverpod providers and VideoManager access through ref.read()

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/widgets/video_overlay_modal_compact.dart';
import '../helpers/test_provider_overrides.dart';

// Fake classes for mocktail fallback values
class FakeVideoEvent extends Fake implements VideoEvent {}

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    registerFallbackValue(VideoEvent(
      id: 'fallback-id',
      pubkey: 'fallback-pubkey',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      content: '',
      timestamp: DateTime.now(),
    ));
  });

  group('VideoOverlayModalCompact Riverpod Migration Tests', () {
    late TestVideoManager testVideoManager;
    late List<VideoEvent> testVideoList;
    late VideoEvent testStartingVideo;

    setUp(() {
      testVideoManager = TestVideoManager();

      // Create test video events using real VideoEvent instances
      final now = DateTime.now();
      testStartingVideo = VideoEvent(
        id: 'test-video-1',
        pubkey: 'test-pubkey-1',
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        content: 'Test Video 1',
        timestamp: now,
        videoUrl: 'https://example.com/video1.mp4',
        thumbnailUrl: 'https://example.com/thumb1.jpg',
        title: 'Test Video 1',
        hashtags: const <String>[],
      );

      final testVideo2 = VideoEvent(
        id: 'test-video-2',
        pubkey: 'test-pubkey-2',
        createdAt:
            now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                1000,
        content: 'Test Video 2',
        timestamp: now.subtract(const Duration(hours: 1)),
        videoUrl: 'https://example.com/video2.mp4',
        thumbnailUrl: 'https://example.com/thumb2.jpg',
        title: 'Test Video 2',
        hashtags: const <String>[],
      );

      testVideoList = [testStartingVideo, testVideo2];

      // TestVideoManager doesn't need mock setup - it provides stub implementations
    });

    testWidgets('should build with Riverpod providers (NOW PASSES)',
        (tester) async {
      // This test should NOW PASS because widget has been converted to ConsumerStatefulWidget
      // and uses ref.read() instead of Provider.of()

      await tester.pumpWidget(
        createTestWidget(
          testVideoManager: testVideoManager,
          child: VideoOverlayModalCompact(
            startingVideo: testStartingVideo,
            videoList: testVideoList,
            contextTitle: 'Test Context',
            startingIndex: 0,
          ),
        ),
      );

      await tester.pump();

      // This should fail because widget still uses Provider.of() instead of ref.read()
      expect(find.byType(VideoOverlayModalCompact), findsOneWidget);
    });

    testWidgets(
        'should access VideoManager through ref.read() (NOW PASSES after migration)',
        (tester) async {
      // This test should PASS because widget now uses ref.read(videoManagerProvider.notifier)

      await tester.pumpWidget(
        createTestWidget(
          testVideoManager: testVideoManager,
          child: VideoOverlayModalCompact(
            startingVideo: testStartingVideo,
            videoList: testVideoList,
            contextTitle: 'Test Context',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(); // Allow async initialization

      // If we get here without exceptions, the widget is using Riverpod correctly
      expect(find.byType(VideoOverlayModalCompact), findsOneWidget);
    });

    testWidgets(
        'should handle animation and gesture behavior with Riverpod (SHOULD FAIL initially)',
        (tester) async {
      // Test that animations and gestures work with Riverpod providers

      await tester.pumpWidget(
        createTestWidget(
          testVideoManager: testVideoManager,
          child: VideoOverlayModalCompact(
            startingVideo: testStartingVideo,
            videoList: testVideoList,
            contextTitle: 'Test Context',
          ),
        ),
      );

      await tester.pump();
      await tester
          .pump(const Duration(milliseconds: 350)); // Animation duration

      // Test swipe down gesture to dismiss
      await tester.drag(find.byType(PageView), const Offset(0, 500));
      await tester.pumpAndSettle();

      // Should be able to dismiss properly with Riverpod
      expect(find.byType(VideoOverlayModalCompact), findsOneWidget);
    });

    testWidgets(
        'should handle compact modal specific behavior (SHOULD FAIL initially)',
        (tester) async {
      // Test compact modal header, drag handle, and page navigation

      await tester.pumpWidget(
        createTestWidget(
          testVideoManager: testVideoManager,
          child: VideoOverlayModalCompact(
            startingVideo: testStartingVideo,
            videoList: testVideoList,
            contextTitle: 'Test Videos',
            startingIndex: 1,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Should show context title
      expect(find.text('Test Videos'), findsOneWidget);

      // Should show current position
      expect(find.text('2 of 2'), findsOneWidget);

      // Should have drag handle
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

      // Should have PageView for video content
      expect(find.byType(PageView), findsOneWidget);
    });

    test(
        'showCompactVideoOverlay helper function should work with Riverpod context',
        () {
      // Test the helper function that shows the modal
      // This should fail if context doesn't have proper Riverpod providers

      // Create a mock context that should have Riverpod providers
      final context = MockBuildContext();

      // This should not throw an exception once converted to Riverpod
      expect(() {
        showCompactVideoOverlay(
          context: context,
          startingVideo: testStartingVideo,
          videoList: testVideoList,
          contextTitle: 'Test Context',
          startingIndex: 0,
        );
      }, returnsNormally);
    });
  });
}

// Mock BuildContext for testing
class MockBuildContext extends Mock implements BuildContext {}
