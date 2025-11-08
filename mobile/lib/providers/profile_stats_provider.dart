// ABOUTME: Riverpod provider for managing profile statistics with async loading and caching
// ABOUTME: Aggregates user video count, likes, and other metrics from Nostr events

import 'dart:async';

import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/profile_stats_cache_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/utils/string_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_stats_provider.g.dart';

/// Statistics for a user's profile
class ProfileStats {
  const ProfileStats({
    required this.videoCount,
    required this.totalLikes,
    required this.followers,
    required this.following,
    required this.totalViews,
    required this.lastUpdated,
  });
  final int videoCount;
  final int totalLikes;
  final int followers;
  final int following;
  final int totalViews; // Placeholder for future implementation
  final DateTime lastUpdated;

  ProfileStats copyWith({
    int? videoCount,
    int? totalLikes,
    int? followers,
    int? following,
    int? totalViews,
    DateTime? lastUpdated,
  }) =>
      ProfileStats(
        videoCount: videoCount ?? this.videoCount,
        totalLikes: totalLikes ?? this.totalLikes,
        followers: followers ?? this.followers,
        following: following ?? this.following,
        totalViews: totalViews ?? this.totalViews,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  @override
  String toString() =>
      'ProfileStats(videos: $videoCount, likes: $totalLikes, followers: $followers, following: $following, views: $totalViews)';
}


// SQLite-based persistent cache
final _cacheService = ProfileStatsCacheService();

/// Get cached stats if available and not expired
Future<ProfileStats?> _getCachedProfileStats(String pubkey) async {
  final stats = await _cacheService.getCachedStats(pubkey);

  if (stats != null) {
    final age = DateTime.now().difference(stats.lastUpdated);
    Log.debug(
        '📱 Using cached stats for $pubkey (age: ${age.inMinutes}min)',
        name: 'ProfileStatsProvider',
        category: LogCategory.ui);
  }

  return stats;
}

/// Cache stats for a user
Future<void> _cacheProfileStats(String pubkey, ProfileStats stats) async {
  await _cacheService.saveStats(pubkey, stats);
  Log.debug('📱 Cached stats for $pubkey',
      name: 'ProfileStatsProvider', category: LogCategory.ui);
}

/// Clear all cached stats
Future<void> clearAllProfileStatsCache() async {
  await _cacheService.clearAll();
  Log.debug('📱️ Cleared all stats cache',
      name: 'ProfileStatsProvider', category: LogCategory.ui);
}

/// Async provider for loading profile statistics
@riverpod
Future<ProfileStats> fetchProfileStats(Ref ref, String pubkey) async {
  Log.info('📊 fetchProfileStats called for pubkey: $pubkey',
      name: 'ProfileStatsProvider', category: LogCategory.ui);

  // Check cache first
  final cached = await _getCachedProfileStats(pubkey);
  if (cached != null) {
    Log.info('📊 Returning CACHED stats: views=${cached.totalViews}, likes=${cached.totalLikes}',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    return cached;
  }

  // Get the social service from app providers
  final socialService = ref.read(socialServiceProvider);

  Log.debug('Loading profile stats for: $pubkey',
      name: 'ProfileStatsProvider', category: LogCategory.ui);

  try {
    Log.debug('📊 Starting stats fetch for pubkey: $pubkey',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    // Get video event service and ensure subscription exists
    final videoEventService = ref.read(videoEventServiceProvider);

    // Subscribe to user's videos to ensure _authorBuckets is populated
    // This will backfill from existing videos in other subscription types
    Log.debug('📊 Step 1: Subscribing to user videos...',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    await videoEventService.subscribeToUserVideos(pubkey, limit: 100);
    Log.debug('📊 Step 1 complete: User videos subscription ready',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    // Get follower stats - use cache if available, otherwise fetch from network
    Log.debug('📊 Step 2: Getting follower stats...',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    // Check cache first for instant display
    final cachedStats = socialService.getCachedFollowerStats(pubkey);
    if (cachedStats != null) {
      Log.debug('📊 Using cached follower stats: $cachedStats',
          name: 'ProfileStatsProvider', category: LogCategory.ui);
    }

    // Fetch fresh stats from network (will use cache if recent)
    final followerStats = await socialService.getFollowerStats(pubkey);

    Log.debug('📊 Step 2 complete: Follower stats - followers=${followerStats['followers']}, following=${followerStats['following']}',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    // Get videos from VideoEventService (now populated via subscription)
    Log.debug('📊 Step 3: Fetching author videos from cache...',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    final videos = videoEventService.authorVideos(pubkey);
    final videoCount = videos.length;

    Log.debug('📊 Step 3 complete: Got ${videos.length} videos for stats calculation',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    // Sum up loops and likes from all user's videos
    Log.debug('📊 Step 4: Calculating stats from ${videos.length} videos...',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    int totalLoops = 0;
    int totalLikes = 0;

    for (final video in videos) {
      final loops = video.originalLoops ?? 0;
      final likes = video.originalLikes ?? 0;
      totalLoops += loops;
      totalLikes += likes;

      // Log every video to see what data we have
      Log.debug('📊 Video ${video.id}: loops=$loops, likes=$likes',
          name: 'ProfileStatsProvider', category: LogCategory.ui);
    }

    Log.info('📊 Step 4 complete: Calculated stats from ${videos.length} videos: totalLoops=$totalLoops, totalLikes=$totalLikes',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    Log.debug('📊 Step 5: Creating ProfileStats object...',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    final stats = ProfileStats(
      videoCount: videoCount,
      totalLikes: totalLikes, // Sum of all likes from user's videos
      followers: followerStats['followers'] ?? 0,
      following: followerStats['following'] ?? 0,
      totalViews: totalLoops, // Sum of all loops (views) from user's videos
      lastUpdated: DateTime.now(),
    );

    Log.debug('📊 Step 6: Caching stats...',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    // Cache the results
    await _cacheProfileStats(pubkey, stats);

    Log.info('📊 ✅ COMPLETE: Profile stats loaded: $stats',
        name: 'ProfileStatsProvider', category: LogCategory.ui);

    return stats;
  } catch (e) {
    Log.error('Error loading profile stats: $e',
        name: 'ProfileStatsProvider', category: LogCategory.ui);
    rethrow;
  }
}


/// Get a formatted string for large numbers (e.g., 1234 -> "1.2k")
/// Delegates to StringUtils.formatCompactNumber for consistent formatting
String formatProfileStatsCount(int count) {
  return StringUtils.formatCompactNumber(count);
}
