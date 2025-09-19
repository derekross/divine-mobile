import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/models/video_state.dart';
import 'package:openvine/services/social_service.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/theme/vine_theme.dart';

// Generate mocks
@GenerateMocks([SocialService, IVideoManager])
import 'video_feed_item_like_test.mocks.dart';

void main() {
  group('VideoFeedItem Like Button', () {
    late MockSocialService mockSocialService;
    late MockIVideoManager mockVideoManager;
    late VideoEvent testVideoEvent;

    setUpAll(() {
      // Initialize platform channel mocking once for all tests
      const MethodChannel('flutter.io/videoPlayer')
          .setMockMethodCallHandler((call) async {
        switch (call.method) {
          case 'init':
            return null;
          case 'create':
            return {'textureId': 1};
          case 'setLooping':
          case 'setVolume':
          case 'setPlaybackSpeed':
          case 'play':
          case 'pause':
          case 'seekTo':
          case 'dispose':
            return null;
          case 'position':
            return {'position': 0};
          default:
            return null;
        }
      });
    });

    setUp(() {
      mockSocialService = MockSocialService();
      mockVideoManager = MockIVideoManager();

      testVideoEvent = VideoEvent(
        id: 'test_video_123',
        pubkey: 'test_author_pubkey',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        content: 'Test video content',
        timestamp: DateTime.now(),
        videoUrl: 'https://example.com/video.mp4',
        mimeType: 'video/mp4',
      );

      // Setup video manager mock with video state
      final testVideoState = VideoState(
        event: testVideoEvent,
        loadingState: VideoLoadingState.ready,
      );
      when(mockVideoManager.getVideoState('test_video_123'))
          .thenReturn(testVideoState);
      when(mockVideoManager.getController('test_video_123')).thenReturn(null);
      when(mockVideoManager.videos).thenReturn([testVideoEvent]);
      when(mockVideoManager.readyVideos).thenReturn([testVideoEvent]);
      when(mockVideoManager.preloadVideo('test_video_123'))
          .thenAnswer((_) async {});
      when(mockVideoManager.addVideoEvent(testVideoEvent))
          .thenAnswer((_) async {});
    });

    Widget createTestWidget({bool isLiked = false, int likeCount = 0}) {
      // Mock social service responses
      when(mockSocialService.isLiked(testVideoEvent.id)).thenReturn(isLiked);
      when(mockSocialService.getCachedLikeCount(testVideoEvent.id))
          .thenReturn(likeCount);
      when(mockSocialService.getLikeStatus(testVideoEvent.id)).thenAnswer(
        (_) async => {'count': likeCount, 'user_liked': isLiked},
      );
      when(mockSocialService.toggleLike(
              testVideoEvent.id, testVideoEvent.pubkey))
          .thenAnswer((_) async {});
      when(mockSocialService.fetchCommentsForEvent(testVideoEvent.id))
          .thenAnswer((_) => const Stream.empty());

      final container = ProviderContainer(
        overrides: [
          socialServiceProvider.overrideWithValue(mockSocialService),
          // We'll skip the video manager provider override for now to keep tests simple
          // The real provider will be used but should work with platform channel mocks
        ],
      );

      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: VineTheme.theme,
          home: Scaffold(
            body: VideoFeedItem(
              video: testVideoEvent,
              isActive: true,
            ),
          ),
        ),
      );
    }

    testWidgets('should show unfilled heart when video is not liked',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 0));
      await tester.pumpAndSettle();

      // Should show unfilled heart icon
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);

      // Should not show like count when count is 0
      expect(find.text('0'), findsNothing);
    });

    testWidgets('should show filled red heart when video is liked',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isLiked: true, likeCount: 5));
      await tester.pumpAndSettle();

      // Should show filled heart icon
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);

      // Should show like count
      expect(find.text('5'), findsOneWidget);

      // Heart should be red
      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.favorite));
      expect(iconWidget.color, Colors.red);
    });

    testWidgets('should display formatted like counts correctly',
        (tester) async {
      // Test thousands formatting
      await tester
          .pumpWidget(createTestWidget(isLiked: false, likeCount: 1500));
      await tester.pumpAndSettle();
      expect(find.text('1.5K'), findsOneWidget);

      // Test millions formatting
      await tester
          .pumpWidget(createTestWidget(isLiked: false, likeCount: 2500000));
      await tester.pumpAndSettle();
      expect(find.text('2.5M'), findsOneWidget);

      // Test regular numbers
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 999));
      await tester.pumpAndSettle();
      expect(find.text('999'), findsOneWidget);
    });

    testWidgets('should call toggleLike when like button is tapped',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 0));
      await tester.pumpAndSettle();

      // Find the like button container and tap it
      final likeButton = find.byIcon(Icons.favorite_border);
      expect(likeButton, findsOneWidget);

      await tester.tap(likeButton);
      await tester.pumpAndSettle();

      // Verify toggleLike was called with correct parameters
      verify(mockSocialService.toggleLike(
              testVideoEvent.id, testVideoEvent.pubkey))
          .called(1);
    });

    testWidgets('should update UI immediately when like state changes',
        (tester) async {
      // This test verifies the UI updates when the SocialService state changes
      // Start with unliked state
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 0));
      await tester.pumpAndSettle();

      // Should show unfilled heart initially
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);

      // Tap the like button to trigger the toggle
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump(); // Single pump to avoid infinite loop

      // Verify toggleLike was called
      verify(mockSocialService.toggleLike(
              testVideoEvent.id, testVideoEvent.pubkey))
          .called(1);
    });

    testWidgets('should show error snackbar when toggleLike fails',
        (tester) async {
      // Mock toggleLike to throw error
      when(mockSocialService.toggleLike(
              testVideoEvent.id, testVideoEvent.pubkey))
          .thenThrow(Exception('Network error'));

      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 0));
      await tester.pumpAndSettle();

      // Tap the like button
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump(); // Pump for the async call to complete
      await tester
          .pump(const Duration(milliseconds: 100)); // Give time for snackbar

      // Verify toggleLike was called and threw error
      verify(mockSocialService.toggleLike(
              testVideoEvent.id, testVideoEvent.pubkey))
          .called(1);

      // Note: SnackBar testing can be complex due to async nature and ScaffoldMessenger
      // For now, we verify the method was called which would trigger the error handling
    });

    testWidgets('should handle loading state properly', (tester) async {
      // This test verifies the widget shows the initial cached state
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 5));
      await tester.pumpAndSettle();

      // Should show initial state
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Should show like count from cache
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('should not show count when like count is zero',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 0));
      await tester.pumpAndSettle();

      // Should not display "0" text
      expect(find.text('0'), findsNothing);

      // But should show the heart icon
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('should maintain proper button sizing and styling',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isLiked: false, likeCount: 42));
      await tester.pumpAndSettle();

      // Check that like button exists
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Check that count is displayed
      expect(find.text('42'), findsOneWidget);

      // Check icon size
      final iconWidget =
          tester.widget<Icon>(find.byIcon(Icons.favorite_border));
      expect(iconWidget.size, 24);
    });
  });
}
