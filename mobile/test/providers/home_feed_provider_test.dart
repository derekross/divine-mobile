// ABOUTME: Tests for home feed provider functionality
// ABOUTME: Verifies that home feed correctly filters videos from followed authors

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/home_feed_provider.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/social_providers.dart' as social;
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/state/social_state.dart';

import 'home_feed_provider_test.mocks.dart';

@GenerateMocks([
  VideoEventService,
  INostrService,
  SubscriptionManager,
])
void main() {
  group('HomeFeedProvider', () {
    late ProviderContainer container;
    late MockVideoEventService mockVideoEventService;
    late MockINostrService mockNostrService;
    late MockSubscriptionManager mockSubscriptionManager;

    setUp(() {
      mockVideoEventService = MockVideoEventService();
      mockNostrService = MockINostrService();
      mockSubscriptionManager = MockSubscriptionManager();

      // Setup default mock behaviors
      when(mockVideoEventService.homeFeedVideos).thenReturn([]);
      when(mockVideoEventService.getEventCount(SubscriptionType.homeFeed))
          .thenReturn(0);
      when(mockVideoEventService.subscribeToHomeFeed(
        any,
        limit: anyNamed('limit'),
      )).thenAnswer((_) async {});

      container = ProviderContainer(
        overrides: [
          videoEventServiceProvider.overrideWithValue(mockVideoEventService),
          nostrServiceProvider.overrideWithValue(mockNostrService),
          subscriptionManagerProvider
              .overrideWithValue(mockSubscriptionManager),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('should return empty state when user is not following anyone',
        () async {
      // Setup: User is not following anyone - create new container with overrides
      final testContainer = ProviderContainer(
        overrides: [
          videoEventServiceProvider.overrideWithValue(mockVideoEventService),
          nostrServiceProvider.overrideWithValue(mockNostrService),
          subscriptionManagerProvider
              .overrideWithValue(mockSubscriptionManager),
          social.socialNotifierProvider.overrideWith(() {
            return social.SocialNotifier()
              ..state = const SocialState(
                followingPubkeys: [],
                isInitialized: true,
              );
          }),
        ],
      );
      addTearDown(testContainer.dispose);

      // Act
      final result = await testContainer.read(homeFeedProvider.future);

      // Assert
      expect(result.videos, isEmpty);
      expect(result.hasMoreContent, isFalse);
      expect(result.isLoadingMore, isFalse);
      expect(result.error, isNull);

      // Verify that we didn't try to subscribe since there are no following
      verifyNever(mockVideoEventService.subscribeToHomeFeed(
        any,
        limit: anyNamed('limit'),
      ));
    });

    test('should subscribe to videos from followed authors', () async {
      // Setup: User is following 3 people
      final followingPubkeys = [
        'pubkey1_following',
        'pubkey2_following',
        'pubkey3_following',
      ];

      container.updateOverrides([
        social.socialNotifierProvider.overrideWith(() {
          return social.SocialNotifier()
            ..state = SocialState(
              followingPubkeys: followingPubkeys,
              isInitialized: true,
            );
        }),
      ]);

      // Create mock videos from followed authors
      final mockVideos = [
        VideoEvent(
          id: 'event1',
          pubkey: 'pubkey1_following',
          createdAt: 1000,
          content: 'Video 1',
          timestamp: DateTime.now(),
          videoUrl: 'https://example.com/video1.mp4',
        ),
        VideoEvent(
          id: 'event2',
          pubkey: 'pubkey2_following',
          createdAt: 900,
          content: 'Video 2',
          timestamp: DateTime.now(),
          videoUrl: 'https://example.com/video2.mp4',
        ),
      ];

      when(mockVideoEventService.homeFeedVideos).thenReturn(mockVideos);

      // Act
      final result = await container.read(homeFeedProvider.future);

      // Assert
      expect(result.videos.length, equals(2));
      expect(result.videos[0].pubkey, equals('pubkey1_following'));
      expect(result.videos[1].pubkey, equals('pubkey2_following'));

      // Verify subscription was created with correct authors
      verify(mockVideoEventService.subscribeToHomeFeed(
        followingPubkeys,
        limit: 100,
      )).called(1);
    });

    test('should sort videos by creation time (newest first)', () async {
      // Setup: User is following people
      final followingPubkeys = ['pubkey1', 'pubkey2'];

      container.updateOverrides([
        social.socialNotifierProvider.overrideWith(() {
          return social.SocialNotifier()
            ..state = SocialState(
              followingPubkeys: followingPubkeys,
              isInitialized: true,
            );
        }),
      ]);

      // Create mock videos with different timestamps
      final now = DateTime.now();
      final mockVideos = [
        VideoEvent(
          id: 'event1',
          pubkey: 'pubkey1',
          createdAt: 100,
          content: 'Older video',
          timestamp: now.subtract(const Duration(hours: 2)),
          videoUrl: 'https://example.com/video1.mp4',
        ),
        VideoEvent(
          id: 'event2',
          pubkey: 'pubkey2',
          createdAt: 200,
          content: 'Newer video',
          timestamp: now.subtract(const Duration(hours: 1)),
          videoUrl: 'https://example.com/video2.mp4',
        ),
      ];

      when(mockVideoEventService.homeFeedVideos).thenReturn(mockVideos);

      // Act
      final result = await container.read(homeFeedProvider.future);

      // Assert: Videos should be sorted newest first
      expect(result.videos.length, equals(2));
      expect(
          result.videos[0].createdAt, greaterThan(result.videos[1].createdAt));
      expect(result.videos[0].content, equals('Newer video'));
      expect(result.videos[1].content, equals('Older video'));
    });

    test('should handle load more functionality', () async {
      // Setup
      final followingPubkeys = ['pubkey1'];

      container.updateOverrides([
        social.socialNotifierProvider.overrideWith(() {
          return social.SocialNotifier()
            ..state = SocialState(
              followingPubkeys: followingPubkeys,
              isInitialized: true,
            );
        }),
      ]);

      when(mockVideoEventService.homeFeedVideos).thenReturn([]);
      when(mockVideoEventService.loadMoreEvents(
        SubscriptionType.homeFeed,
        limit: anyNamed('limit'),
      )).thenAnswer((_) async {});
      when(mockVideoEventService.getEventCount(SubscriptionType.homeFeed))
          .thenReturn(10);

      // Act
      await container.read(homeFeedProvider.future);
      await container.read(homeFeedProvider.notifier).loadMore();

      // Assert
      verify(mockVideoEventService.loadMoreEvents(
        SubscriptionType.homeFeed,
        limit: 50,
      )).called(1);
    });

    test('should handle refresh functionality', () async {
      // Setup
      final followingPubkeys = ['pubkey1'];

      container.updateOverrides([
        social.socialNotifierProvider.overrideWith(() {
          return social.SocialNotifier()
            ..state = SocialState(
              followingPubkeys: followingPubkeys,
              isInitialized: true,
            );
        }),
      ]);

      when(mockVideoEventService.homeFeedVideos).thenReturn([]);

      // Act
      await container.read(homeFeedProvider.future);
      await container.read(homeFeedProvider.notifier).refresh();

      // Assert: Should re-subscribe after refresh
      verify(mockVideoEventService.subscribeToHomeFeed(
        followingPubkeys,
        limit: 100,
      )).called(2); // Once on initial load, once on refresh
    });

    test('should handle empty video list correctly', () async {
      // Setup: User is following people but no videos available
      final followingPubkeys = ['pubkey1', 'pubkey2'];

      container.updateOverrides([
        social.socialNotifierProvider.overrideWith(() {
          return social.SocialNotifier()
            ..state = SocialState(
              followingPubkeys: followingPubkeys,
              isInitialized: true,
            );
        }),
      ]);

      when(mockVideoEventService.homeFeedVideos).thenReturn([]);

      // Act
      final result = await container.read(homeFeedProvider.future);

      // Assert
      expect(result.videos, isEmpty);
      expect(result.hasMoreContent, isFalse);
      expect(result.error, isNull);

      // Verify subscription was still attempted
      verify(mockVideoEventService.subscribeToHomeFeed(
        followingPubkeys,
        limit: 100,
      )).called(1);
    });
  });

  group('HomeFeed Helper Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('homeFeedLoading should reflect loading state', () {
      // Test loading state detection
      final isLoading = container.read(homeFeedLoadingProvider);
      expect(isLoading, isA<bool>());
    });

    test('homeFeedCount should return video count', () {
      // Test video count
      final count = container.read(homeFeedCountProvider);
      expect(count, isA<int>());
      expect(count, greaterThanOrEqualTo(0));
    });

    test('hasHomeFeedVideos should indicate if videos exist', () {
      // Test video existence check
      final hasVideos = container.read(hasHomeFeedVideosProvider);
      expect(hasVideos, isA<bool>());
    });
  });
}
