// ABOUTME: PopularNow feed provider showing newest videos using VideoFeedBuilder helper
// ABOUTME: Subscribes to SubscriptionType.popularNow and sorts by timestamp (newest first)
// ABOUTME: Auto-refreshes every 30 seconds to match web version behavior

import 'dart:async';

import 'package:nostr_sdk/filter.dart';
import 'package:openvine/constants/app_constants.dart';
import 'package:openvine/helpers/video_feed_builder.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/video_filter_builder.dart';
import 'package:openvine/state/video_feed_state.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'popular_now_feed_provider.g.dart';

/// PopularNow feed provider - shows newest videos (sorted by creation time)
///
/// Rebuilds when:
/// - Auto-refresh every 30 seconds (matching web version)
/// - User pulls to refresh
/// - VideoEventService updates with new videos
@Riverpod(keepAlive: true) // Keep alive to prevent state loss on tab switches
class PopularNowFeed extends _$PopularNowFeed {
  VideoFeedBuilder? _builder;
  Timer? _autoRefreshTimer;

  @override
  Future<VideoFeedState> build() async {
    Log.info(
      '🆕 PopularNowFeed: Building feed for newest videos',
      name: 'PopularNowFeedProvider',
      category: LogCategory.video,
    );

    final videoEventService = ref.watch(videoEventServiceProvider);
    _builder = VideoFeedBuilder(videoEventService);

    // Configure feed for popularNow subscription type
    // IMPORTANT: NO NIP-50 search - just chronological sorting to match web version
    final config = VideoFeedConfig(
      subscriptionType: SubscriptionType.popularNow,
      subscribe: (service) async {
        await service.subscribeToVideoFeed(
          subscriptionType: SubscriptionType.popularNow,
          limit: 100,
          // NO sortBy or nip50Sort - just get videos chronologically
          // This matches the web version's 'recent' feed behavior
        );
      },
      getVideos: (service) => service.popularNowVideos,
      filterVideos: (videos) {
        // Filter out WebM videos on iOS/macOS (not supported by AVPlayer)
        return videos.where((v) => v.isSupportedOnCurrentPlatform).toList();
      },
      sortVideos: (videos) {
        // Client-side chronological sort (newest first) to match web version
        final sorted = List<VideoEvent>.from(videos);
        sorted.sort((a, b) {
          final timeCompare = b.timestamp.compareTo(a.timestamp);
          if (timeCompare != 0) return timeCompare;
          // Secondary sort by ID for stable ordering
          return a.id.compareTo(b.id);
        });
        return sorted;
      },
    );

    // Build feed using helper
    final state = await _builder!.buildFeed(config: config);

    // Check if still mounted after async gap
    if (!ref.mounted) {
      return VideoFeedState(
        videos: const [],
        hasMoreContent: false,
        isLoadingMore: false,
      );
    }

    // Set up continuous listener for updates
    _builder!.setupContinuousListener(
      config: config,
      onUpdate: (newState) {
        if (ref.mounted) {
          this.state = AsyncData(newState);
        }
      },
    );

    // Set up 30-second auto-refresh to match web version
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.mounted) {
        Log.info(
          '🔄 PopularNowFeed: Auto-refreshing (30 sec interval)',
          name: 'PopularNowFeedProvider',
          category: LogCategory.video,
        );
        refresh();
      }
    });

    // Clean up on dispose
    ref.onDispose(() {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      _builder?.cleanup();
      _builder = null;
      Log.info(
        '🆕 PopularNowFeed: Disposed',
        name: 'PopularNowFeedProvider',
        category: LogCategory.video,
      );
    });

    Log.info(
      '✅ PopularNowFeed: Feed built with ${state.videos.length} videos',
      name: 'PopularNowFeedProvider',
      category: LogCategory.video,
    );

    return state;
  }

  /// Load more historical events
  Future<void> loadMore() async {
    final currentState = await future;

    if (!ref.mounted || currentState.isLoadingMore) {
      return;
    }

    // Update state to show loading
    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final videoEventService = ref.read(videoEventServiceProvider);
      final eventCountBefore =
          videoEventService.getEventCount(SubscriptionType.popularNow);

      // Load more events for popularNow subscription type
      await videoEventService.loadMoreEvents(
        SubscriptionType.popularNow,
        limit: 50,
      );

      if (!ref.mounted) return;

      final eventCountAfter =
          videoEventService.getEventCount(SubscriptionType.popularNow);
      final newEventsLoaded = eventCountAfter - eventCountBefore;

      Log.info(
        '🆕 PopularNowFeed: Loaded $newEventsLoaded new events (total: $eventCountAfter)',
        name: 'PopularNowFeedProvider',
        category: LogCategory.video,
      );

      // Reset loading state - state will auto-update via listener
      final newState = await future;
      if (!ref.mounted) return;
      state = AsyncData(newState.copyWith(
        isLoadingMore: false,
        hasMoreContent: newEventsLoaded > 0,
      ));
    } catch (e) {
      Log.error(
        '🆕 PopularNowFeed: Error loading more: $e',
        name: 'PopularNowFeedProvider',
        category: LogCategory.video,
      );

      if (!ref.mounted) return;
      final currentState = await future;
      if (!ref.mounted) return;
      state = AsyncData(
        currentState.copyWith(
          isLoadingMore: false,
          error: e.toString(),
        ),
      );
    }
  }

  /// Refresh the feed
  /// Delegate to VideoEventService's refresh logic which waits for EOSE
  Future<void> refresh() async {
    Log.info(
      '🆕 PopularNowFeed: Refreshing feed via VideoEventService',
      name: 'PopularNowFeedProvider',
      category: LogCategory.video,
    );

    final videoEventService = ref.read(videoEventServiceProvider);

    // Close existing subscription
    await videoEventService.unsubscribeFromVideoFeed();

    // Force new subscription to get fresh data from relay
    // NO NIP-50 search - just chronological to match web version
    await videoEventService.subscribeToVideoFeed(
      subscriptionType: SubscriptionType.popularNow,
      limit: 100,
      // NO sortBy or nip50Sort - just get videos chronologically
      force: true, // Force refresh bypasses duplicate detection
    );

    // Invalidate self to rebuild with fresh data
    ref.invalidateSelf();

    Log.info(
      '🆕 PopularNowFeed: Refresh complete',
      name: 'PopularNowFeedProvider',
      category: LogCategory.video,
    );
  }
}

/// Provider to check if popularNow feed is loading
@riverpod
bool popularNowFeedLoading(Ref ref) {
  final asyncState = ref.watch(popularNowFeedProvider);
  if (asyncState.isLoading) return true;

  final state = asyncState.hasValue ? asyncState.value : null;
  if (state == null) return false;

  return state.isLoadingMore;
}

/// Provider to get current popularNow feed video count
@riverpod
int popularNowFeedCount(Ref ref) {
  final asyncState = ref.watch(popularNowFeedProvider);
  return asyncState.hasValue ? (asyncState.value?.videos.length ?? 0) : 0;
}
