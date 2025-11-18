// ABOUTME: Route-aware hashtag feed provider with pagination support
// ABOUTME: Returns videos filtered by hashtag from route context

import 'dart:async';

import 'package:openvine/models/video_event.dart';
import 'package:openvine/router/page_context_provider.dart';
import 'package:openvine/router/route_utils.dart';
import 'package:openvine/services/custom_hashtag_fetcher.dart';
import 'package:openvine/state/video_feed_state.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'hashtag_feed_providers.g.dart';

/// Hashtag feed provider - shows videos with a specific hashtag
///
/// Rebuilds when:
/// - Route changes (different hashtag)
/// - User pulls to refresh
/// - VideoEventService updates with new hashtag videos
@Riverpod(keepAlive: false) // Auto-dispose when no listeners
class HashtagFeed extends _$HashtagFeed {
  static int _buildCounter = 0;

  @override
  Future<VideoFeedState> build() async {
    _buildCounter++;
    final buildId = _buildCounter;

    // Get hashtag from route context
    final ctx = ref.watch(pageContextProvider).asData?.value;
    if (ctx == null || ctx.type != RouteType.hashtag) {
      return VideoFeedState(
        videos: const [],
        hasMoreContent: false,
        isLoadingMore: false,
      );
    }

    final raw = (ctx.hashtag ?? '').trim();
    final tag = raw.toLowerCase(); // normalize
    if (tag.isEmpty) {
      return VideoFeedState(
        videos: const [],
        hasMoreContent: false,
        isLoadingMore: false,
      );
    }

    Log.info('HashtagFeed: Loading #$tag (build #$buildId)',
        name: 'HashtagFeedProvider', category: LogCategory.video);

    // Use CustomHashtagFetcher to load videos directly from relay
    final videos = await CustomHashtagFetcher.fetchHashtagVideos(
      hashtag: tag,
      limit: 100,
    );

    // Sort videos by loops, then time
    videos.sort(VideoEvent.compareByLoopsThenTime);

    Log.info('HashtagFeed: Loaded ${videos.length} videos for #$tag',
        name: 'HashtagFeedProvider', category: LogCategory.video);

    return VideoFeedState(
      videos: videos,
      hasMoreContent: videos.length >= 10,
      isLoadingMore: false,
      error: null,
      lastUpdated: DateTime.now(),
    );
  }

  /// Load more historical videos with this hashtag
  /// Note: CustomHashtagFetcher loads all available videos at once, so this is a no-op
  Future<void> loadMore() async {
    final currentState = await future;
    if (!ref.mounted) return;

    // Mark as complete (no more content to load since we fetched all at once)
    state = AsyncData(currentState.copyWith(
      isLoadingMore: false,
      hasMoreContent: false,
    ));
  }

  /// Refresh the hashtag feed
  Future<void> refresh() async {
    // Simply invalidate to trigger rebuild and re-fetch from relay
    ref.invalidateSelf();
  }
}
