// ABOUTME: Riverpod provider for managing user-specific video fetching and grid display
// ABOUTME: Fetches video events by author with pagination and caching

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostr_sdk/filter.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_videos_provider.g.dart';

/// State for profile videos provider
class ProfileVideosState {
  const ProfileVideosState({
    required this.videos,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.error,
    required this.lastTimestamp,
  });

  final List<VideoEvent> videos;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int? lastTimestamp;

  ProfileVideosState copyWith({
    List<VideoEvent>? videos,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? lastTimestamp,
  }) =>
      ProfileVideosState(
        videos: videos ?? this.videos,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: error,
        lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      );

  static const initial = ProfileVideosState(
    videos: [],
    isLoading: false,
    isLoadingMore: false,
    hasMore: true,
    error: null,
    lastTimestamp: null,
  );

  bool get hasVideos => videos.isNotEmpty;
  bool get hasError => error != null;
  int get videoCount => videos.length;
}

// Cache for different users' videos
final Map<String, List<VideoEvent>> _profileVideosCache = {};
final Map<String, DateTime> _profileVideosCacheTimestamps = {};
final Map<String, bool> _profileVideosHasMoreCache = {};
const Duration _profileVideosCacheExpiry = Duration(minutes: 10);

// Pagination settings
const int _profileVideosPageSize = 200;

/// Get cached videos if available and not expired
List<VideoEvent>? _getCachedProfileVideos(String pubkey) {
  final videos = _profileVideosCache[pubkey];
  final timestamp = _profileVideosCacheTimestamps[pubkey];

  if (videos != null && timestamp != null) {
    final age = DateTime.now().difference(timestamp);
    if (age < _profileVideosCacheExpiry) {
      Log.debug(
          '📱 Using cached videos for ${pubkey.substring(0, 8)} (age: ${age.inMinutes}min)',
          name: 'ProfileVideosProvider',
          category: LogCategory.ui);
      return videos;
    } else {
      Log.debug(
          '⏰ Video cache expired for ${pubkey.substring(0, 8)} (age: ${age.inMinutes}min)',
          name: 'ProfileVideosProvider',
          category: LogCategory.ui);
      _clearProfileVideosCache(pubkey);
    }
  }

  return null;
}

/// Cache videos for a user
void _cacheProfileVideos(String pubkey, List<VideoEvent> videos, bool hasMore) {
  _profileVideosCache[pubkey] = videos;
  _profileVideosCacheTimestamps[pubkey] = DateTime.now();
  _profileVideosHasMoreCache[pubkey] = hasMore;
  Log.debug('📱 Cached ${videos.length} videos for ${pubkey.substring(0, 8)}',
      name: 'ProfileVideosProvider', category: LogCategory.ui);
}

/// Clear cache for a specific user
void _clearProfileVideosCache(String pubkey) {
  _profileVideosCache.remove(pubkey);
  _profileVideosCacheTimestamps.remove(pubkey);
  _profileVideosHasMoreCache.remove(pubkey);
}

/// Clear all cached videos
void clearAllProfileVideosCache() {
  _profileVideosCache.clear();
  _profileVideosCacheTimestamps.clear();
  _profileVideosHasMoreCache.clear();
  Log.debug('📱 Cleared all profile videos cache',
      name: 'ProfileVideosProvider', category: LogCategory.ui);
}

/// Async provider for loading profile videos
@riverpod
Future<List<VideoEvent>> profileVideos(Ref ref, String pubkey) async {
  // Check cache first
  final cached = _getCachedProfileVideos(pubkey);
  if (cached != null) {
    return cached;
  }

  // Get services from app providers
  final nostrService = ref.watch(nostrServiceProvider);
  final videoEventService = ref.watch(videoEventServiceProvider);

  Log.info(
      '📱 Loading videos for user: ${pubkey.substring(0, 8)}... (full: ${pubkey.substring(0, 16)})',
      name: 'ProfileVideosProvider',
      category: LogCategory.ui);

  try {
    // First check VideoEventService cache for any videos by this author
    final cachedVideos = videoEventService.getVideosByAuthor(pubkey);
    if (cachedVideos.isNotEmpty) {
      Log.info(
          '📱 Found ${cachedVideos.length} cached videos for ${pubkey.substring(0, 8)} in VideoEventService',
          name: 'ProfileVideosProvider',
          category: LogCategory.ui);
    }

    // Fetch complete profile videos from network to augment cache
    final filter = Filter(
      authors: [pubkey],
      kinds: [32222], // NIP-32222 addressable short videos
      limit: _profileVideosPageSize,
    );

    Log.info(
        '📱 Querying for videos: authors=[${pubkey.substring(0, 16)}], kinds=[32222], limit=$_profileVideosPageSize',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);

    final completer = Completer<List<VideoEvent>>();
    // Start with cached videos to show immediately
    final videos = <VideoEvent>[...cachedVideos];
    final seenIds = <String>{...cachedVideos.map((v) => v.id)};

    final subscription = nostrService.subscribeToEvents(
      filters: [filter],
      onEose: () {
        Log.info(
            '📱 Streaming EOSE: received ${videos.length} events for ${pubkey.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);
        if (!completer.isCompleted) {
          completer.complete(videos);
        }
      },
    );

    subscription.listen(
      (event) {
        // Process events immediately as they arrive
        try {
          final videoEvent = VideoEvent.fromNostrEvent(event);
          // Only add if we haven't seen this video before
          if (!seenIds.contains(videoEvent.id)) {
            videos.add(videoEvent);
            seenIds.add(videoEvent.id);

            Log.debug(
                '📱 Received new video event ${videoEvent.id.substring(0, 8)} for ${pubkey.substring(0, 8)}',
                name: 'ProfileVideosProvider',
                category: LogCategory.ui);
          } else {
            Log.debug(
                '📱 Skipping duplicate video event ${videoEvent.id.substring(0, 8)}',
                name: 'ProfileVideosProvider',
                category: LogCategory.ui);
          }
        } catch (e) {
          Log.warning('Failed to parse video event: $e',
              name: 'ProfileVideosProvider', category: LogCategory.ui);
        }
      },
      onError: (error) {
        Log.error('Error fetching profile videos: $error',
            name: 'ProfileVideosProvider', category: LogCategory.ui);
        if (!completer.isCompleted) {
          completer.complete(videos);
        }
      },
      onDone: () {
        Log.info(
            '📱 Query completed: received ${videos.length} events for ${pubkey.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);

        if (!completer.isCompleted) {
          completer.complete(videos);
        }
      },
    );

    // Timeout for fetching - complete with whatever we have so far
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        Log.info(
            '📱 Timeout reached: completing with ${videos.length} videos for ${pubkey.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);
        completer.complete(videos);
      }
    });

    final finalVideos = await completer.future;

    // Sort using loops-first policy
    finalVideos.sort(VideoEvent.compareByLoopsThenTime);

    // Cache the results
    _cacheProfileVideos(
        pubkey, finalVideos, finalVideos.length >= _profileVideosPageSize);

    Log.info(
        '📱 Loaded ${finalVideos.length} videos for ${pubkey.substring(0, 8)}',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);

    return finalVideos;
  } catch (e) {
    Log.error('Error loading profile videos: $e',
        name: 'ProfileVideosProvider', category: LogCategory.ui);
    rethrow;
  }
}

/// Notifier for managing profile videos state
@Riverpod(keepAlive: true)
class ProfileVideosNotifier extends _$ProfileVideosNotifier {
  String? _currentPubkey;
  Completer<void>? _loadingCompleter;

  @override
  ProfileVideosState build() {
    return ProfileVideosState.initial;
  }

  /// Load videos for a specific user with real-time streaming
  Future<void> loadVideosForUser(String pubkey) async {
    if (_currentPubkey == pubkey && state.hasVideos && !state.hasError) {
      // Already loaded for this user
      return;
    }

    // Prevent concurrent loads for the same user
    if (_loadingCompleter != null && _currentPubkey == pubkey) {
      return _loadingCompleter!.future;
    }

    _loadingCompleter = Completer<void>();
    _currentPubkey = pubkey;

    // Check cache first
    final cached = _getCachedProfileVideos(pubkey);
    if (cached != null) {
      // Defer state modification to avoid modifying provider during build
      await Future.microtask(() {
        state = state.copyWith(
          videos: cached,
          isLoading: false,
          hasMore: _profileVideosHasMoreCache[pubkey] ?? true,
          error: null,
        );
      });
      _loadingCompleter!.complete();
      _loadingCompleter = null;
      return;
    }

    // Defer state modification to avoid modifying provider during build
    await Future.microtask(() {
      state = state.copyWith(
        isLoading: true,
        videos: [],
        error: null,
        hasMore: true,
        lastTimestamp: null,
      );
    });

    try {
      // Use streaming approach for real-time video updates
      await _loadVideosStreaming(pubkey);
      _loadingCompleter!.complete();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      _loadingCompleter!.completeError(e);
    } finally {
      _loadingCompleter = null;
    }
  }

  /// Stream videos with real-time UI updates as they arrive
  Future<void> _loadVideosStreaming(String pubkey) async {
    final nostrService = ref.read(nostrServiceProvider);
    final videoEventService = ref.read(videoEventServiceProvider);

    // First, get any cached videos for immediate display
    final cachedVideos = videoEventService.getVideosByAuthor(pubkey);
    if (cachedVideos.isNotEmpty) {
      Log.info(
          '📱 Found ${cachedVideos.length} cached videos for ${pubkey.substring(0, 8)} in VideoEventService',
          name: 'ProfileVideosProvider',
          category: LogCategory.ui);

      // Sort and update UI immediately with cached videos
      final sortedCached = List<VideoEvent>.from(cachedVideos);
      sortedCached.sort(VideoEvent.compareByLoopsThenTime);

      state = state.copyWith(
        videos: sortedCached,
        lastTimestamp:
            sortedCached.isNotEmpty ? sortedCached.last.createdAt : null,
      );
    }

    final filter = Filter(
      authors: [pubkey],
      kinds: [32222], // NIP-32222 addressable short videos
      limit: _profileVideosPageSize,
    );

    Log.info(
        '📱 Starting streaming query for videos: authors=[${pubkey.substring(0, 16)}], kinds=[32222], limit=$_profileVideosPageSize',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);

    final completer = Completer<void>();
    // Start with cached videos
    final receivedVideos = <VideoEvent>[...cachedVideos];
    final seenIds = <String>{...cachedVideos.map((v) => v.id)};

    final subscription = nostrService.subscribeToEvents(
      filters: [filter],
      onEose: () {
        Log.info(
            '📱 Streaming EOSE: received ${receivedVideos.length} events for ${pubkey.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);
        if (!completer.isCompleted) {
          _finalizeStreamingLoad(pubkey, receivedVideos);
          completer.complete();
        }
      },
    );

    subscription.listen(
      (event) {
        // Process events immediately and update UI progressively
        try {
          final videoEvent = VideoEvent.fromNostrEvent(event);
          // Only add if we haven't seen this video before
          if (!seenIds.contains(videoEvent.id)) {
            receivedVideos.add(videoEvent);
            seenIds.add(videoEvent.id);

            Log.debug(
                '📱 Streaming: received new video event ${videoEvent.id.substring(0, 8)} for ${pubkey.substring(0, 8)}',
                name: 'ProfileVideosProvider',
                category: LogCategory.ui);

            // Update UI state immediately with new video
            _updateUIWithStreamingVideo(videoEvent, receivedVideos);
          } else {
            Log.debug(
                '📱 Streaming: skipping duplicate video event ${videoEvent.id.substring(0, 8)}',
                name: 'ProfileVideosProvider',
                category: LogCategory.ui);
          }
        } catch (e) {
          Log.warning('Failed to parse streaming video event: $e',
              name: 'ProfileVideosProvider', category: LogCategory.ui);
        }
      },
      onError: (error) {
        Log.error('Error streaming profile videos: $error',
            name: 'ProfileVideosProvider', category: LogCategory.ui);
        if (!completer.isCompleted) {
          _finalizeStreamingLoad(pubkey, receivedVideos);
          completer.complete();
        }
      },
      onDone: () {
        Log.info(
            '📱 Streaming query completed: received ${receivedVideos.length} events for ${pubkey.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);

        if (!completer.isCompleted) {
          _finalizeStreamingLoad(pubkey, receivedVideos);
          completer.complete();
        }
      },
    );

    // Completion is driven by EOSE; no timer fallback

    await completer.future;
  }

  /// Update UI state immediately when each video arrives during streaming
  void _updateUIWithStreamingVideo(
      VideoEvent newVideo, List<VideoEvent> allReceived) {
    // Add the new video to current state, maintaining sort order
    final currentVideos = List<VideoEvent>.from(state.videos);
    currentVideos.add(newVideo);

    // Sort using loops-first policy
    currentVideos.sort(VideoEvent.compareByLoopsThenTime);

    // Update state with progressive loading
    state = state.copyWith(
      videos: currentVideos,
      lastTimestamp:
          currentVideos.isNotEmpty ? currentVideos.last.createdAt : null,
    );

    Log.debug(
        '📱 Streaming UI update: now showing ${currentVideos.length} videos',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);
  }

  /// Finalize the streaming load and update cache
  void _finalizeStreamingLoad(String pubkey, List<VideoEvent> allVideos) {
    // Final sort using loops-first policy
    allVideos.sort(VideoEvent.compareByLoopsThenTime);

    // Update final state
    state = state.copyWith(
      videos: allVideos,
      isLoading: false,
      hasMore: allVideos.length >= _profileVideosPageSize,
      lastTimestamp: allVideos.isNotEmpty ? allVideos.last.createdAt : null,
    );

    // Cache the results
    _cacheProfileVideos(
        pubkey, allVideos, allVideos.length >= _profileVideosPageSize);

    Log.info(
        '📱 Streaming finalized: loaded ${allVideos.length} videos for ${pubkey.substring(0, 8)}',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);
  }

  /// Load more videos (pagination) with streaming updates
  Future<void> loadMoreVideos() async {
    if (_currentPubkey == null ||
        state.isLoadingMore ||
        !state.hasMore ||
        state.lastTimestamp == null) {
      return;
    }

    // Defer state modification to avoid modifying provider during build
    await Future.microtask(() {
      state = state.copyWith(isLoadingMore: true, error: null);
    });

    try {
      await _loadMoreVideosStreaming();
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
      Log.error('Error loading more videos: $e',
          name: 'ProfileVideosProvider', category: LogCategory.ui);
    }
  }

  /// Stream additional videos with real-time UI updates as they arrive
  Future<void> _loadMoreVideosStreaming() async {
    final nostrService = ref.read(nostrServiceProvider);

    final filter = Filter(
      authors: [_currentPubkey!],
      kinds: [32222], // NIP-32222 addressable video events
      until: state.lastTimestamp! - 1, // Load older videos
      limit: _profileVideosPageSize,
    );

    Log.info(
        '📱 Starting streaming load more query for ${_currentPubkey!.substring(0, 8)}: until=${state.lastTimestamp! - 1}, limit=$_profileVideosPageSize',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);

    final completer = Completer<void>();
    final newVideos = <VideoEvent>[];

    final subscription = nostrService.subscribeToEvents(
      filters: [filter],
      onEose: () {
        Log.info(
            '📱 Load more EOSE: received ${newVideos.length} additional events for ${_currentPubkey!.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);
        if (!completer.isCompleted) {
          _finalizeLoadMoreStreaming(newVideos);
          completer.complete();
        }
      },
    );

    subscription.listen(
      (event) {
        // Process events immediately and update UI progressively
        try {
          final videoEvent = VideoEvent.fromNostrEvent(event);
          newVideos.add(videoEvent);

          Log.debug(
              '📱 Load more streaming: received video event ${videoEvent.id.substring(0, 8)} for ${_currentPubkey!.substring(0, 8)}',
              name: 'ProfileVideosProvider',
              category: LogCategory.ui);

          // Update UI state immediately with new video
          _updateUIWithAdditionalVideo(videoEvent);
        } catch (e) {
          Log.warning('Failed to parse additional streaming video event: $e',
              name: 'ProfileVideosProvider', category: LogCategory.ui);
        }
      },
      onError: (error) {
        Log.error('Error streaming additional videos: $error',
            name: 'ProfileVideosProvider', category: LogCategory.ui);
        if (!completer.isCompleted) {
          _finalizeLoadMoreStreaming(newVideos);
          completer.complete();
        }
      },
      onDone: () {
        Log.info(
            '📱 Load more streaming completed: received ${newVideos.length} additional events for ${_currentPubkey!.substring(0, 8)}',
            name: 'ProfileVideosProvider',
            category: LogCategory.ui);

        if (!completer.isCompleted) {
          _finalizeLoadMoreStreaming(newVideos);
          completer.complete();
        }
      },
    );

    // Completion is driven by EOSE; no timer fallback

    await completer.future;
  }

  /// Update UI state immediately when each additional video arrives during load more streaming
  void _updateUIWithAdditionalVideo(VideoEvent newVideo) {
    // Add the new video to current state
    final currentVideos = List<VideoEvent>.from(state.videos);
    currentVideos.add(newVideo);

    // Sort using loops-first policy
    currentVideos.sort(VideoEvent.compareByLoopsThenTime);

    // Update state with progressive loading
    state = state.copyWith(
      videos: currentVideos,
      lastTimestamp:
          currentVideos.isNotEmpty ? currentVideos.last.createdAt : null,
    );

    Log.debug(
        '📱 Load more streaming UI update: now showing ${currentVideos.length} videos',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);
  }

  /// Finalize the load more streaming and update cache
  void _finalizeLoadMoreStreaming(List<VideoEvent> newVideos) {
    final hasMore = newVideos.length >= _profileVideosPageSize;

    // Update final state
    state = state.copyWith(
      isLoadingMore: false,
      hasMore: hasMore,
    );

    // Update cache with current videos
    _cacheProfileVideos(_currentPubkey!, state.videos, hasMore);

    Log.info(
        '📱 Load more streaming finalized: added ${newVideos.length} videos (total: ${state.videos.length})',
        name: 'ProfileVideosProvider',
        category: LogCategory.ui);
  }

  /// Refresh videos by clearing cache and reloading
  Future<void> refreshVideos() async {
    if (_currentPubkey != null) {
      _clearProfileVideosCache(_currentPubkey!);
      ref.invalidate(profileVideosProvider(_currentPubkey!));
      await loadVideosForUser(_currentPubkey!);
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Add a new video to the current list (for optimistic updates)
  void addVideo(VideoEvent video) {
    if (_currentPubkey != null && video.pubkey == _currentPubkey) {
      final updatedVideos = [video, ...state.videos];
      state = state.copyWith(videos: updatedVideos);

      // Update cache
      _cacheProfileVideos(_currentPubkey!, updatedVideos, state.hasMore);
    }
  }

  /// Remove a video from the current list
  void removeVideo(String videoId) {
    final updatedVideos = state.videos.where((v) => v.id != videoId).toList();
    state = state.copyWith(videos: updatedVideos);

    // Update cache if we have a current pubkey
    if (_currentPubkey != null) {
      _cacheProfileVideos(_currentPubkey!, updatedVideos, state.hasMore);
    }
  }
}
