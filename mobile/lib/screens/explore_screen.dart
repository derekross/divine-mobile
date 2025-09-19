// ABOUTME: Explore screen showing trending content, Editor's Picks, and Popular Now sections
// ABOUTME: Displays curated content similar to original Vine's explore tab

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:openvine/models/curation_set.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/screens/hashtag_feed_screen.dart';
import 'package:openvine/screens/search_screen.dart';
import 'package:openvine/services/top_hashtags_service.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_explore_tile.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/curation_providers.dart'
    as curation_providers;
import 'package:openvine/providers/video_events_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/services/video_event_service.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => ExploreScreenState();
}

// Made public to allow access from MainNavigationScreen
class ExploreScreenState extends ConsumerState<ExploreScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  String? _selectedHashtag;
  String? _playingVideoId;
  int _currentVideoIndex = 0;
  List<VideoEvent> _currentTabVideos = [];
  bool _isInFeedMode = false; // Track if we're in full feed mode vs grid mode

  // Tab tap tracking for double-tap detection
  DateTime? _lastTabTap;
  int? _lastTappedIndex;

  // Pagination state for grid views
  int _popularNowLimit = 50;
  int _trendingLimit = 100;
  bool _isLoadingMorePopular = false;
  bool _isLoadingMoreTrending = false;

  // Hashtag pagination state
  int _editorsHashtagLimit = 25;
  final int _trendingHashtagLimit = 25;
  bool _isLoadingMoreEditorsHashtags = false;
  // Removed _isLoadingMoreTrendingHashtags - now using infinite scrolling

  // Track if the explore screen is actually visible
  bool _isScreenVisible = false;
  // Track if trending has been fetched for this session
  bool _hasFetchedTrending = false;

  // Pagination tracking for automatic loading
  DateTime? _lastPaginationCall;

  // Track hashtag video loading
  int? _oldestHashtagVideoTimestamp;

  // One-time guard to avoid repeatedly starting discovery from Trending grid builds
  bool _discoveryStartedForHashtags = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);

    // Listen for tab changes to close video and reset state
    _tabController.addListener(_onTabChanged);

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Load top hashtags from JSON file
    TopHashtagsService.instance.loadTopHashtags().then((_) {
      if (mounted) {
        setState(() {});
      }
    });

    // Only start discovery if ExploreScreen is visible AND on Popular Now tab
    // This prevents loading videos when user is on Home feed
    // Discovery subscription will be started when user actually navigates to Popular Now
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Called when this screen becomes visible in the navigation
  void onScreenVisible() {
    Log.info('📱 ExploreScreen became visible',
        name: 'ExploreScreen', category: LogCategory.ui);
    _isScreenVisible = true;

    // Ensure tab visibility is set to Explore (index 2) only if needed
    if (ref.read(tabVisibilityProvider) != 2) {
      ref.read(tabVisibilityProvider.notifier).setActiveTab(2);
    }

    // If user is on trending tab and we haven't fetched yet, fetch now
    if (_tabController.index == 2 && !_hasFetchedTrending) {
      Log.info('🔄 Fetching trending on screen visible',
          name: 'ExploreScreen', category: LogCategory.ui);
      _hasFetchedTrending = true;
      final trendingProvider =
          ref.read(curation_providers.analyticsTrendingProvider.notifier);
      trendingProvider.refresh();
    }

    // If a hashtag is selected and we're on trending tab, re-subscribe to ensure we have videos
    if (_tabController.index == 2 && _selectedHashtag != null) {
      Log.info(
          '📍 Re-subscribing to hashtag #$_selectedHashtag on screen visible',
          name: 'ExploreScreen',
          category: LogCategory.ui);
      final hashtagService = ref.read(hashtagServiceProvider);
      hashtagService.subscribeToHashtagVideos([_selectedHashtag!], limit: 100);
    }
  }

  /// Called when this screen becomes hidden in the navigation
  void onScreenHidden() {
    Log.info('📱 ExploreScreen became hidden',
        name: 'ExploreScreen', category: LogCategory.ui);
    _isScreenVisible = false;

    // Pause all videos when screen is hidden.
    // Use main VideoManager directly to avoid circular dependency with exploreVideoManagerProvider
    Future.microtask(() {
      if (!mounted) return;
      try {
        final videoManager = ref.read(videoManagerProvider.notifier);
        videoManager.pauseAllVideos();
      } catch (_) {
        // No-op: if container is disposing during navigation
      }
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      // Pause any playing videos when switching tabs
      // Use main VideoManager directly to avoid circular dependency with exploreVideoManagerProvider
      final videoManager = ref.read(videoManagerProvider.notifier);
      videoManager.pauseAllVideos();

      // Close the currently playing video overlay if any and return to grid mode
      if (_playingVideoId != null || _isInFeedMode) {
        setState(() {
          _playingVideoId = null;
          _currentVideoIndex = 0;
          _currentTabVideos = [];
          _isInFeedMode = false; // Return to grid mode when switching tabs
        });
      }

      // Reset video index for all tabs
      setState(() {
        _currentVideoIndex = 0;
      });

      // Start discovery subscription when switching to Popular Now tab (index 1)
      if (_tabController.index == 1) {
        Log.info(
            '📱 User navigated to Popular Now tab - starting discovery subscription',
            name: 'ExploreScreen',
            category: LogCategory.ui);
        // Start discovery subscription on demand
        ref.read(videoEventsProvider.notifier).startDiscoverySubscription();
      }

      // Trigger refresh when switching to Trending tab (index 2)
      // Only fetch if the screen is actually visible and we haven't fetched yet
      if (_tabController.index == 2 &&
          _isScreenVisible &&
          !_hasFetchedTrending) {
        Log.info('🔄 User navigated to Trending tab - fetching trending videos',
            name: 'ExploreScreen', category: LogCategory.ui);
        _hasFetchedTrending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final trendingProvider =
              ref.read(curation_providers.analyticsTrendingProvider.notifier);
          trendingProvider.refresh();
        });
      }
    }
  }

  /// Handle tab tap to detect double-tap and already-selected tap
  void _handleTabTap(int index) {
    Log.debug(
        '🔄 Tab tapped: index=$index, current=${_tabController.index}, isInFeedMode=$_isInFeedMode',
        name: 'ExploreScreen',
        category: LogCategory.ui);

    // Always pause videos when tapping any tab (whether switching or not)
    // FIXED: Use VideoManager directly to avoid circular dependency
    final videoManager = ref.read(videoManagerProvider.notifier);
    videoManager.pauseAllVideos();

    // Check if tapping on the already selected tab
    if (index == _tabController.index) {
      // If we're in feed mode, exit to grid mode
      if (_isInFeedMode) {
        Log.debug('🔄 Tapping current tab while in feed mode - exiting to grid',
            name: 'ExploreScreen', category: LogCategory.ui);
        _exitFeedMode();
        return;
      }

      // Check for double-tap
      final now = DateTime.now();
      if (_lastTappedIndex == index &&
          _lastTabTap != null &&
          now.difference(_lastTabTap!).inMilliseconds < 500) {
        // Double-tap detected on the same tab - exit feed mode if active
        Log.debug('🔄 Double-tap detected on tab $index',
            name: 'ExploreScreen', category: LogCategory.ui);
        if (_isInFeedMode) {
          _exitFeedMode();
        }
        _lastTabTap = null;
        _lastTappedIndex = null;
      } else {
        // Single tap on already selected tab
        _lastTabTap = now;
        _lastTappedIndex = index;
      }
    } else {
      // Switching to a different tab
      _lastTabTap = null;
      _lastTappedIndex = null;
      _tabController.animateTo(index);
    }
  }

  /// Handle video tap to enter feed mode
  void _enterFeedMode(List<VideoEvent> videos, int startIndex) {
    Log.debug(
        '🎬 Entering feed mode for video ${videos[startIndex].id} at index $startIndex',
        name: 'ExploreScreen',
        category: LogCategory.ui);

    // Pause all videos before entering feed mode
    // FIXED: Use VideoManager directly to avoid circular dependency
    final videoManager = ref.read(videoManagerProvider.notifier);
    videoManager.pauseAllVideos();

    // For videos from analytics API or other sources, we need to add them to VideoManager first
    // This includes: Editor's Picks (index 0), Trending (index 2), and hashtag filtered videos

    // Add all videos to VideoManager first (synchronously before entering feed mode)
    for (final video in videos) {
      try {
        videoManager.addVideoEvent(video);
      } catch (e) {
        // Video might already exist, that's ok
        Log.verbose('Video already in manager: ${video.id}',
            name: 'ExploreScreen', category: LogCategory.ui);
      }
    }

    // DO NOT preload here - let VideoFeedItem handle preloading when it's rendered
    // This avoids timing issues where we try to preload before videos are properly added
    Log.debug('🚀 Added ${videos.length} videos to VideoManager for feed mode',
        name: 'ExploreScreen', category: LogCategory.ui);

    // Batch fetch profiles for visible videos
    // Add a small delay to ensure tab visibility is properly set
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _batchFetchProfilesAroundIndex(startIndex, videos);
    });

    setState(() {
      _isInFeedMode = true;
      _currentTabVideos = videos;
      _currentVideoIndex = startIndex;
      _playingVideoId = videos[startIndex].id;
    });

    // Update oldest timestamp for hashtag videos in feed mode
    if (_selectedHashtag != null && videos.isNotEmpty) {
      _updateOldestHashtagTimestamp(videos);
    }
  }

  /// Exit feed mode and return to grid view
  void _exitFeedMode() {
    // Pause any playing videos when exiting feed mode
    // FIXED: Use VideoManager directly to avoid circular dependency
    final videoManager = ref.read(videoManagerProvider.notifier);
    videoManager.pauseAllVideos();

    setState(() {
      _isInFeedMode = false;
      _playingVideoId = null;
      _currentVideoIndex = 0;
      _currentTabVideos = [];
      _selectedHashtag = null; // Clear hashtag when exiting
    });
  }

  /// Lazy load profile for currently visible video only
  void _batchFetchProfilesAroundIndex(
      int currentIndex, List<VideoEvent> videos) {
    if (videos.isEmpty) return;

    // Only fetch profile for the currently visible video
    // This prevents creating hundreds of relay subscriptions
    final currentVideo = videos[currentIndex];
    final pubkeysToFetch = <String>{};
    final userProfilesNotifier = ref.read(userProfileNotifierProvider.notifier);

    // Only add pubkeys that don't have profiles yet
    if (!userProfilesNotifier.hasProfile(currentVideo.pubkey)) {
      pubkeysToFetch.add(currentVideo.pubkey);
    }

    // Also fetch reposter profile if needed
    if (currentVideo.isRepost &&
        currentVideo.reposterPubkey != null &&
        !userProfilesNotifier.hasProfile(currentVideo.reposterPubkey!)) {
      pubkeysToFetch.add(currentVideo.reposterPubkey!);
    }

    if (pubkeysToFetch.isEmpty) return;

    Log.debug(
      '⚡ Lazy loading ${pubkeysToFetch.length} profile(s) for visible video',
      name: 'ExploreScreen',
      category: LogCategory.ui,
    );

    // Fetch profiles only for the currently visible video
    userProfilesNotifier.prefetchProfilesImmediately(pubkeysToFetch.toList());
  }

  /// Check if currently in feed mode
  bool get isInFeedMode => _isInFeedMode;

  /// Public method to exit feed mode (called from MainNavigationScreen)
  void exitFeedMode() {
    Log.debug(
        '🔄 ExploreScreen.exitFeedMode() called - current feed mode: $_isInFeedMode',
        name: 'ExploreScreen',
        category: LogCategory.ui);
    if (_isInFeedMode) {
      _exitFeedMode();
    } else {
      Log.debug('🔄 Not in feed mode, ignoring exitFeedMode() call',
          name: 'ExploreScreen', category: LogCategory.ui);
    }
  }

  /// Load more popular now videos
  void _loadMorePopularNow() {
    if (_isLoadingMorePopular) return;

    setState(() {
      _isLoadingMorePopular = true;
    });

    // Get current total videos available locally
    final videoEventsAsync = ref.read(videoEventsProvider);
    final totalAvailable = videoEventsAsync.valueOrNull?.length ?? 0;

    Log.info(
        'ExploreScreen: Loading more Popular Now videos - current: $_popularNowLimit, available: $totalAvailable',
        name: 'ExploreScreen',
        category: LogCategory.video);

    // If we have more videos locally, show them first
    if (_popularNowLimit < totalAvailable) {
      Log.info(
          'ExploreScreen: Showing more Popular Now videos from local cache ($_popularNowLimit -> ${_popularNowLimit + 25})',
          name: 'ExploreScreen',
          category: LogCategory.video);

      setState(() {
        _popularNowLimit += 25;
        _isLoadingMorePopular = false;
      });
      return;
    }

    // We've shown all local videos, fetch more from server with pagination
    // Use the provider's loadMoreEvents method which properly calls the service
    final videoEventsNotifier = ref.read(videoEventsProvider.notifier);

    Log.info(
        'ExploreScreen: Fetching historical Popular Now videos via provider loadMoreEvents',
        name: 'ExploreScreen',
        category: LogCategory.video);

    videoEventsNotifier.loadMoreEvents().then((_) {
      // After loading, increase display limit to show the new videos
      // The reactive VideoEventsProvider will automatically update the UI
      if (mounted) {
        // Check if we actually got new videos
        final newTotalAvailable =
            ref.read(videoEventsProvider).valueOrNull?.length ?? 0;
        if (newTotalAvailable > totalAvailable) {
          Log.info(
              'ExploreScreen: Received ${newTotalAvailable - totalAvailable} new videos from relay',
              name: 'ExploreScreen',
              category: LogCategory.video);
          setState(() {
            _popularNowLimit += 25;
            _isLoadingMorePopular = false;
          });
        } else {
          Log.warning(
              'ExploreScreen: No new videos received from relay - may have reached end of content',
              name: 'ExploreScreen',
              category: LogCategory.video);
          setState(() {
            _isLoadingMorePopular = false;
          });
        }
      }
    }).catchError((error) {
      Log.error('ExploreScreen: Error loading more Popular Now videos: $error',
          name: 'ExploreScreen', category: LogCategory.video);
      if (mounted) {
        setState(() {
          _isLoadingMorePopular = false;
        });
      }
    });
  }

  /// Load more trending videos
  void _loadMoreTrending() {
    if (_isLoadingMoreTrending) return;

    setState(() {
      _isLoadingMoreTrending = true;
    });

    Log.info('ExploreScreen: Loading more Trending videos from Analytics API',
        name: 'ExploreScreen', category: LogCategory.video);

    // Get current count before loading
    final currentCount =
        ref.read(curation_providers.analyticsTrendingProvider).length;

    // Load more trending videos from analytics API
    final trendingProvider =
        ref.read(curation_providers.analyticsTrendingProvider.notifier);
    trendingProvider.loadMore().then((_) {
      if (mounted) {
        // Check if we actually got new videos
        final newCount =
            ref.read(curation_providers.analyticsTrendingProvider).length;
        final hasNewVideos = newCount > currentCount;

        setState(() {
          // Only increase limit if we got new videos
          if (hasNewVideos) {
            _trendingLimit += 25;
          }
          _isLoadingMoreTrending = false;
        });

        if (!hasNewVideos) {
          Log.warning(
              'ExploreScreen: No new trending videos loaded - reached end of available content',
              name: 'ExploreScreen',
              category: LogCategory.video);
        }
      }
    }).catchError((error) {
      Log.error('ExploreScreen: Error loading more Trending videos: $error',
          name: 'ExploreScreen', category: LogCategory.video);
      if (mounted) {
        setState(() {
          _isLoadingMoreTrending = false;
        });
      }
    });
  }

  /// Load more editor's pick hashtags
  void _loadMoreEditorsHashtags() {
    if (_isLoadingMoreEditorsHashtags) return;

    setState(() {
      _isLoadingMoreEditorsHashtags = true;
      _editorsHashtagLimit += 10; // Load 10 more hashtags
    });

    // Brief delay to show loading state, then hide it
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isLoadingMoreEditorsHashtags = false;
        });
      }
    });
  }

  // Removed _loadMoreTrendingHashtags - now using infinite scrolling

  /// Play a specific video in feed mode with context videos
  void playSpecificVideo(List<VideoEvent> videos, int startIndex) {
    Log.debug(
        '📱 Playing video ${videos[startIndex].id} from search results (${videos.length} total)',
        name: 'ExploreScreen',
        category: LogCategory.ui);

    // Enter feed mode with all videos in context, starting at the specified index
    _enterFeedMode(videos, startIndex);
  }

  /// Show videos for a specific hashtag
  Future<void> showHashtagVideos(String hashtag) async {
    Log.debug('📍 Showing hashtag videos for: #$hashtag',
        name: 'ExploreScreen', category: LogCategory.ui);

    // Exit feed mode if we're in it
    if (_isInFeedMode) {
      _exitFeedMode();
    }

    // Switch to trending tab for hashtag display
    _tabController.animateTo(2);

    setState(() {
      _selectedHashtag = hashtag;
      _oldestHashtagVideoTimestamp =
          null; // Reset pagination when selecting a new hashtag
    });

    // Subscribe to hashtag videos and wait for them to load
    final hashtagService = ref.read(hashtagServiceProvider);
    final videoService = ref.read(videoEventServiceProvider);
    final nostrService = ref.read(nostrServiceProvider);

    Log.info('📍 Subscribing to hashtag videos for #$hashtag',
        name: 'ExploreScreen', category: LogCategory.ui);
    Log.info('📍 Connected relays: ${nostrService.connectedRelayCount}',
        name: 'ExploreScreen', category: LogCategory.ui);

    // First check if we have cached videos for this hashtag
    var cachedVideos = hashtagService.getVideosByHashtags([hashtag]);
    Log.info('📍 Found ${cachedVideos.length} cached videos for #$hashtag',
        name: 'ExploreScreen', category: LogCategory.ui);

    // Force a new subscription with replace=true to ensure we fetch from relays
    try {
      // Clear any existing hashtag videos first
      Log.info('📍 Creating new subscription for #$hashtag with replace=true',
          name: 'ExploreScreen', category: LogCategory.ui);

      await videoService.subscribeToVideoFeed(
        subscriptionType: SubscriptionType.hashtag,
        hashtags: [hashtag],
        limit: 100,
        replace: true, // Force replace existing subscription
      );

      Log.info('📍 Subscription created, waiting for relay responses...',
          name: 'ExploreScreen', category: LogCategory.ui);

      // Give relays a moment to respond
      await Future.delayed(const Duration(milliseconds: 1500));

      // Check if we have videos after subscription
      final hashtagVideos = videoService.getVideos(SubscriptionType.hashtag);
      Log.info(
          '📍 After delay, VideoService has ${hashtagVideos.length} hashtag videos',
          name: 'ExploreScreen',
          category: LogCategory.ui);

      // Also check what the hashtag service sees
      final fetchedVideos = hashtagService.getVideosByHashtags([hashtag]);
      Log.info(
          '📍 HashtagService found ${fetchedVideos.length} videos for #$hashtag',
          name: 'ExploreScreen',
          category: LogCategory.ui);

      // Log some video IDs for debugging
      if (hashtagVideos.isNotEmpty) {
        final sampleIds =
            hashtagVideos.take(3).map((v) => v.id.substring(0, 8)).join(', ');
        Log.info('📍 Sample video IDs: $sampleIds',
            name: 'ExploreScreen', category: LogCategory.ui);
      }
    } catch (e) {
      Log.error('📍 Failed to subscribe to hashtag videos: $e',
          name: 'ExploreScreen', category: LogCategory.ui);
      // Fall back to cached videos if subscription fails
    }

    // Get videos one more time to check current state
    final videos = hashtagService.getVideosByHashtags([hashtag]);

    // Track the oldest video timestamp for pagination
    if (videos.isNotEmpty) {
      _updateOldestHashtagTimestamp(videos);
    }

    // Force a rebuild after subscription is established
    if (mounted) {
      setState(() {});

      // Also trigger a delayed rebuild to catch videos that arrive shortly after
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _selectedHashtag == hashtag) {
          final delayedVideos = hashtagService.getVideosByHashtags([hashtag]);
          Log.info(
              '📍 Delayed check: found ${delayedVideos.length} videos for #$hashtag',
              name: 'ExploreScreen',
              category: LogCategory.ui);

          // Update oldest timestamp if we got new videos
          if (delayedVideos.isNotEmpty) {
            _updateOldestHashtagTimestamp(delayedVideos);
          }

          setState(() {});
        }
      });
    }
  }

  /// Update the oldest hashtag video timestamp for pagination
  void _updateOldestHashtagTimestamp(List<VideoEvent> videos) {
    if (videos.isEmpty) return;

    // Find the oldest timestamp among the videos
    int? oldestTimestamp;
    for (final video in videos) {
      if (oldestTimestamp == null || video.createdAt < oldestTimestamp) {
        oldestTimestamp = video.createdAt;
      }
    }

    // Update if we found an older timestamp
    if (oldestTimestamp != null &&
        (_oldestHashtagVideoTimestamp == null ||
            oldestTimestamp < _oldestHashtagVideoTimestamp!)) {
      _oldestHashtagVideoTimestamp = oldestTimestamp;
      Log.debug(
          '📍 Updated oldest hashtag timestamp: $_oldestHashtagVideoTimestamp',
          name: 'ExploreScreen',
          category: LogCategory.video);
    }
  }

  /// Check if we're near the end of the video list and should load more content
  void _checkForAutoPagination(int currentIndex, int totalVideos) {
    // Load more when we're 3 videos away from the end
    const paginationThreshold = 3;

    if (currentIndex >= totalVideos - paginationThreshold) {
      // Rate limit pagination calls to prevent spam
      final now = DateTime.now();
      if (_lastPaginationCall != null &&
          now.difference(_lastPaginationCall!).inSeconds < 5) {
        Log.debug(
          'ExploreScreen: Skipping pagination - too soon since last call',
          name: 'ExploreScreen',
          category: LogCategory.video,
        );
        return;
      }

      _lastPaginationCall = now;

      Log.info(
        'ExploreScreen: Near end of videos ($currentIndex/$totalVideos), auto-loading more...',
        name: 'ExploreScreen',
        category: LogCategory.video,
      );

      // Load more content based on current tab
      _loadMoreContentForCurrentTab();
    }
  }

  /// Load more content based on the currently active tab
  void _loadMoreContentForCurrentTab() {
    final currentTab = _tabController.index;

    switch (currentTab) {
      case 0: // Editor's Picks
        // Editor's picks are finite, so we don't need to load more
        Log.debug(
            'ExploreScreen: Editor\'s picks are finite, no auto-pagination needed',
            name: 'ExploreScreen',
            category: LogCategory.video);
        break;

      case 1: // Popular Now
        Log.debug('ExploreScreen: Auto-loading more Popular Now videos',
            name: 'ExploreScreen', category: LogCategory.video);
        // Trigger discovery provider to load more events
        ref.read(videoEventsProvider.notifier).loadMoreEvents();
        break;

      case 2: // Trending
        Log.debug('ExploreScreen: Auto-loading more Trending videos',
            name: 'ExploreScreen', category: LogCategory.video);

        // If a hashtag is selected, load more videos for that hashtag
        if (_selectedHashtag != null && _oldestHashtagVideoTimestamp != null) {
          Log.info(
              '📍 Loading more videos for hashtag #$_selectedHashtag (until: $_oldestHashtagVideoTimestamp)',
              name: 'ExploreScreen',
              category: LogCategory.video);
          final hashtagService = ref.read(hashtagServiceProvider);
          // Load more videos older than the current oldest
          hashtagService.subscribeToHashtagVideos(
            [_selectedHashtag!],
            limit: 50,
            until: _oldestHashtagVideoTimestamp! -
                1, // Get videos before the oldest one
          ).then((_) {
            // Update the oldest timestamp after loading
            final newVideos =
                hashtagService.getVideosByHashtags([_selectedHashtag!]);
            if (newVideos.isNotEmpty) {
              _updateOldestHashtagTimestamp(newVideos);
            }
          });
        } else {
          // Load more from analytics trending provider
          final trendingProvider =
              ref.read(curation_providers.analyticsTrendingProvider.notifier);
          trendingProvider.loadMore();
        }
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Only handle lifecycle for Popular Now tab with PageView
    if (_tabController.index != 1) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Pause videos when app goes to background
        // FIXED: Use VideoManager directly to avoid circular dependency
        final videoManager = ref.read(videoManagerProvider.notifier);
        videoManager.pauseAllVideos();
      case AppLifecycleState.resumed:
        // Videos will auto-resume via VideoFeedItem when it rebuilds
        if (mounted) {
          setState(() {}); // Trigger rebuild
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: VineTheme.backgroundColor,
        appBar: _isInFeedMode
            ? AppBar(
                backgroundColor: VineTheme.vineGreen,
                elevation: 0,
                leading: IconButton(
                  icon:
                      const Icon(Icons.arrow_back, color: VineTheme.whiteText),
                  onPressed: _exitFeedMode,
                ),
                title: Text(
                  'Explore Vines',
                  style: GoogleFonts.pacifico(
                    color: VineTheme.whiteText,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: VineTheme.whiteText),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const SearchScreen()),
                      );
                    },
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: VineTheme.whiteText,
                  indicatorWeight: 2,
                  labelColor: VineTheme.whiteText,
                  unselectedLabelColor:
                      VineTheme.whiteText.withValues(alpha: 0.7),
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  onTap: _handleTabTap,
                  tabs: const [
                    Tab(text: "EDITOR'S PICKS"),
                    Tab(text: 'NEW VINES'),
                    Tab(text: 'TRENDING'),
                  ],
                ),
              )
            : AppBar(
                backgroundColor: VineTheme.vineGreen,
                elevation: 0,
                title: Text(
                  'Explore Vines',
                  style: GoogleFonts.pacifico(
                    color: VineTheme.whiteText,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: VineTheme.whiteText),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const SearchScreen()),
                      );
                    },
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: VineTheme.whiteText,
                  indicatorWeight: 2,
                  labelColor: VineTheme.whiteText,
                  unselectedLabelColor:
                      VineTheme.whiteText.withValues(alpha: 0.7),
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  onTap: _handleTabTap,
                  tabs: const [
                    Tab(text: "EDITOR'S PICKS"),
                    Tab(text: 'NEW VINES'),
                    Tab(text: 'TRENDING'),
                  ],
                ),
              ),
        body: Stack(
          children: [
            TabBarView(
              controller: _tabController,
              children: [
                _buildEditorsPicks(),
                _buildPopularNow(),
                _buildTrending(),
              ],
            ),
            // No overlay needed - feed mode is handled by navigation to main tab
          ],
        ),
      );

  Widget _buildEditorsPicks() {
    final curationService = ref.watch(curationServiceProvider);
    final hashtagService = ref.watch(hashtagServiceProvider);

    // Get editor's picks from curation service
    final editorsPicks =
        curationService.getVideosForSetType(CurationSetType.editorsPicks);

    // Riverpod providers handle subscription automatically

    if (curationService.isLoading && editorsPicks.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: VineTheme.vineGreen,
        ),
      );
    }

    if (editorsPicks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 64,
              color: VineTheme.secondaryText,
            ),
            SizedBox(height: 16),
            Text(
              "Editor's Picks",
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Curated videos selected by our\ncommunity moderators.',
              style: TextStyle(
                color: VineTheme.secondaryText,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Get editor's pick hashtags with pagination
    final allEditorsHashtags =
        hashtagService.getEditorsPicks(limit: 100); // Get more from service
    final editorsHashtags =
        allEditorsHashtags.take(_editorsHashtagLimit).toList();

    // Batch fetch profiles for the first visible videos
    if (editorsPicks.isNotEmpty && !_isInFeedMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _batchFetchProfilesAroundIndex(0, editorsPicks);
      });
    }

    // Full-screen video feed with hashtag filter at top
    return Column(
      children: [
        // Editor's pick hashtags
        if (editorsHashtags.isNotEmpty) ...[
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: editorsHashtags.length +
                  (editorsHashtags.length < allEditorsHashtags.length ? 1 : 0),
              itemBuilder: (context, index) {
                // Show load more button at the end
                if (index >= editorsHashtags.length) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _isLoadingMoreEditorsHashtags
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: VineTheme.vineGreen,
                              strokeWidth: 2,
                            ),
                          )
                        : ActionChip(
                            label: const Text('+ More'),
                            onPressed: _loadMoreEditorsHashtags,
                            backgroundColor: VineTheme.vineGreen,
                            labelStyle: const TextStyle(
                              color: VineTheme.whiteText,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  );
                }

                final hashtag = editorsHashtags[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text('#$hashtag'),
                    onPressed: () {
                      debugPrint(
                          "🔗 Navigating to hashtag feed from editor's picks: #$hashtag");
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              HashtagFeedScreen(hashtag: hashtag),
                        ),
                      );
                    },
                    backgroundColor: VineTheme.cardBackground,
                    labelStyle: const TextStyle(
                      color: VineTheme.primaryText,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: VineTheme.secondaryText, height: 1),
        ],

        // Video content - either grid or feed mode
        Expanded(
          child: _isInFeedMode
              ? PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: _currentTabVideos.length,
                  controller: PageController(initialPage: _currentVideoIndex),
                  onPageChanged: (index) {
                    // Check for automatic pagination
                    _checkForAutoPagination(index, _currentTabVideos.length);

                    // Pause all videos first
                    // FIXED: Use VideoManager directly to avoid circular dependency
                    final videoManager = ref.read(videoManagerProvider.notifier);
                    videoManager.pauseAllVideos();

                    setState(() {
                      _currentVideoIndex = index;
                      _playingVideoId = _currentTabVideos[index].id;
                    });

                    // Only fetch profile when video is actually playing to minimize subscriptions
                    if (_playingVideoId == _currentTabVideos[index].id) {
                      _batchFetchProfilesAroundIndex(index, _currentTabVideos);
                    }

                    // Preload videos around new position
                    videoManager.preloadAroundIndex(index);
                  },
                  itemBuilder: (context, index) {
                    final video = _currentTabVideos[index];
                    final isActive = index == _currentVideoIndex;

                    return VideoFeedItem(
                      key: ValueKey(video.id),
                      video: video,
                      isActive: isActive &&
                          _tabController.index ==
                              0, // Only active if on Editor's Picks tab
                      tabContext: TabContext.explore,
                    );
                  },
                )
              : RefreshIndicator(
                  color: VineTheme.vineGreen,
                  onRefresh: () async {
                    // Refresh editor's picks curation data
                    final curationProvider =
                        ref.read(curation_providers.curationProvider.notifier);
                    await curationProvider.forceRefresh();
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(1),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width < 600
                          ? 3
                          : MediaQuery.of(context).size.width < 900
                              ? 4
                              : MediaQuery.of(context).size.width < 1200
                                  ? 5
                                  : 6,
                      crossAxisSpacing: 1,
                      mainAxisSpacing: 1,
                      childAspectRatio: 1,
                    ),
                    itemCount: editorsPicks.length,
                    itemBuilder: (context, index) {
                      final video = editorsPicks[index];
                      return VideoExploreTile(
                        video: video,
                        isActive: false,
                        onTap: () {
                          _enterFeedMode(editorsPicks, index);
                        },
                        onClose: _exitFeedMode,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPopularNow() {
    // Use the proper Riverpod provider that reactively updates
    final asyncVideoEvents = ref.watch(videoEventsProvider);

    // Handle different async states
    return asyncVideoEvents.when(
      loading: () => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: VineTheme.vineGreen,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Popular Now...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: VineTheme.vineGreen,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Popular Now...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      data: (allVideos) {
        // Sort Popular Now by loops (new vines without loops first, then by loop count desc, then newest)
        final popularVideos = List<VideoEvent>.from(allVideos)
          ..sort(VideoEvent.compareByLoopsThenTime);

        // Take videos up to current limit for Popular Now
        final videos = popularVideos.take(_popularNowLimit).toList();

        Log.debug('PopularNow: ${videos.length} videos available',
            name: 'ExploreScreen', category: LogCategory.ui);

        if (videos.isEmpty) {
          return _buildPopularNowEmptyState();
        }

        // Batch fetch profiles for the first visible videos
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _batchFetchProfilesAroundIndex(0, videos);
        });

        return _buildPopularNowContent(videos, allVideos);
      },
    );
  }

  Widget _buildPopularNowEmptyState() {
    return RefreshIndicator(
      color: VineTheme.vineGreen,
      onRefresh: () async {
        // Invalidate the video events provider to refresh
        ref.invalidate(videoEventsProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.trending_up,
                  size: 64,
                  color: VineTheme.secondaryText,
                ),
                SizedBox(height: 16),
                Text(
                  'Looking for Popular Videos...',
                  style: TextStyle(
                    color: VineTheme.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Fetching the most popular content\nfrom the network.\n\nPull down to refresh.',
                  style: TextStyle(
                    color: VineTheme.secondaryText,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopularNowContent(
      List<VideoEvent> videos, List<VideoEvent> allVideos) {
    // Check if we should show feed mode or grid mode
    if (_isInFeedMode) {
      // Full-screen video feed mode
      return PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _currentTabVideos.length,
        controller: PageController(initialPage: _currentVideoIndex),
        onPageChanged: (index) {
          // Check for automatic pagination
          _checkForAutoPagination(index, _currentTabVideos.length);

          // Pause all videos first
          // FIXED: Use VideoManager directly to avoid circular dependency
          final videoManager = ref.read(videoManagerProvider.notifier);
          videoManager.pauseAllVideos();

          setState(() {
            _currentVideoIndex = index;
            _playingVideoId = _currentTabVideos[index].id;
          });

          // Only fetch profile when video is actually playing to minimize subscriptions
          if (_playingVideoId == _currentTabVideos[index].id) {
            _batchFetchProfilesAroundIndex(index, _currentTabVideos);
          }

          // Preload videos around new position
          videoManager.preloadAroundIndex(index);
        },
        itemBuilder: (context, index) {
          final video = _currentTabVideos[index];
          final isActive = index == _currentVideoIndex;

          return VideoFeedItem(
            key: ValueKey(video.id),
            video: video,
            isActive: isActive &&
                _tabController.index == 1, // Only active if on Popular Now tab
            tabContext: TabContext.explore,
          );
        },
      );
    } else {
      // Grid view mode with pull-to-refresh
      final screenWidth = MediaQuery.of(context).size.width;
      final crossAxisCount = screenWidth < 600
          ? 3
          : screenWidth < 900
              ? 4
              : screenWidth < 1200
                  ? 5
                  : 6;

      return RefreshIndicator(
        color: VineTheme.vineGreen,
        onRefresh: () async {
          // Reset pagination and refresh
          setState(() {
            _popularNowLimit = 50;
          });

          // Reset pagination state in the service to allow fresh loading
          final videoEventService = ref.read(videoEventServiceProvider);
          videoEventService.resetPaginationState(SubscriptionType.discovery);

          // Invalidate and refresh the provider
          ref.invalidate(videoEventsProvider);

          // Force a fresh discovery subscription
          ref.read(videoEventsProvider.notifier).startDiscoverySubscription();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // Check for automatic pagination when near end of grid scroll
            if (notification is ScrollUpdateNotification &&
                !_isLoadingMorePopular) {
              final scrollExtent = notification.metrics.maxScrollExtent;
              final currentScroll = notification.metrics.pixels;
              final threshold =
                  scrollExtent * 0.8; // Load more when 80% scrolled

              if (currentScroll >= threshold) {
                // Always try to load more when scrolling near bottom
                // The method will handle checking if there are local videos or need to fetch from relay
                Log.debug('📜 Auto-triggering load more at 80% scroll position',
                    name: 'ExploreScreen', category: LogCategory.ui);
                _loadMorePopularNow();
              }
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(1),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final video = videos[index];
                      return VideoExploreTile(
                        video: video,
                        isActive:
                            false, // Never active in grid - feed mode handles playback
                        showTextOverlay:
                            false, // Popular Now shows clean thumbnails without text
                        onTap: () {
                          _enterFeedMode(videos, index);
                        },
                        onClose: _exitFeedMode,
                      );
                    },
                    childCount: videos.length,
                  ),
                ),
              ),
              // Loading indicator when loading more (no more button!)
              if (_isLoadingMorePopular)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: VineTheme.vineGreen),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildTrending() {
    // Watch video events to trigger rebuilds when new videos arrive
    ref.watch(videoEventsProvider);

    final hashtagService = ref.watch(hashtagServiceProvider);
    final topHashtagsService = TopHashtagsService.instance;

    // Create a map to store hashtags with their counts
    final hashtagCounts = <String, int>{};

    // Get ALL hashtags from JSON (no limit)
    final topHashtagsFromJson = topHashtagsService.getTopHashtags(limit: 1000);

    // Add JSON hashtags with their counts
    for (final hashtag in topHashtagsFromJson) {
      final jsonStats = topHashtagsService.getHashtagStats(hashtag);
      hashtagCounts[hashtag] = jsonStats?.count ?? 0;
    }

    // Add or update with local hashtag counts
    final localHashtags = hashtagService.allHashtags;
    for (final hashtag in localHashtags) {
      final localStats = hashtagService.getHashtagStats(hashtag);
      if (localStats != null) {
        // Add local count to existing count (combine JSON + local)
        final currentCount = hashtagCounts[hashtag] ?? 0;
        hashtagCounts[hashtag] = currentCount + localStats.videoCount;
      }
    }

    // Sort hashtags by count (descending) - PROPER SORTING
    final sortedHashtagEntries = hashtagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Get all hashtags sorted properly
    final allTrendingHashtags = sortedHashtagEntries.map((e) => e.key).toList();
    var trendingHashtags =
        allTrendingHashtags.take(_trendingHashtagLimit).toList();

    // If a hashtag is selected but not in the trending list, add it to ensure it's visible
    if (_selectedHashtag != null &&
        !trendingHashtags.contains(_selectedHashtag)) {
      trendingHashtags = [_selectedHashtag!, ...trendingHashtags];
    }

    // If user has selected a specific hashtag, show hashtag-filtered content
    if (_selectedHashtag != null) {
      // Get videos after watching video events to ensure we have latest data
      final videos = hashtagService.getVideosByHashtags([_selectedHashtag!]);

      return Column(
        children: [
          // Hashtag filter chips
          if (trendingHashtags.isNotEmpty) ...[
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Show ALL hashtags, no limit - user can scroll infinitely
                itemCount: allTrendingHashtags.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // "All" chip
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _selectedHashtag == null,
                        onSelected: (selected) {
                          // If in feed mode, exit it first
                          if (_isInFeedMode) {
                            _exitFeedMode();
                          }

                          setState(() {
                            _selectedHashtag = null;
                          });
                        },
                        backgroundColor: VineTheme.cardBackground,
                        selectedColor: VineTheme.vineGreen,
                        labelStyle: TextStyle(
                          color: _selectedHashtag == null
                              ? VineTheme.whiteText
                              : VineTheme.primaryText,
                          fontWeight: _selectedHashtag == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }

                  // Get the hashtag for this index (remember index 0 is "All")
                  final hashtag = allTrendingHashtags[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                HashtagFeedScreen(hashtag: hashtag),
                          ),
                        );
                      },
                      child: FilterChip(
                        label: Text('#$hashtag'),
                        selected: _selectedHashtag == hashtag,
                        onSelected: (selected) async {
                          debugPrint(
                              '🏷️ Hashtag filter selected: #$hashtag (selected=$selected)');

                          // If in feed mode, exit it first
                          if (_isInFeedMode) {
                            _exitFeedMode();
                          }

                          setState(() {
                            _selectedHashtag = selected ? hashtag : null;
                          });

                          // If selecting a hashtag, subscribe to get more videos from relays
                          if (selected) {
                            final filteredVideos =
                                hashtagService.getVideosByHashtags([hashtag]);
                            debugPrint(
                                '🏷️ Found ${filteredVideos.length} local videos for #$hashtag');

                            // Also request from relays - the videoEventsProvider will trigger rebuild
                            hashtagService.subscribeToHashtagVideos([hashtag],
                                limit: 100).then((_) {
                              debugPrint(
                                  '🏷️ Subscription completed for #$hashtag videos');
                            });
                          }
                        },
                        backgroundColor: VineTheme.cardBackground,
                        selectedColor: VineTheme.vineGreen,
                        labelStyle: TextStyle(
                          color: _selectedHashtag == hashtag
                              ? VineTheme.whiteText
                              : VineTheme.primaryText,
                          fontWeight: _selectedHashtag == hashtag
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: VineTheme.secondaryText, height: 1),
          ],

          // Hashtag-filtered videos - support both grid and feed modes
          Expanded(
            child: videos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.tag,
                          size: 64,
                          color: VineTheme.secondaryText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No videos found for #$_selectedHashtag',
                          style: const TextStyle(
                            color: VineTheme.primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try a different hashtag or check back later',
                          style: TextStyle(
                            color: VineTheme.secondaryText,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _isInFeedMode
                    ? PageView.builder(
                        scrollDirection: Axis.vertical,
                        itemCount: _currentTabVideos.length,
                        controller:
                            PageController(initialPage: _currentVideoIndex),
                        onPageChanged: (index) {
                          // Check for automatic pagination
                          _checkForAutoPagination(
                              index, _currentTabVideos.length);

                          // Pause all videos first
                          // FIXED: Use VideoManager directly to avoid circular dependency
                          final videoManager = ref.read(videoManagerProvider.notifier);
                          videoManager.pauseAllVideos();

                          setState(() {
                            _currentVideoIndex = index;
                            _playingVideoId = _currentTabVideos[index].id;
                          });

                          // Only fetch profile when video is actually playing to minimize subscriptions
                          if (_playingVideoId == _currentTabVideos[index].id) {
                            _batchFetchProfilesAroundIndex(index, _currentTabVideos);
                          }

                          // Preload videos around new position
                          videoManager.preloadAroundIndex(index);
                        },
                        itemBuilder: (context, index) {
                          final video = _currentTabVideos[index];
                          final isActive = index == _currentVideoIndex;

                          return VideoFeedItem(
                            key: ValueKey(video.id),
                            video: video,
                            isActive: isActive &&
                                _tabController.index ==
                                    2, // Only active if on Trending tab
                            tabContext: TabContext.explore,
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: videos.length,
                        itemBuilder: (context, index) {
                          final video = videos[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              height: 250,
                              child: VideoExploreTile(
                                video: video,
                                isActive: false,
                                onTap: () {
                                  _enterFeedMode(videos, index);
                                },
                                onClose: _exitFeedMode,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      );
    }

    // Default trending infinite scroll feed
    return Column(
      children: [
        // Hashtag filter chips
        if (trendingHashtags.isNotEmpty) ...[
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Show ALL hashtags, no limit - user can scroll infinitely
              itemCount: allTrendingHashtags.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  // "All" chip
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _selectedHashtag == null,
                      onSelected: (selected) {
                        setState(() {
                          _selectedHashtag = null;
                        });
                      },
                      backgroundColor: VineTheme.cardBackground,
                      selectedColor: VineTheme.vineGreen,
                      labelStyle: TextStyle(
                        color: _selectedHashtag == null
                            ? VineTheme.whiteText
                            : VineTheme.primaryText,
                        fontWeight: _selectedHashtag == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }

                // Get the hashtag for this index (remember index 0 is "All")
                final hashtag = allTrendingHashtags[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onLongPress: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              HashtagFeedScreen(hashtag: hashtag),
                        ),
                      );
                    },
                    child: FilterChip(
                      label: Text('#$hashtag'),
                      selected: _selectedHashtag == hashtag,
                      onSelected: (selected) async {
                        debugPrint(
                            '🏷️ Hashtag filter selected: #$hashtag (selected=$selected)');

                        // If in feed mode, exit it first
                        if (_isInFeedMode) {
                          _exitFeedMode();
                        }

                        setState(() {
                          _selectedHashtag = selected ? hashtag : null;
                        });

                        // If selecting a hashtag, also subscribe to get more videos from relays
                        if (selected) {
                          final hashtagService =
                              ref.read(hashtagServiceProvider);
                          final filteredVideos =
                              hashtagService.getVideosByHashtags([hashtag]);
                          debugPrint(
                              '🏷️ Found ${filteredVideos.length} local videos for #$hashtag');

                          // Also request from relays - the videoEventsProvider will trigger rebuild
                          hashtagService.subscribeToHashtagVideos([hashtag],
                              limit: 100).then((_) {
                            debugPrint(
                                '🏷️ Subscription completed for #$hashtag videos');
                          });
                        }
                      },
                      backgroundColor: VineTheme.cardBackground,
                      selectedColor: VineTheme.vineGreen,
                      labelStyle: TextStyle(
                        color: _selectedHashtag == hashtag
                            ? VineTheme.whiteText
                            : VineTheme.primaryText,
                        fontWeight: _selectedHashtag == hashtag
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: VineTheme.secondaryText, height: 1),
        ],

        // Trending grid view (similar to Popular Now)
        Expanded(
          child: _buildTrendingVideoGrid(),
        ),
      ],
    );
  }

  Widget _buildTrendingVideoGrid() {
    final isExploreActive = ref.watch(isExploreTabActiveProvider);
    // Use analytics trending provider for data sorted by actual popularity
    final analyticsTrendingVideos =
        ref.watch(curation_providers.analyticsTrendingProvider);

    // Only trigger refresh once on initial load, not on every rebuild
    if (analyticsTrendingVideos.isEmpty && !_hasFetchedTrending) {
      _hasFetchedTrending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final trendingProvider =
            ref.read(curation_providers.analyticsTrendingProvider.notifier);
        trendingProvider.refresh();
      });
    }

    // Filter by hashtag if one is selected
    List<VideoEvent> videos;
    if (_selectedHashtag != null) {
      final hashtagService = ref.watch(hashtagServiceProvider);
      videos = hashtagService.getVideosByHashtags([_selectedHashtag!]);
      debugPrint(
          '🏷️ Filtering trending by #$_selectedHashtag: ${videos.length} videos');
    } else {
      // Take videos up to current limit for trending
      videos = analyticsTrendingVideos.take(_trendingLimit).toList();
    }

    Log.debug('Trending: ${videos.length} videos from analytics',
        name: 'ExploreScreen', category: LogCategory.ui);

    if (videos.isEmpty) {
      // When no trending videos from server, show popular hashtags sorted by video count
      final hashtagService = ref.watch(hashtagServiceProvider);

      // Watch video events to trigger rebuilds when new videos arrive
      final videoEventsAsync = ref.watch(videoEventsProvider);

      // Also trigger discovery subscription to get more videos from relays
      // This will populate hashtag statistics with fresh data
      // Guard to once to avoid repeated requests on every rebuild.
      if (isExploreActive && !_discoveryStartedForHashtags) {
        _discoveryStartedForHashtags = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Check relay connectivity status first
          final nostrService = ref.read(nostrServiceProvider);
          final connectedRelays = nostrService.connectedRelayCount;

          Log.info('📡 Relay Status: $connectedRelays relays connected',
              name: 'ExploreScreen', category: LogCategory.ui);

          if (connectedRelays == 0) {
            Log.warning('⚠️ No relays connected! Cannot fetch remote videos',
                name: 'ExploreScreen', category: LogCategory.ui);
          }

          // Start discovery subscription to get videos from relays
          Log.info(
              '📡 Starting discovery subscription to fetch hashtags from relays',
              name: 'ExploreScreen',
              category: LogCategory.ui);
          ref.read(videoEventsProvider.notifier).startDiscoverySubscription();

          // Also trigger a force refresh to ensure we're fetching fresh data
          final videoEventService = ref.read(videoEventServiceProvider);
          videoEventService
              .loadMoreContentUnlimited(
                  subscriptionType: SubscriptionType.discovery, limit: 300)
              .then((_) {
            Log.info('📡 Unlimited content query started for hashtag discovery',
                name: 'ExploreScreen', category: LogCategory.ui);
            // Refresh hashtag statistics after fetching
            Future.delayed(const Duration(seconds: 3), () {
              hashtagService.refreshHashtagStats();
            });
          });
        });
      } else {
        Log.debug(
            'Explore inactive; skipping subscription/unlimited content kick-off',
            name: 'ExploreScreen',
            category: LogCategory.ui);
      }

      // Show loading state while fetching initial videos
      final isLoading = videoEventsAsync.when(
        data: (videos) => videos.isEmpty,
        loading: () => true,
        error: (_, __) => false,
      );

      // Get current video count for display
      final videoEventService = ref.read(videoEventServiceProvider);
      final totalVideos = videoEventService.discoveryVideos.length +
          videoEventService.homeFeedVideos.length;

      // Combine top hashtags from JSON with local cache
      final topHashtagsService = TopHashtagsService.instance;
      // Get ALL hashtags from JSON (no limit)
      final topHashtagsFromJson =
          topHashtagsService.getTopHashtags(limit: 1000);
      // Get ALL local hashtags
      final localHashtags = hashtagService.allHashtags;

      // Create a map to store hashtags with their counts
      final hashtagCounts = <String, int>{};

      // Add JSON hashtags with their counts
      for (final hashtag in topHashtagsFromJson) {
        final jsonStats = topHashtagsService.getHashtagStats(hashtag);
        hashtagCounts[hashtag] = jsonStats?.count ?? 0;
      }

      // Add or update with local hashtag counts (which are more current)
      for (final hashtag in localHashtags) {
        final localStats = hashtagService.getHashtagStats(hashtag);
        if (localStats != null) {
          // Add local count to existing count (combine JSON + local)
          final currentCount = hashtagCounts[hashtag] ?? 0;
          hashtagCounts[hashtag] = currentCount + localStats.videoCount;
        } else if (!hashtagCounts.containsKey(hashtag)) {
          // Add hashtags that only exist locally with count of 1 (since it exists)
          hashtagCounts[hashtag] = 1;
        }
      }

      // Sort hashtags by count (descending)
      final sortedHashtags = hashtagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Debug: Log top hashtags to verify sorting
      if (sortedHashtags.isNotEmpty) {
        final top5 =
            sortedHashtags.take(5).map((e) => '${e.key}:${e.value}').join(', ');
        Log.debug('📊 Top 5 hashtags by count: $top5',
            name: 'ExploreScreen', category: LogCategory.ui);
      }

      // Get ALL hashtags - no limit
      final popularHashtags = sortedHashtags.map((entry) => entry.key).toList();

      return RefreshIndicator(
        color: VineTheme.vineGreen,
        onRefresh: () async {
          // Refresh analytics trending data
          final trendingProvider =
              ref.read(curation_providers.analyticsTrendingProvider.notifier);
          await trendingProvider.refresh();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.tag,
                    size: 64,
                    color: VineTheme.secondaryText,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Explore Hashtags',
                    style: TextStyle(
                      color: VineTheme.primaryText,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLoading
                        ? 'Fetching videos from relays...'
                        : 'Browse popular hashtags to discover content',
                    style: const TextStyle(
                      color: VineTheme.secondaryText,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (topHashtagsService.isLoaded || totalVideos > 0)
                    Text(
                      topHashtagsService.isLoaded
                          ? 'Showing ${popularHashtags.length} hashtags (${topHashtagsFromJson.length} global + ${localHashtags.length} local)'
                          : 'Showing ${popularHashtags.length} hashtags from $totalVideos cached videos',
                      style: const TextStyle(
                        color: VineTheme.secondaryText,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),

                  // Add manual refresh button
                  ElevatedButton.icon(
                    onPressed: () {
                      // Force refresh from relays
                      final nostrService = ref.read(nostrServiceProvider);
                      final connectedRelays = nostrService.connectedRelayCount;

                      if (connectedRelays == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'No relays connected. Check your network connection.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      // Force fetch new videos
                      ref
                          .read(videoEventServiceProvider)
                          .loadMoreContentUnlimited(
                            subscriptionType: SubscriptionType.discovery,
                            limit: 500,
                          )
                          .then((_) {
                        // Refresh stats after a delay
                        Future.delayed(const Duration(seconds: 5), () {
                          hashtagService.refreshHashtagStats();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Hashtag data refreshed'),
                                backgroundColor: VineTheme.vineGreen,
                              ),
                            );
                          }
                        });
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Fetch from Relays'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VineTheme.vineGreen,
                      foregroundColor: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Display popular hashtags in a wrap widget
                  if (popularHashtags.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: popularHashtags.map((hashtag) {
                          // Get video count - check both JSON stats and local cache
                          final jsonStats =
                              topHashtagsService.getHashtagStats(hashtag);
                          final localStats =
                              hashtagService.getHashtagStats(hashtag);

                          // Use local count if available (more current), otherwise use JSON count
                          final videoCount =
                              localStats?.videoCount ?? jsonStats?.count ?? 0;

                          return ActionChip(
                            label: Text(
                              videoCount > 0
                                  ? '#$hashtag ($videoCount)'
                                  : '#$hashtag',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () async {
                              // Navigate to hashtag feed
                              debugPrint(
                                  '🔗 Navigating to hashtag feed: #$hashtag');
                              await showHashtagVideos(hashtag);
                            },
                            backgroundColor:
                                VineTheme.vineGreen.withValues(alpha: 0.9),
                            labelStyle: const TextStyle(
                              color: VineTheme.whiteText,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          );
                        }).toList(),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'No hashtags available yet.\nPull down to refresh.',
                      style: TextStyle(
                        color: VineTheme.secondaryText,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Batch fetch profiles for the first visible trending videos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _batchFetchProfilesAroundIndex(0, videos);
    });

    // Check if we should show feed mode or grid mode
    if (_isInFeedMode) {
      // Full-screen video feed mode
      return PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _currentTabVideos.length,
        controller: PageController(initialPage: _currentVideoIndex),
        onPageChanged: (index) {
          // Check for automatic pagination
          _checkForAutoPagination(index, _currentTabVideos.length);

          // Pause all videos first
          // FIXED: Use VideoManager directly to avoid circular dependency
          final videoManager = ref.read(videoManagerProvider.notifier);
          videoManager.pauseAllVideos();

          setState(() {
            _currentVideoIndex = index;
            _playingVideoId = _currentTabVideos[index].id;
          });

          // Only fetch profile when video is actually playing to minimize subscriptions
          if (_playingVideoId == _currentTabVideos[index].id) {
            _batchFetchProfilesAroundIndex(index, _currentTabVideos);
          }

          // Preload videos around new position
          videoManager.preloadAroundIndex(index);
        },
        itemBuilder: (context, index) {
          final video = _currentTabVideos[index];
          final isActive = index == _currentVideoIndex;

          return VideoFeedItem(
            key: ValueKey(video.id),
            video: video,
            isActive: isActive &&
                _tabController.index == 2, // Only active if on Trending tab
            tabContext: TabContext.explore,
          );
        },
      );
    } else {
      // Grid view mode with pull-to-refresh
      final screenWidth = MediaQuery.of(context).size.width;
      final crossAxisCount = screenWidth < 600
          ? 3
          : screenWidth < 900
              ? 4
              : screenWidth < 1200
                  ? 5
                  : 6;

      return RefreshIndicator(
        color: VineTheme.vineGreen,
        onRefresh: () async {
          // Reset pagination and refresh
          setState(() {
            _trendingLimit = 100;
          });

          // Refresh analytics trending data
          final trendingProvider =
              ref.read(curation_providers.analyticsTrendingProvider.notifier);
          await trendingProvider.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // Check for automatic pagination when near end of grid scroll
            if (notification is ScrollUpdateNotification &&
                !_isLoadingMoreTrending &&
                videos.length >= _trendingLimit &&
                _trendingLimit < analyticsTrendingVideos.length) {
              final scrollExtent = notification.metrics.maxScrollExtent;
              final currentScroll = notification.metrics.pixels;
              final threshold =
                  scrollExtent * 0.8; // Load more when 80% scrolled

              if (currentScroll >= threshold) {
                // Auto-load more Trending videos
                _loadMoreTrending();
              }
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(1),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final video = videos[index];
                      return VideoExploreTile(
                        video: video,
                        isActive: false,
                        onTap: () {
                          _enterFeedMode(videos, index);
                        },
                        onClose: _exitFeedMode,
                      );
                    },
                    childCount: videos.length,
                  ),
                ),
              ),
              // Loading indicator when loading more (no more button!)
              if (_isLoadingMoreTrending)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: VineTheme.vineGreen),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }
}
