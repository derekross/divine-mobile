// ABOUTME: Home feed provider that shows videos only from people you follow
// ABOUTME: Filters video events by the user's following list for a personalized feed

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/social_providers.dart' as social;
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/state/video_feed_state.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'home_feed_provider.g.dart';

/// Home feed provider - shows videos only from people you follow
@Riverpod(keepAlive: false)
class HomeFeed extends _$HomeFeed {
  Timer? _profileFetchTimer;

  @override
  Future<VideoFeedState> build() async {
    Log.info(
      '🏠 HomeFeed: Starting home feed build (following only)',
      name: 'HomeFeedProvider',
      category: LogCategory.video,
    );

    // Clean up timer on dispose
    ref.onDispose(() {
      _profileFetchTimer?.cancel();
    });

    // Get social data to check following list
    final socialData = ref.watch(social.socialNotifierProvider);
    final followingPubkeys = socialData.followingPubkeys;

    Log.info(
      '🏠 HomeFeed: User is following ${followingPubkeys.length} people',
      name: 'HomeFeedProvider',
      category: LogCategory.video,
    );

    if (followingPubkeys.isEmpty) {
      // Return empty state if not following anyone
      return const VideoFeedState(
        videos: [],
        hasMoreContent: false,
        isLoadingMore: false,
        error: null,
        lastUpdated: null,
      );
    }

    // Get video event service and subscribe to following feed
    final videoEventService = ref.watch(videoEventServiceProvider);

    // Subscribe to home feed videos from followed authors using dedicated subscription type
    // NostrService now handles deduplication automatically
    await videoEventService.subscribeToHomeFeed(followingPubkeys, limit: 100);

    // Wait for initial events by listening to video service notifications
    // This replaces crude timing with proper reactive state management
    final completer = Completer<void>();
    late VoidCallback listener;

    listener = () {
      if (videoEventService.homeFeedVideos.isNotEmpty) {
        videoEventService.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    };

    videoEventService.addListener(listener);

    // Set a reasonable timeout to prevent hanging
    Timer(const Duration(seconds: 5), () {
      videoEventService.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;

    // Get videos from the dedicated home feed list (server-side filtered to only following)
    final followingVideos =
        List<VideoEvent>.from(videoEventService.homeFeedVideos);

    Log.info(
      '🏠 HomeFeed: Server-side filtered to ${followingVideos.length} videos from following',
      name: 'HomeFeedProvider',
      category: LogCategory.video,
    );

    // Sort by creation time (newest first)
    followingVideos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Auto-fetch profiles for new videos and wait for completion
    await _scheduleBatchProfileFetch(followingVideos);

    final feedState = VideoFeedState(
      videos: followingVideos,
      hasMoreContent: followingVideos.length >= 10,
      isLoadingMore: false,
      error: null,
      lastUpdated: DateTime.now(),
    );

    Log.info(
      '📋 HomeFeed: Home feed complete - ${followingVideos.length} videos from following',
      name: 'HomeFeedProvider',
      category: LogCategory.video,
    );

    return feedState;
  }

  Future<void> _scheduleBatchProfileFetch(List<VideoEvent> videos) async {
    // Cancel any existing timer
    _profileFetchTimer?.cancel();

    // Fetch profiles immediately - no delay needed as provider handles batching internally
    final profilesProvider = ref.read(userProfileNotifierProvider.notifier);

    final newPubkeys = videos
        .map((v) => v.pubkey)
        .where((pubkey) => !profilesProvider.hasProfile(pubkey))
        .toSet()
        .toList();

    if (newPubkeys.isNotEmpty) {
      Log.debug(
        'HomeFeed: Fetching ${newPubkeys.length} new profiles immediately and waiting for completion',
        name: 'HomeFeedProvider',
        category: LogCategory.video,
      );

      // Wait for profiles to be fetched before continuing
      await profilesProvider.fetchMultipleProfiles(newPubkeys);

      Log.debug(
        'HomeFeed: Profile fetching completed for ${newPubkeys.length} profiles',
        name: 'HomeFeedProvider',
        category: LogCategory.video,
      );
    } else {
      Log.debug(
        'HomeFeed: All ${videos.length} video profiles already cached',
        name: 'HomeFeedProvider',
        category: LogCategory.video,
      );
    }
  }

  /// Load more historical events from followed authors
  Future<void> loadMore() async {
    final currentState = await future;

    Log.info(
      'HomeFeed: loadMore() called - isLoadingMore: ${currentState.isLoadingMore}',
      name: 'HomeFeedProvider',
      category: LogCategory.video,
    );

    if (currentState.isLoadingMore) {
      return;
    }

    // Update state to show loading
    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final videoEventService = ref.read(videoEventServiceProvider);
      final socialData = ref.read(social.socialNotifierProvider);
      final followingPubkeys = socialData.followingPubkeys;

      if (followingPubkeys.isEmpty) {
        // No one to load more from
        state = AsyncData(currentState.copyWith(
          isLoadingMore: false,
          hasMoreContent: false,
        ));
        return;
      }

      final eventCountBefore =
          videoEventService.getEventCount(SubscriptionType.homeFeed);

      // Load more events for home feed subscription type
      await videoEventService.loadMoreEvents(SubscriptionType.homeFeed,
          limit: 50);

      final eventCountAfter =
          videoEventService.getEventCount(SubscriptionType.homeFeed);
      final newEventsLoaded = eventCountAfter - eventCountBefore;

      Log.info(
        'HomeFeed: Loaded $newEventsLoaded new events from following (total: $eventCountAfter)',
        name: 'HomeFeedProvider',
        category: LogCategory.video,
      );

      // Reset loading state - state will auto-update via dependencies
      final newState = await future;
      state = AsyncData(newState.copyWith(
        isLoadingMore: false,
        hasMoreContent: newEventsLoaded > 0,
      ));
    } catch (e) {
      Log.error(
        'HomeFeed: Error loading more: $e',
        name: 'HomeFeedProvider',
        category: LogCategory.video,
      );

      final currentState = await future;
      state = AsyncData(
        currentState.copyWith(
          isLoadingMore: false,
          error: e.toString(),
        ),
      );
    }
  }

  /// Refresh the home feed
  Future<void> refresh() async {
    Log.info(
      'HomeFeed: Refreshing home feed (following only)',
      name: 'HomeFeedProvider',
      category: LogCategory.video,
    );

    // Invalidate self to rebuild with current following list
    ref.invalidateSelf();
  }
}

/// Provider to check if home feed is loading
@riverpod
bool homeFeedLoading(Ref ref) {
  final asyncState = ref.watch(homeFeedProvider);
  if (asyncState.isLoading) return true;

  final state = asyncState.valueOrNull;
  if (state == null) return false;

  return state.isLoadingMore;
}

/// Provider to get current home feed video count
@riverpod
int homeFeedCount(Ref ref) =>
    ref.watch(homeFeedProvider).valueOrNull?.videos.length ?? 0;

/// Provider to check if we have home feed videos
@riverpod
bool hasHomeFeedVideos(Ref ref) {
  final count = ref.watch(homeFeedCountProvider);
  return count > 0;
}
