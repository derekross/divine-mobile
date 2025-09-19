// ABOUTME: Explore video feed using VideoManager pipeline for consistent playback
// ABOUTME: Shows curated videos with same performance as main feed

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/curation_set.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/explore_video_manager.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_feed_item.dart';

/// Video feed screen for explore content using VideoManager pipeline
///
/// This provides the same performance and video management as the main feed
/// but displays curated content from the explore service.
class ExploreVideoFeedScreen extends ConsumerStatefulWidget {
  const ExploreVideoFeedScreen({
    required this.curationSetType,
    required this.title,
    super.key,
    this.startingVideo,
    this.startingIndex = 0,
  });
  final CurationSetType curationSetType;
  final String title;
  final VideoEvent? startingVideo;
  final int startingIndex;

  @override
  ConsumerState<ExploreVideoFeedScreen> createState() =>
      _ExploreVideoFeedScreenState();
}

class _ExploreVideoFeedScreenState extends ConsumerState<ExploreVideoFeedScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  ExploreVideoManager? _exploreVideoManager;
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
    // FIXED: Use VideoManager directly to avoid circular dependency
    if (_isInitialized && _videoManager != null) {
      _videoManager!.pauseAllVideos();
    }

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
      _exploreVideoManager = ref.read(exploreVideoManagerProvider);
      // FIXED: Get VideoManager directly to avoid circular dependency
      _videoManager = ref.read(videoManagerProvider.notifier);

      // Get videos for this curation type
      _videos = _exploreVideoManager!.getVideosForType(widget.curationSetType);

      // Start preloading around initial position
      if (_videos.isNotEmpty) {
        // FIXED: Handle preloading directly through VideoManager
        final videosToPreload = _exploreVideoManager!.getVideosForPreloading(widget.curationSetType, startIndex: _currentIndex);
        for (final video in videosToPreload) {
          _videoManager!.addVideoEvent(video);
          _videoManager!.preloadVideo(video.id);
        }
      }

      // REFACTORED: Service no longer extends ChangeNotifier - using Riverpod watch instead

      _isInitialized = true;
      setState(() {});

      Log.info(
          'ExploreVideoFeedScreen initialized with ${_videos.length} videos',
          name: 'ExploreVideoFeedScreen',
          category: LogCategory.ui);
    } catch (e) {
      Log.error('Failed to initialize ExploreVideoFeedScreen: $e',
          name: 'ExploreVideoFeedScreen', category: LogCategory.ui);
      _isInitialized = true; // Mark as initialized to show error state
      setState(() {});
    }
  }

  void _onPageChanged(int index) {
    if (!_isInitialized || _videoManager == null) return;

    setState(() {
      _currentIndex = index;
    });

    // FIXED: Use VideoManager's preloading around new position
    final videosToPreload = _exploreVideoManager!.getVideosForPreloading(widget.curationSetType, startIndex: index);
    for (final video in videosToPreload) {
      _videoManager!.addVideoEvent(video);
      _videoManager!.preloadVideo(video.id);
    }

    // Update video playback states
    _updateVideoPlayback(index);
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
      Log.debug('Paused explore video: ${videoId.substring(0, 8)}...',
          name: 'ExploreVideoFeedScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('Error pausing explore video $videoId: $e',
          name: 'ExploreVideoFeedScreen', category: LogCategory.ui);
    }
  }

  void _pauseAllVideos() {
    // FIXED: Use VideoManager directly to avoid circular dependency
    if (_videoManager != null) {
      _videoManager!.pauseAllVideos();
    }
  }

  void _resumeCurrentVideo() {
    // VideoFeedItem will handle resuming when it becomes active
    if (mounted) {
      setState(() {}); // Trigger rebuild to resume current video
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
            onPressed: () {
              // Pause videos before navigating back
              _pauseAllVideos();
              Navigator.of(context).pop();
            },
          ),
          title: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_exploreVideoManager?.isLoading == true && _videos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading curated videos...',
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
              'No ${widget.title.toLowerCase()} available',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check back later for new content',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Use same PageView structure as main feed
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _onPageChanged,
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        final isActive = index == _currentIndex;

        return VideoFeedItem(
          video: video,
          isActive: isActive,
          onVideoError: (videoId) {
            Log.error('Error in explore video $videoId',
                name: 'ExploreVideoFeedScreen', category: LogCategory.ui);
          },
        );
      },
    );
  }
}
