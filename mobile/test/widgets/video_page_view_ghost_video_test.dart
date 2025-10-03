// ABOUTME: Tests for ghost video playback bug fixes in VideoPageView
// ABOUTME: Ensures videos don't play when on inactive tabs or during navigation

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/individual_video_providers.dart';
import 'package:openvine/widgets/video_page_view.dart';
import '../builders/test_video_event_builder.dart';

void main() {
  group('VideoPageView Ghost Video Prevention', () {
    late List<VideoEvent> testVideos;

    setUp(() {
      final now = DateTime.now();
      testVideos = List.generate(
        5,
        (i) => TestVideoEventBuilder.create(
          id: 'test-video-$i',
          pubkey: 'test-pubkey-$i',
          content: 'Test video $i',
          title: 'Test Video $i',
          videoUrl: 'https://example.com/video-$i.mp4',
          timestamp: now.subtract(Duration(hours: i)),
          createdAt: (now.millisecondsSinceEpoch ~/ 1000) - (i * 3600),
        ),
      );
    });

    testWidgets('initState does not set active video immediately', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Build widget with lifecycle management enabled
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoPageView(
                videos: testVideos,
                initialIndex: 0,
                enableLifecycleManagement: true,
              ),
            ),
          ),
        ),
      );

      // Wait ONLY for initState and postFrameCallback to complete
      // Don't pump visibility detector timers yet
      await tester.pump();
      await tester.pump();

      // Verify that no active video was set by initState/postFrameCallback
      // (Visibility detection may set it later, which is expected behavior)
      final activeVideo = container.read(activeVideoProvider);
      expect(activeVideo, isNull,
          reason: 'VideoPageView.initState() should not eagerly set active video');

      // Clean up pending timers from visibility detector
      await tester.pumpAndSettle();
    });

    testWidgets('does not steal active video from another source', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Simulate another video being active (e.g., from another tab)
      const otherVideoId = 'other-active-video-123';
      container.read(activeVideoProvider.notifier).setActiveVideo(otherVideoId);

      // Build VideoPageView
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoPageView(
                videos: testVideos,
                initialIndex: 0,
                enableLifecycleManagement: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the active video was not changed
      final activeVideo = container.read(activeVideoProvider);
      expect(activeVideo, equals(otherVideoId),
          reason: 'VideoPageView should not override existing active video');
    });

    testWidgets('multiple VideoPageViews do not compete for active video', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Build IndexedStack with multiple VideoPageViews (simulating tab navigation)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: IndexedStack(
                index: 0, // First tab active
                children: [
                  VideoPageView(
                    key: const Key('feed-1'),
                    videos: testVideos,
                    enableLifecycleManagement: true,
                  ),
                  VideoPageView(
                    key: const Key('feed-2'),
                    videos: testVideos,
                    enableLifecycleManagement: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify no active video was set by either PageView
      final activeVideo = container.read(activeVideoProvider);
      expect(activeVideo, isNull,
          reason: 'Multiple VideoPageViews should not compete to set active video');
    });

    testWidgets('clearing active video does not cause reactivation', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Build VideoPageView
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoPageView(
                videos: testVideos,
                enableLifecycleManagement: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Simulate clearing active video (like when navigating to camera)
      container.read(activeVideoProvider.notifier).clearActiveVideo();
      await tester.pumpAndSettle();

      // Verify active video stays null (not reactivated by VideoPageView)
      final activeVideo = container.read(activeVideoProvider);
      expect(activeVideo, isNull,
          reason: 'VideoPageView should not reactivate video after clearing');
    });

    testWidgets('rebuilding VideoPageView does not set active video', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Widget buildWidget(Key key) {
        return UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoPageView(
                key: key,
                videos: testVideos,
                enableLifecycleManagement: true,
              ),
            ),
          ),
        );
      }

      // Initial build
      await tester.pumpWidget(buildWidget(const Key('initial')));
      await tester.pumpAndSettle();

      // Verify no active video set
      expect(container.read(activeVideoProvider), isNull);

      // Rebuild with different key (simulates app resume rebuild)
      await tester.pumpWidget(buildWidget(const Key('rebuild')));
      await tester.pumpAndSettle();

      // Verify active video still null after rebuild
      final activeVideo = container.read(activeVideoProvider);
      expect(activeVideo, isNull,
          reason: 'VideoPageView rebuild should not set active video');
    });

    testWidgets('prewarm still works without setting active video', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoPageView(
                videos: testVideos,
                initialIndex: 1,
                enableLifecycleManagement: true,
                enablePrewarming: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify prewarming happened (videos around index 1 should be prewarmed)
      final prewarmedVideos = container.read(prewarmManagerProvider);
      expect(prewarmedVideos, isNotEmpty,
          reason: 'Prewarming should still work without setting active video');

      // But active video should still be null
      expect(container.read(activeVideoProvider), isNull,
          reason: 'Prewarming should not trigger active video setting');
    });
  });
}
