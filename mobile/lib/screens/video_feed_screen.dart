// ABOUTME: TDD-driven video feed screen implementation with single source of truth
// ABOUTME: Memory-efficient PageView with intelligent preloading and error boundaries

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/models/video_state.dart';
import 'package:openvine/providers/home_feed_provider.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/providers/social_providers.dart' as social;
import 'package:openvine/main.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:openvine/state/video_feed_state.dart';

/// Feed context for filtering videos
enum FeedContext {
  general, // All videos (default feed)
  hashtag, // Videos from specific hashtag
  editorsPicks, // Curated videos
  trending, // Trending content
  userProfile, // User's videos
  search, // Search results videos
}

/// Main video feed screen implementing TDD specifications with Riverpod
///
/// Key features:
/// - Reactive Riverpod state management
/// - Single source of truth video management
/// - Memory-bounded operation (<500MB)
/// - Intelligent preloading around current position
/// - Error boundaries for individual videos
/// - Accessibility support
/// - Lifecycle management (pause on background, resume on foreground)
/// - Context-aware content filtering
class VideoFeedScreen extends ConsumerStatefulWidget {
  // hashtag name, user pubkey, etc.

  const VideoFeedScreen({
    super.key,
    this.startingVideo,
    this.context = FeedContext.general,
    this.contextValue,
  });
  final VideoEvent? startingVideo;
  final FeedContext context;
  final String? contextValue;

  @override
  ConsumerState<VideoFeedScreen> createState() => _VideoFeedScreenState();

  /// Static method to pause videos - called from external components
  static void pauseVideos(GlobalKey<State<VideoFeedScreen>> key) {
    final state = key.currentState;
    if (state is _VideoFeedScreenState) {
      state.pauseVideos();
    }
  }

  /// Static method to resume videos - called from external components
  static void resumeVideos(GlobalKey<State<VideoFeedScreen>> key) {
    final state = key.currentState;
    if (state is _VideoFeedScreenState) {
      state.resumeVideos();
    }
  }

  /// Static method to get current video - called from external components
  static VideoEvent? getCurrentVideo(GlobalKey<State<VideoFeedScreen>> key) {
    final state = key.currentState;
    if (state is _VideoFeedScreenState) {
      return state.getCurrentVideo();
    }
    return null;
  }

  /// Static method to scroll to top and refresh - called from external components
  static void scrollToTopAndRefresh(GlobalKey<State<VideoFeedScreen>> key) {
    final state = key.currentState;
    if (state is _VideoFeedScreenState) {
      state.scrollToTopAndRefresh();
    }
  }
}

class _VideoFeedScreenState extends ConsumerState<VideoFeedScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isRefreshing = false; // Track if feed is currently refreshing

  @override
  bool get wantKeepAlive => true; // Keep state alive when using IndexedStack

  @override
  void initState() {
    super.initState();
    Log.info('🎬 VideoFeedScreen: initState called',
        name: 'VideoFeedScreen', category: LogCategory.ui);

    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);

    // Feed mode removed - each screen manages its own content
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();

    // Pause all videos when screen is disposed
    _pauseAllVideos();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pauseAllVideos();
      case AppLifecycleState.resumed:
        _resumeCurrentVideo();
      case AppLifecycleState.detached:
        _pauseAllVideos();
      case AppLifecycleState.hidden:
        _pauseAllVideos();
    }
  }

  void _onPageChanged(int index) {
    // Store the previous index before updating
    final previousIndex = _currentIndex;

    setState(() {
      _currentIndex = index;
    });

    // Get current videos from home feed state
    final feedState = ref.read(homeFeedProvider).valueOrNull;
    if (feedState == null) return;

    final videos = feedState.videos;
    if (videos.isEmpty) return;

    // Simple bounds check
    if (index < 0 || index >= videos.length) {
      return;
    }

    // Check if we're near the end and should load more videos
    _checkForPagination(index, videos.length);

    // Trigger preloading around new position
    ref.read(videoManagerProvider.notifier).preloadAroundIndex(index);

    // Batch fetch profiles for videos around current position
    _batchFetchProfilesAroundIndex(index, videos);

    // Update video playback states with both old and new indices
    _updateVideoPlayback(index, videos, previousIndex);
  }

  void _updateVideoPlayback(
      int videoIndex, List<VideoEvent> videos, int previousPageIndex) {
    if (videoIndex < 0 || videoIndex >= videos.length) return;

    // Immediately pause ALL videos first to ensure clean state
    _pauseAllVideos();

    // Then play only the current video
    final currentVideo = videos[videoIndex];
    _playVideo(currentVideo.id);
  }

  void _playVideo(String videoId) {
    try {
      // The video will be played by the VideoFeedItem when it detects it's active
      // We just need to ensure the video is preloaded
      ref.read(videoManagerProvider.notifier).preloadVideo(videoId);
      Log.debug('Requested play for video: ${videoId.substring(0, 8)}...',
          name: 'VideoFeedScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('Error playing video $videoId: $e',
          name: 'VideoFeedScreen', category: LogCategory.ui);
    }
  }

  void _pauseAllVideos() {
    try {
      ref.read(videoManagerProvider.notifier).pauseAllVideos();
      Log.debug('Paused all videos in feed',
          name: 'VideoFeedScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('Error pausing all videos: $e',
          name: 'VideoFeedScreen', category: LogCategory.ui);
    }
  }

  /// Public method to pause videos from external sources (like navigation)
  void pauseVideos() {
    _pauseAllVideos();
  }

  /// Public method to resume videos from external sources (like navigation)
  void resumeVideos() {
    _resumeCurrentVideo();

    // Also trigger preloading around current position to reload videos that were stopped
    final feedState = ref.read(homeFeedProvider).valueOrNull;
    if (feedState != null && feedState.videos.isNotEmpty) {
      ref.read(videoManagerProvider.notifier).preloadAroundIndex(_currentIndex);
      Log.debug(
          '▶️ Triggered preloading around index $_currentIndex when resuming feed',
          name: 'VideoFeedScreen',
          category: LogCategory.ui);
    }
  }

  // Context filtering is now handled by Riverpod feed mode providers

  void _resumeCurrentVideo() {
    final feedState = ref.read(homeFeedProvider).valueOrNull;
    if (feedState == null) return;

    final videos = feedState.videos;
    if (_currentIndex < videos.length) {
      final currentVideo = videos[_currentIndex];

      // Check if video needs to be preloaded first
      final videoState = ref.read(videoStateByIdProvider(currentVideo.id));
      if (videoState?.loadingState == VideoLoadingState.notLoaded) {
        Log.debug(
            'Current video needs reload, preloading: ${currentVideo.id.substring(0, 8)}...',
            name: 'VideoFeedScreen',
            category: LogCategory.ui);
        ref.read(videoManagerProvider.notifier).preloadVideo(currentVideo.id);
      }

      _playVideo(currentVideo.id);
    }
  }

  /// Get the currently displayed video
  VideoEvent? getCurrentVideo() {
    final feedState = ref.read(homeFeedProvider).valueOrNull;
    if (feedState == null) return null;

    final videos = feedState.videos;
    if (_currentIndex >= 0 && _currentIndex < videos.length) {
      return videos[_currentIndex];
    }
    return null;
  }

  /// Scroll to top and refresh the feed
  void scrollToTopAndRefresh() {
    // Scroll to top
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );

      // Trigger refresh after scroll completes
      Future.delayed(const Duration(milliseconds: 600), _handleRefresh);
    } else {
      // If already at top or no clients, just refresh
      _handleRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    Log.info('🎬 VideoFeedScreen: build() called',
        name: 'VideoFeedScreen', category: LogCategory.ui);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: VineTheme.vineGreen,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'divine',
          style: GoogleFonts.pacifico(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      body: SafeArea(
        top: false, // AppBar handles top safe area
        bottom: false, // Let videos extend to bottom for full screen
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    Log.info('🎬 VideoFeedScreen: _buildBody called',
        name: 'VideoFeedScreen', category: LogCategory.ui);

    // Watch the home feed state
    final videoFeedAsync = ref.watch(homeFeedProvider);

    Log.info(
        '🎬 VideoFeedScreen: videoFeedAsync state = ${videoFeedAsync.runtimeType}',
        name: 'VideoFeedScreen',
        category: LogCategory.ui);

    // Watch the video manager provider to ensure it gets instantiated and syncs videos
    ref.watch(videoManagerProvider);

    return videoFeedAsync.when(
      loading: () {
        Log.info('🎬 VideoFeedScreen: Showing loading state',
            name: 'VideoFeedScreen', category: LogCategory.ui);
        return _buildLoadingState();
      },
      error: (error, stackTrace) {
        Log.error('🎬 VideoFeedScreen: Error state - $error',
            name: 'VideoFeedScreen', category: LogCategory.ui);
        return _buildErrorState(error.toString());
      },
      data: (feedState) {
        final videos = feedState.videos;

        if (videos.isEmpty) {
          return _buildEmptyState();
        }

        return _buildVideoFeed(videos, feedState);
      },
    );
  }

  Widget _buildLoadingState() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading videos...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );

  Widget _buildEmptyState() {
    // Check if user is following anyone to show appropriate message
    final socialData = ref.watch(social.socialNotifierProvider);
    final isFollowingAnyone = socialData.followingPubkeys.isNotEmpty;

    Log.info(
        '🔍 VideoFeedScreen: Empty state - '
        'isFollowingAnyone=$isFollowingAnyone, '
        'socialInitialized=${socialData.isInitialized}, '
        'followingCount=${socialData.followingPubkeys.length}',
        name: 'VideoFeedScreen',
        category: LogCategory.ui);

    if (!isFollowingAnyone) {
      // Show educational message about divine's non-algorithmic approach
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.people_outline,
                size: 64,
                color: Colors.white54,
              ),
              const SizedBox(height: 24),
              const Text(
                'Your Feed, Your Choice',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'divine doesn\'t give you an algorithmic feed.\nYou choose who you follow.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Text(
                'Start following viners to see their posts here,\nor explore new content to discover creators.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // Switch to explore tab
                  final mainNavState = mainNavigationKey.currentState;
                  if (mainNavState != null) {
                    mainNavState.switchToTab(2); // Explore tab index
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VineTheme.vineGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('Explore Vines'),
              ),
            ],
          ),
        ),
      );
    } else {
      // Show standard empty state for users who are following people
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: Colors.white54,
            ),
            SizedBox(height: 16),
            Text(
              'No videos available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Check your connection and try again',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildErrorState(String error) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Error loading videos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(homeFeedProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _buildVideoFeed(List<VideoEvent> videos, VideoFeedState feedState) {
    Log.info(
        '🎬 VideoFeedScreen: Building home video feed with ${videos.length} videos from following',
        name: 'VideoFeedScreen',
        category: LogCategory.ui);

    return Semantics(
      label: 'Video feed',
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Track user scrolling to prevent rebuilds during interaction
              if (notification is ScrollStartNotification) {
                Log.info('📱 User started scrolling',
                    name: 'FeedScreenV2', category: LogCategory.ui);

                // Immediately pause all videos when scrolling starts
                _pauseAllVideos();
              } else if (notification is ScrollEndNotification) {
                Log.info('📱 User stopped scrolling',
                    name: 'FeedScreenV2', category: LogCategory.ui);

                // Check for pull-to-refresh at the top
                if (_currentIndex == 0 && notification.metrics.pixels < -50) {
                  _handleRefresh();
                }

                // Resume the current video after scrolling ends
                if (videos.isNotEmpty && _currentIndex < videos.length) {
                  final currentVideo = videos[_currentIndex];
                  _playVideo(currentVideo.id);
                }
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: videos.length,
              pageSnapping: true,
              itemBuilder: (context, index) {
                // No transition indicators needed - simple discovery feed

                // Simple index - no adjustments needed
                final videoIndex = index;

                // Bounds checking
                if (videoIndex < 0 || videoIndex >= videos.length) {
                  return _buildErrorItem('Index out of bounds');
                }

                final video = videos[videoIndex];
                final isActive = index == _currentIndex;

                // Error boundary for individual videos
                return _buildVideoItemWithErrorBoundary(video, isActive);
              },
            ),
          ),

          // Pull-to-refresh indicator overlay
          if (_isRefreshing && _currentIndex == 0)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Refreshing feed...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoItemWithErrorBoundary(VideoEvent video, bool isActive) {
    try {
      return VideoFeedItem(
        video: video,
        isActive: isActive,
        onVideoError: (error) => _handleVideoError(video.id, error),
        tabContext: TabContext.feed,
      );
    } catch (e) {
      // Error boundary - prevent one bad video from crashing entire feed
      Log.error('FeedScreenV2: Error creating video item ${video.id}: $e',
          name: 'FeedScreenV2', category: LogCategory.ui);
      return _buildErrorItem('Error loading video: ${video.title ?? video.id}');
    }
  }

  Widget _buildErrorItem(String message) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Go Back'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Trigger refresh
                      setState(() {});
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  void _handleVideoError(String videoId, String error) {
    Log.error('FeedScreenV2: Video error for $videoId: $error',
        name: 'FeedScreenV2', category: LogCategory.ui);
    // Error handling would be implemented here
    // For now, just log the error
  }

  DateTime? _lastPaginationCall;

  /// Check if we're near the end of the video list and should load more content
  void _checkForPagination(int currentIndex, int totalVideos) {
    // Load more when we're 3 videos away from the end
    const paginationThreshold = 3;

    if (currentIndex >= totalVideos - paginationThreshold) {
      // Rate limit pagination calls to prevent spam
      final now = DateTime.now();
      if (_lastPaginationCall != null &&
          now.difference(_lastPaginationCall!).inSeconds < 5) {
        Log.debug(
          'VideoFeed: Skipping pagination - too soon since last call',
          name: 'VideoFeedScreen',
          category: LogCategory.video,
        );
        return;
      }

      _lastPaginationCall = now;

      Log.info(
        'VideoFeed: Near end of videos ($currentIndex/$totalVideos), loading more...',
        name: 'VideoFeedScreen',
        category: LogCategory.video,
      );

      // Call the home feed provider's loadMore method
      ref.read(homeFeedProvider.notifier).loadMore();
    }
  }

  /// Handle pull-to-refresh functionality
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      Log.info('🔄 Pull-to-refresh triggered - refreshing feed',
          name: 'VideoFeedScreen', category: LogCategory.ui);

      // Refresh the home feed using Riverpod
      await ref.read(homeFeedProvider.notifier).refresh();

      Log.info('✅ Feed refresh completed',
          name: 'VideoFeedScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('❌ Feed refresh failed: $e',
          name: 'VideoFeedScreen', category: LogCategory.ui);

      // Show error feedback to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to refresh feed'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// Batch fetch profiles for videos around the current position
  void _batchFetchProfilesAroundIndex(
      int currentIndex, List<VideoEvent> videos) {
    if (videos.isEmpty) return;

    // Only fetch profile for the currently visible video
    // This prevents creating hundreds of relay subscriptions
    final currentVideo = videos[currentIndex];
    final pubkeysToFetch = <String>{};
    final userProfilesNotifier = ref.read(userProfileNotifierProvider.notifier);

    // Only add pubkey if we don't have the profile yet
    if (!userProfilesNotifier.hasProfile(currentVideo.pubkey)) {
      pubkeysToFetch.add(currentVideo.pubkey);
    }

    if (pubkeysToFetch.isEmpty) return;

    Log.debug(
      '⚡ Lazy loading profile for visible video at index $currentIndex',
      name: 'VideoFeedScreen',
      category: LogCategory.ui,
    );

    // Fetch profile only for the currently visible video
    userProfilesNotifier.prefetchProfilesImmediately(pubkeysToFetch.toList());
  }

  // Note: Keyboard navigation methods removed to avoid unused warnings
  // Would be implemented for accessibility support when needed
}

/// Error widget for video loading failures
class VideoErrorWidget extends StatelessWidget {
  const VideoErrorWidget({
    required this.message,
    super.key,
    this.onRetry,
    this.onGoBack,
  });
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Network error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (onGoBack != null || onRetry != null) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (onGoBack != null) ...[
                      ElevatedButton(
                        onPressed: onGoBack,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Go Back'),
                      ),
                      if (onRetry != null) const SizedBox(width: 16),
                    ],
                    if (onRetry != null)
                      ElevatedButton(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}
