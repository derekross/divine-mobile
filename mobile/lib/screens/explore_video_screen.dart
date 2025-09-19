// ABOUTME: Inline video player screen that preserves explore context and navigation
// ABOUTME: Displays videos within explore screen layout instead of full-screen modal

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_feed_item.dart';

/// Inline video player screen that maintains explore context
class ExploreVideoScreen extends ConsumerStatefulWidget {
  const ExploreVideoScreen({
    required this.startingVideo,
    required this.videoList,
    required this.contextTitle,
    super.key,
    this.startingIndex,
  });
  final VideoEvent startingVideo;
  final List<VideoEvent> videoList;
  final String contextTitle;
  final int? startingIndex;

  @override
  ConsumerState<ExploreVideoScreen> createState() => _ExploreVideoScreenState();
}

class _ExploreVideoScreenState extends ConsumerState<ExploreVideoScreen> {
  late PageController _pageController;
  late int _currentIndex;
  VideoManager? _videoManager;

  @override
  void initState() {
    super.initState();

    Log.debug(
        'ExploreVideoScreen.initState: Called with ${widget.videoList.length} videos',
        name: 'ExploreVideoScreen',
        category: LogCategory.ui);

    // Find starting video index or use provided index
    _currentIndex = widget.startingIndex ??
        widget.videoList
            .indexWhere((video) => video.id == widget.startingVideo.id);

    if (_currentIndex == -1) {
      _currentIndex = 0;
    }

    _pageController = PageController(initialPage: _currentIndex);

    // Initialize video manager
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVideoManager();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pauseAllVideos();

    super.dispose();
  }

  Future<void> _initializeVideoManager() async {
    try {
      _videoManager = ref.read(videoManagerProvider.notifier);

      // PRIORITY 1: Immediately register and preload the current video
      if (_currentIndex < widget.videoList.length) {
        final currentVideo = widget.videoList[_currentIndex];
        Log.debug(
            'ExploreVideoScreen: Priority loading starting video: ${currentVideo.id.substring(0, 8)}...',
            name: 'ExploreVideoScreen',
            category: LogCategory.ui);

        // Preload the current video (videos are synced from feed automatically)
        await _videoManager!.preloadVideo(currentVideo.id);

        // PRIORITY 2: Preload adjacent videos for smooth scrolling
        // Preload the next video if available
        if (_currentIndex + 1 < widget.videoList.length) {
          await _videoManager!
              .preloadVideo(widget.videoList[_currentIndex + 1].id);
        }

        // Preload the previous video if available
        if (_currentIndex - 1 >= 0) {
          await _videoManager!
              .preloadVideo(widget.videoList[_currentIndex - 1].id);
        }
      }

      // Videos are now synced automatically from video feed provider
      Log.debug(
          'ExploreVideoScreen: Video management handled by Riverpod providers',
          name: 'ExploreVideoScreen',
          category: LogCategory.ui);
    } catch (e) {
      Log.error('ExploreVideoScreen: VideoManager not found: $e',
          name: 'ExploreVideoScreen', category: LogCategory.ui);
    }
  }

  void _pauseAllVideos() {
    if (_videoManager != null) {
      try {
        _videoManager!.pauseAllVideos();
      } catch (e) {
        Log.error('Error pausing videos in explore video screen: $e',
            name: 'ExploreVideoScreen', category: LogCategory.ui);
      }
    }
  }

  Future<void> _onPageChanged(int index) async {
    setState(() {
      _currentIndex = index;
    });

    // Manage video playback for the new current video
    if (_videoManager != null && index < widget.videoList.length) {
      final newVideo = widget.videoList[index];

      Log.debug(
          'ExploreVideoScreen: Page changed to video $index: ${newVideo.id.substring(0, 8)}...',
          name: 'ExploreVideoScreen',
          category: LogCategory.ui);

      // Preload current video with priority (videos are synced automatically)
      await _videoManager!.preloadVideo(newVideo.id);

      // Preload adjacent videos for smoother scrolling experience
      // Use fire-and-forget pattern to avoid blocking current video
      Future.microtask(() async {
        try {
          // Preload next video if available
          if (index + 1 < widget.videoList.length) {
            final nextVideo = widget.videoList[index + 1];
            await _videoManager!.preloadVideo(nextVideo.id);
          }

          // Videos are synced automatically from feed provider
          Log.debug('Adjacent videos handled by Riverpod provider',
              name: 'ExploreVideoScreen', category: LogCategory.ui);
        } catch (e) {
          Log.error('ExploreVideoScreen: Error preloading adjacent videos: $e',
              name: 'ExploreVideoScreen', category: LogCategory.ui);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.9),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.explore,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contextTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_currentIndex + 1} of ${widget.videoList.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          centerTitle: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        body: widget.videoList.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No videos available',
                      style:
                          TextStyle(color: VineTheme.primaryText, fontSize: 18),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Go back to explore more content',
                      style: TextStyle(
                          color: VineTheme.secondaryText, fontSize: 14),
                    ),
                  ],
                ),
              )
            : PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                onPageChanged: _onPageChanged,
                itemCount: widget.videoList.length,
                itemBuilder: (context, index) {
                  if (index < 0 || index >= widget.videoList.length) {
                    return const SizedBox.shrink();
                  }

                  final video = widget.videoList[index];
                  final isActive = index == _currentIndex;

                  return Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black,
                    child: VideoFeedItem(
                      video: video,
                      isActive: isActive,
                      forceInfoBelow: true,
                    ),
                  );
                },
              ),
      );
}
