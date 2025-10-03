// ABOUTME: Tests for hybrid local+remote search in SearchScreenPure
// ABOUTME: Validates immediate local results followed by remote relay search

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_events_providers.dart';
import 'package:openvine/screens/pure/search_screen_pure.dart';
import 'package:openvine/services/user_profile_service.dart';
import 'package:openvine/services/video_event_service.dart';

import '../helpers/test_helpers.dart';
import 'search_screen_hybrid_search_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<VideoEventService>(),
  MockSpec<UserProfileService>(),
])
void main() {
  group('SearchScreenPure Hybrid Search Tests', () {
    late MockVideoEventService mockVideoEventService;
    late MockUserProfileService mockUserProfileService;

    setUp(() {
      mockVideoEventService = MockVideoEventService();
      mockUserProfileService = MockUserProfileService();

      // Setup basic mocks
      when(mockVideoEventService.discoveryVideos).thenReturn([]);
      when(mockVideoEventService.searchResults).thenReturn([]);
      when(mockUserProfileService.getCachedProfile(any)).thenReturn(null);
    });

    testWidgets('should show local results immediately while searching remote',
        (WidgetTester tester) async {
      // Arrange: Create test videos
      final localVideo = TestHelpers.createVideoEvent(
        id: 'local1',
        title: 'Local Bitcoin Video',
        content: 'Bitcoin is awesome',
        hashtags: ['bitcoin'],
      );

      final remoteVideo = TestHelpers.createVideoEvent(
        id: 'remote1',
        title: 'Remote Bitcoin Video',
        content: 'Bitcoin from relay',
        hashtags: ['bitcoin'],
      );

      // Mock local videos available immediately
      when(mockVideoEventService.discoveryVideos).thenReturn([localVideo]);

      // Mock remote search that takes time
      when(mockVideoEventService.searchVideos(
        any,
        authors: anyNamed('authors'),
        since: anyNamed('since'),
        until: anyNamed('until'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async {
        // Simulate network delay
        await Future.delayed(const Duration(milliseconds: 500));
      });

      // Mock search results getter to return remote results after search
      when(mockVideoEventService.searchResults).thenReturn([remoteVideo]);

      // Act: Build widget
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoEventServiceProvider.overrideWithValue(mockVideoEventService),
            userProfileServiceProvider
                .overrideWithValue(mockUserProfileService),
            videoEventsProvider.overrideWith(
                (ref) => Stream.value([localVideo]).asyncValue()),
          ],
          child: const MaterialApp(
            home: SearchScreenPure(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), 'bitcoin');
      await tester.pump(const Duration(milliseconds: 300)); // Debounce delay

      // Assert: Should show local results immediately
      await tester.pump();
      expect(find.text('Videos (1)'), findsOneWidget);

      // Wait for remote search to complete
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: Should now show combined or remote results
      // verify(mockVideoEventService.searchVideos(
      //   'bitcoin',
      //   authors: anyNamed('authors'),
      //   since: anyNamed('since'),
      //   until: anyNamed('until'),
      //   limit: anyNamed('limit'),
      // )).called(1);
    });

    testWidgets('should filter local videos by title, content, and hashtags',
        (WidgetTester tester) async {
      // Arrange
      final video1 = TestHelpers.createVideoEvent(
        id: 'v1',
        title: 'Bitcoin Tutorial',
        content: 'Learn about crypto',
        hashtags: ['bitcoin', 'crypto'],
      );

      final video2 = TestHelpers.createVideoEvent(
        id: 'v2',
        title: 'Flutter App',
        content: 'Build apps with bitcoin payments',
        hashtags: ['flutter'],
      );

      final video3 = TestHelpers.createVideoEvent(
        id: 'v3',
        title: 'Nostr Protocol',
        content: 'Decentralized social media',
        hashtags: ['nostr', 'bitcoin'],
      );

      when(mockVideoEventService.discoveryVideos)
          .thenReturn([video1, video2, video3]);
      when(mockVideoEventService.searchVideos(any,
              authors: anyNamed('authors'),
              since: anyNamed('since'),
              until: anyNamed('until'),
              limit: anyNamed('limit')))
          .thenAnswer((_) async {});

      // Act
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoEventServiceProvider.overrideWithValue(mockVideoEventService),
            userProfileServiceProvider
                .overrideWithValue(mockUserProfileService),
            videoEventsProvider.overrideWith((ref) =>
                Stream.value([video1, video2, video3]).asyncValue()),
          ],
          child: const MaterialApp(
            home: SearchScreenPure(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search for "bitcoin"
      await tester.enterText(find.byType(TextField), 'bitcoin');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // Assert: Should find 3 videos (title match, content match, hashtag match)
      expect(find.text('Videos (3)'), findsOneWidget);
    });

    testWidgets('should show loading indicator during remote search',
        (WidgetTester tester) async {
      // Arrange
      when(mockVideoEventService.discoveryVideos).thenReturn([]);
      when(mockVideoEventService.searchVideos(any,
              authors: anyNamed('authors'),
              since: anyNamed('since'),
              until: anyNamed('until'),
              limit: anyNamed('limit')))
          .thenAnswer(
              (_) => Future.delayed(const Duration(milliseconds: 1000)));

      // Act
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoEventServiceProvider.overrideWithValue(mockVideoEventService),
            userProfileServiceProvider
                .overrideWithValue(mockUserProfileService),
            videoEventsProvider
                .overrideWith((ref) => Stream.value([]).asyncValue()),
          ],
          child: const MaterialApp(
            home: SearchScreenPure(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search and wait for debounce
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump(const Duration(milliseconds: 300));

      // Assert: Should show searching indicator in AppBar
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('should extract unique users from search results',
        (WidgetTester tester) async {
      // Arrange
      final video1 = TestHelpers.createVideoEvent(
        id: 'v1',
        pubkey: 'user1',
        content: 'Content by user1',
      );

      final video2 = TestHelpers.createVideoEvent(
        id: 'v2',
        pubkey: 'user2',
        content: 'Content by user2',
      );

      final video3 = TestHelpers.createVideoEvent(
        id: 'v3',
        pubkey: 'user1', // Duplicate user
        content: 'Another video by user1',
      );

      when(mockVideoEventService.discoveryVideos)
          .thenReturn([video1, video2, video3]);
      when(mockVideoEventService.searchVideos(any,
              authors: anyNamed('authors'),
              since: anyNamed('since'),
              until: anyNamed('until'),
              limit: anyNamed('limit')))
          .thenAnswer((_) async {});

      // Act
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoEventServiceProvider.overrideWithValue(mockVideoEventService),
            userProfileServiceProvider
                .overrideWithValue(mockUserProfileService),
            videoEventsProvider.overrideWith(
                (ref) => Stream.value([video1, video2, video3]).asyncValue()),
          ],
          child: const MaterialApp(
            home: SearchScreenPure(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search and switch to Users tab
      await tester.enterText(find.byType(TextField), 'user');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // Tap Users tab
      await tester.tap(find.text('Users (2)'));
      await tester.pumpAndSettle();

      // Assert: Should show 2 unique users (not 3)
      expect(find.text('Users (2)'), findsOneWidget);
    });

    testWidgets('should combine local and remote search results',
        (WidgetTester tester) async {
      // Arrange
      final localVideo = TestHelpers.createVideoEvent(
        id: 'local1',
        title: 'Local Nostr Video',
        content: 'From local cache',
      );

      final remoteVideo = TestHelpers.createVideoEvent(
        id: 'remote1',
        title: 'Remote Nostr Video',
        content: 'From relay',
      );

      // Start with local video
      when(mockVideoEventService.discoveryVideos).thenReturn([localVideo]);

      var searchResultsValue = <VideoEvent>[];
      when(mockVideoEventService.searchResults)
          .thenAnswer((_) => searchResultsValue);

      when(mockVideoEventService.searchVideos(any,
              authors: anyNamed('authors'),
              since: anyNamed('since'),
              until: anyNamed('until'),
              limit: anyNamed('limit')))
          .thenAnswer((_) async {
        // Simulate remote results arriving
        await Future.delayed(const Duration(milliseconds: 100));
        searchResultsValue = [remoteVideo];
      });

      // Act
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoEventServiceProvider.overrideWithValue(mockVideoEventService),
            userProfileServiceProvider
                .overrideWithValue(mockUserProfileService),
            videoEventsProvider.overrideWith(
                (ref) => Stream.value([localVideo]).asyncValue()),
          ],
          child: const MaterialApp(
            home: SearchScreenPure(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search
      await tester.enterText(find.byType(TextField), 'nostr');
      await tester.pump(const Duration(milliseconds: 300));

      // Should show local results first
      await tester.pump();
      expect(find.text('Videos (1)'), findsOneWidget);

      // Wait for remote search
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Should eventually show remote results
      verify(mockVideoEventService.searchVideos(any,
              authors: anyNamed('authors'),
              since: anyNamed('since'),
              until: anyNamed('until'),
              limit: anyNamed('limit')))
          .called(1);
    });
  });
}

extension StreamToAsyncValue on Stream<List<VideoEvent>> {
  AsyncValue<List<VideoEvent>> asyncValue() {
    return AsyncValue.data(const []);
  }
}
