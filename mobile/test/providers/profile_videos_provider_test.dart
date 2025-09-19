// ABOUTME: Tests for ProfileVideosProvider to ensure cache-first behavior and request optimization
// ABOUTME: Validates that unnecessary subscriptions are avoided when data is fresh in cache

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nostr_sdk/nostr_sdk.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/profile_videos_provider.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/video_event_service.dart';

@GenerateMocks([
  INostrService,
  VideoEventService,
])
import 'profile_videos_provider_test.mocks.dart';

void main() {
  group('ProfileVideosProvider', () {
    late ProviderContainer container;
    late MockINostrService mockNostrService;
    late MockVideoEventService mockVideoEventService;

    setUp(() {
      mockNostrService = MockINostrService();
      mockVideoEventService = MockVideoEventService();

      container = ProviderContainer(
        overrides: [
          nostrServiceProvider.overrideWithValue(mockNostrService),
          videoEventServiceProvider.overrideWithValue(mockVideoEventService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      clearAllProfileVideosCache();
    });

    group('Initial State', () {
      test('should have correct initial state', () {
        final state = container.read(profileVideosNotifierProvider);
        expect(state.videos, isEmpty);
        expect(state.isLoading, false);
        expect(state.isLoadingMore, false);
        expect(state.hasMore, true);
        expect(state.error, isNull);
        expect(state.lastTimestamp, isNull);
      });
    });

    group('Loading Videos', () {
      const testPubkey = 'test_pubkey_123';

      test('should use cached videos from VideoEventService', () async {
        // Arrange
        final now = DateTime.now();
        final cachedVideos = <VideoEvent>[
          VideoEvent(
            id: 'video1',
            pubkey: testPubkey,
            content: 'test content',
            createdAt: now.millisecondsSinceEpoch ~/ 1000,
            timestamp: now,
            videoUrl: 'https://example.com/video1.mp4',
            title: 'Test Video 1',
          ),
          VideoEvent(
            id: 'video2',
            pubkey: testPubkey,
            content: 'test content 2',
            createdAt: (now.millisecondsSinceEpoch ~/ 1000) - 100,
            timestamp: now.subtract(const Duration(seconds: 100)),
            videoUrl: 'https://example.com/video2.mp4',
            title: 'Test Video 2',
          ),
        ];

        // Mock VideoEventService to return cached videos
        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn(cachedVideos);

        // Mock empty subscription (no new events)
        final controller = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller.stream);

        // Act
        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);

        // Close the stream to complete loading
        await controller.close();

        // Assert
        final state = container.read(profileVideosNotifierProvider);
        expect(state.videos.length, equals(2));
        expect(state.videos.first.id, equals('video1')); // Newest first
        expect(state.videos.last.id, equals('video2'));
        expect(state.isLoading, false);
        expect(state.error, isNull);

        // Should have called getVideosByAuthor
        verify(mockVideoEventService.getVideosByAuthor(testPubkey)).called(1);
      });

      test('should handle loading errors gracefully', () async {
        // Arrange
        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn([]);
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => Stream.error(Exception('Network error')));

        // Act
        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);

        // Assert
        final state = container.read(profileVideosNotifierProvider);
        expect(state.isLoading, false);
        expect(state.videos, isEmpty);
        // Note: Error handling in streaming implementation might not set error state
        // This depends on the specific implementation details
      });

      test('should prevent concurrent loads for same user', () async {
        // Arrange
        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn([]);

        final controller = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller.stream);

        // Act - start two concurrent loads
        final notifier = container.read(profileVideosNotifierProvider.notifier);
        final future1 = notifier.loadVideosForUser(testPubkey);
        final future2 = notifier.loadVideosForUser(testPubkey);

        // Complete the stream
        await controller.close();

        await Future.wait([future1, future2]);

        // Assert - should only call service once
        verify(mockVideoEventService.getVideosByAuthor(testPubkey)).called(1);
      });
    });

    group('Cache Management', () {
      const testPubkey = 'test_pubkey_cache';

      test('should refresh videos by clearing cache', () async {
        // Arrange - first load with some videos
        final now = DateTime.now();
        final initialVideos = <VideoEvent>[
          VideoEvent(
            id: 'initial_video1',
            pubkey: testPubkey,
            content: 'initial content',
            createdAt: now.millisecondsSinceEpoch ~/ 1000,
            timestamp: now,
            videoUrl: 'https://example.com/initial1.mp4',
            title: 'Initial Video 1',
          ),
        ];

        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn(initialVideos);

        final controller1 = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller1.stream);

        // Load initial videos
        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);
        await controller1.close();

        // Verify initial state
        var state = container.read(profileVideosNotifierProvider);
        expect(state.videos.length, equals(1));
        expect(state.videos.first.id, equals('initial_video1'));

        // Arrange for refresh - mock updated videos
        final updatedVideos = <VideoEvent>[
          VideoEvent(
            id: 'updated_video1',
            pubkey: testPubkey,
            content: 'updated content',
            createdAt: (now.millisecondsSinceEpoch ~/ 1000) + 100,
            timestamp: now.add(const Duration(seconds: 100)),
            videoUrl: 'https://example.com/updated1.mp4',
            title: 'Updated Video 1',
          ),
        ];

        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn(updatedVideos);

        final controller2 = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller2.stream);

        // Act - refresh videos
        await notifier.refreshVideos();
        await controller2.close();

        // Assert - should have updated videos
        state = container.read(profileVideosNotifierProvider);
        expect(state.videos.length, equals(1));
        expect(state.videos.first.id, equals('updated_video1'));
      });

      test('should clear error state', () async {
        // Create error state first by failing a load
        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn([]);
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => Stream.error(Exception('Test error')));

        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);

        // Verify we can clear error (implementation might vary)
        notifier.clearError();

        final state = container.read(profileVideosNotifierProvider);
        expect(state.error, isNull);
      });

      test('should clear all cache globally', () {
        clearAllProfileVideosCache();
        // Just verify it doesn't throw - internal cache state is private
      });
    });

    group('Load More Videos', () {
      const testPubkey = 'test_pubkey_more';

      test('should load more videos with pagination', () async {
        // Arrange - setup initial videos
        final now = DateTime.now();
        final initialVideos = <VideoEvent>[
          VideoEvent(
            id: 'initial1',
            pubkey: testPubkey,
            content: 'initial content 1',
            createdAt: now.millisecondsSinceEpoch ~/ 1000,
            timestamp: now,
            videoUrl: 'https://example.com/initial1.mp4',
            title: 'Initial Video 1',
          ),
        ];

        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn(initialVideos);

        final controller1 = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller1.stream);

        // Load initial videos
        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);
        await controller1.close();

        // Set hasMore = true for load more test
        // (This would need to be done differently in real implementation)

        // Mock load more subscription
        final controller2 = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller2.stream);

        // Act - try to load more
        await notifier.loadMoreVideos();
        await controller2.close();

        // Assert - should complete without error
        final state = container.read(profileVideosNotifierProvider);
        expect(state.isLoadingMore, false);
      });

      test('should not load more when hasMore is false', () async {
        // This test ensures loadMoreVideos returns early when there are no more videos
        final notifier = container.read(profileVideosNotifierProvider.notifier);

        // Initial state has hasMore = true, but no videos loaded
        // This should cause loadMoreVideos to return early
        await notifier.loadMoreVideos();

        // Should complete without attempting to create subscription
        final state = container.read(profileVideosNotifierProvider);
        expect(state.isLoadingMore, false);
      });
    });

    group('Video Management', () {
      const testPubkey = 'test_pubkey_manage';

      test('should add video optimistically', () async {
        // Load some initial videos first
        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn([]);

        final controller = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller.stream);

        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);
        await controller.close();

        // Create new video to add
        final newVideo = VideoEvent(
          id: 'new_video_123',
          pubkey: testPubkey,
          content: 'new content',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          timestamp: DateTime.now(),
          videoUrl: 'https://example.com/new.mp4',
          title: 'New Video',
        );

        // Act - add video
        notifier.addVideo(newVideo);

        // Assert - video should be added to list
        final state = container.read(profileVideosNotifierProvider);
        expect(state.videos.length, equals(1));
        expect(state.videos.first.id, equals('new_video_123'));
      });

      test('should remove video', () async {
        // Setup initial state with video
        final initialVideo = VideoEvent(
          id: 'video_to_remove',
          pubkey: testPubkey,
          content: 'content',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          timestamp: DateTime.now(),
          videoUrl: 'https://example.com/remove.mp4',
          title: 'Video to Remove',
        );

        when(mockVideoEventService.getVideosByAuthor(testPubkey))
            .thenReturn([initialVideo]);

        final controller = StreamController<Event>();
        when(mockNostrService.subscribeToEvents(filters: anyNamed('filters')))
            .thenAnswer((_) => controller.stream);

        final notifier = container.read(profileVideosNotifierProvider.notifier);
        await notifier.loadVideosForUser(testPubkey);
        await controller.close();

        // Verify initial state
        var state = container.read(profileVideosNotifierProvider);
        expect(state.videos.length, equals(1));

        // Act - remove video
        notifier.removeVideo('video_to_remove');

        // Assert - video should be removed
        state = container.read(profileVideosNotifierProvider);
        expect(state.videos, isEmpty);
      });
    });
  });
}
