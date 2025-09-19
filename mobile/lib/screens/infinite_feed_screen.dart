// ABOUTME: Infinite scroll video feed screen for trending/popular content
// ABOUTME: Continuously loads new videos as users scroll, never reaching the end

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/feed_type.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/infinite_feed_service.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_feed_item.dart';

/// Infinite scroll video feed screen
class InfiniteFeedScreen extends ConsumerStatefulWidget {
  const InfiniteFeedScreen({
    required this.feedType,
    super.key,
    this.startingIndex = 0,
  });

  final FeedType feedType;
  final int startingIndex;

  @override
  ConsumerState<InfiniteFeedScreen> createState() => _InfiniteFeedScreenState();
}

class _InfiniteFeedScreenState extends ConsumerState<InfiniteFeedScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  late InfiniteFeedService _feedService;
  VideoManager? _videoManager;
  List<VideoEvent> _videos = [];
  int _currentIndex = 0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.startingIndex);
    _currentIndex = widget.startingIndex;
    WidgetsBinding.instance.addObserver(this);

    // Initialize after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();

    // Pause all videos when leaving
    _videoManager?.pauseAllVideos();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!_isInitialized) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _pauseAllVideos();
      case AppLifecycleState.resumed:
        _resumeCurrentVideo();
      case AppLifecycleState.detached:
        _pauseAllVideos();
    }
  }

  void _initializeServices() {
    try {
      _videoManager = ref.read(videoManagerProvider.notifier);
      _feedService = InfiniteFeedService(
        nostrService: ref.read(nostrServiceProvider),
        videoEventService: ref.read(videoEventServiceProvider),
      );

      // Listen for feed updates
      // REFACTORED: Service no longer extends ChangeNotifier - use Riverpod ref.watch instead

      // Initialize the feed
      _feedService.initializeFeed(widget.feedType).then((_) {
        if (mounted) {
          _updateVideosList();
          _isInitialized = true;
          setState(() {});
        }
      });

      Log.info(
          'InfiniteFeedScreen initialized for ${widget.feedType.displayName}',
          name: 'InfiniteFeedScreen',
          category: LogCategory.ui);
    } catch (e) {
      Log.error('Failed to initialize InfiniteFeedScreen: $e',
          name: 'InfiniteFeedScreen', category: LogCategory.ui);
      _isInitialized = true; // Mark as initialized to show error state
      setState(() {});
    }
  }

  void _updateVideosList() {
    final newVideos = _feedService.getVideosForFeed(widget.feedType);
    if (newVideos.length != _videos.length) {
      // Check if this is an append (videos added at the end) or prepend (videos added at start)
      final isInitialLoad = _videos.isEmpty;
      final oldLength = _videos.length;
      final currentVideoId =
          _currentIndex < _videos.length ? _videos[_currentIndex].id : null;

      setState(() {
        _videos = newVideos;

        // If videos were prepended and we're not on initial load, adjust position
        if (!isInitialLoad &&
            currentVideoId != null &&
            newVideos.length > oldLength) {
          final newIndex = _videos.indexWhere((v) => v.id == currentVideoId);
          if (newIndex != -1 && newIndex != _currentIndex) {
            _currentIndex = newIndex;
            // Use post frame callback to ensure PageView is ready
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _pageController.hasClients) {
                _pageController.jumpToPage(newIndex);
              }
            });
          }
        }
      });
      Log.debug('Feed updated: ${_videos.length} videos available',
          name: 'InfiniteFeedScreen', category: LogCategory.ui);
    }
  }

  void _onPageChanged(int index) {
    if (!_isInitialized || _videoManager == null) return;

    setState(() {
      _currentIndex = index;
    });

    // Load more content when approaching the end
    if (index >= _videos.length - 5) {
      _loadMoreContent();
    }

    // Preload videos around current position
    _preloadAroundIndex(index);

    // Update video playback states
    _updateVideoPlayback(index);
  }

  void _loadMoreContent() {
    if (_feedService.isLoadingFeed(widget.feedType) ||
        !_feedService.hasMoreContent(widget.feedType)) {
      return;
    }

    _feedService.loadMoreContent(widget.feedType);
    Log.debug('Loading more content for ${widget.feedType.displayName}',
        name: 'InfiniteFeedScreen', category: LogCategory.ui);
  }

  void _preloadAroundIndex(int index) {
    if (_videos.isEmpty || _videoManager == null) return;

    final preloadStart = (index - 2).clamp(0, _videos.length - 1);
    final preloadEnd = (index + 3).clamp(0, _videos.length);

    for (var i = preloadStart; i < preloadEnd; i++) {
      if (i < _videos.length) {
        _videoManager!.preloadVideo(_videos[i].id).catchError((error) {
          Log.warning(
              'Error preloading video ${_videos[i].id.substring(0, 8)}... - $error',
              name: 'InfiniteFeedScreen',
              category: LogCategory.ui);
        });
      }
    }
  }

  void _updateVideoPlayback(int newIndex) {
    if (_videoManager == null || _videos.isEmpty) return;

    if (newIndex < 0 || newIndex >= _videos.length) return;

    // Pause previous video
    if (_currentIndex != newIndex && _currentIndex < _videos.length) {
      final previousVideo = _videos[_currentIndex];
      _pauseVideo(previousVideo.id);
    }

    // Current video will auto-play via VideoFeedItem
  }

  void _pauseVideo(String videoId) {
    if (!_isInitialized || _videoManager == null) return;

    try {
      _videoManager!.pauseVideo(videoId);
      Log.debug('Paused infinite feed video: ${videoId.substring(0, 8)}...',
          name: 'InfiniteFeedScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('Error pausing infinite feed video $videoId: $e',
          name: 'InfiniteFeedScreen', category: LogCategory.ui);
    }
  }

  void _pauseAllVideos() {
    _videoManager?.pauseAllVideos();
  }

  void _resumeCurrentVideo() {
    // VideoFeedItem will handle resuming when it becomes active
    if (mounted) {
      setState(() {}); // Trigger rebuild to resume current video
    }
  }

  Future<void> _refreshFeed() async {
    // Remember the current video ID before refresh
    final currentVideoId =
        _currentIndex < _videos.length ? _videos[_currentIndex].id : null;

    await _feedService.refreshFeed(widget.feedType);

    // Update the video list
    final newVideos = _feedService.getVideosForFeed(widget.feedType);

    if (mounted) {
      setState(() {
        _videos = newVideos;

        // If we had a current video, find its new index
        if (currentVideoId != null) {
          final newIndex = _videos.indexWhere((v) => v.id == currentVideoId);
          if (newIndex != -1 && newIndex != _currentIndex) {
            // Adjust the page controller to maintain position
            _currentIndex = newIndex;
            // Jump to the new position without animation to maintain user's view
            _pageController.jumpToPage(newIndex);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            widget.feedType.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _refreshFeed,
            ),
          ],
        ),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_feedService.isLoadingFeed(widget.feedType) && _videos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading videos...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_library_outlined,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              'No ${widget.feedType.displayName.toLowerCase()} available',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pull to refresh or check back later',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshFeed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    // Use RefreshIndicator for pull-to-refresh
    return RefreshIndicator(
      onRefresh: _refreshFeed,
      color: Colors.white,
      backgroundColor: Colors.black54,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _videos.length +
            (_feedService.hasMoreContent(widget.feedType) ? 1 : 0),
        itemBuilder: (context, index) {
          // Show loading indicator at the end if we have more content
          if (index >= _videos.length) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading more videos...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          }

          final video = _videos[index];
          final isActive = index == _currentIndex;

          return VideoFeedItem(
            video: video,
            isActive: isActive,
            onVideoError: (videoId) {
              Log.error('Error in infinite feed video $videoId',
                  name: 'InfiniteFeedScreen', category: LogCategory.ui);
            },
          );
        },
      ),
    );
  }
}
