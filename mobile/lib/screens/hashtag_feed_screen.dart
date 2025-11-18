// ABOUTME: Screen displaying videos filtered by a specific hashtag
// ABOUTME: Allows users to explore all videos with a particular hashtag

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/router/nav_extensions.dart';
import 'package:openvine/services/custom_hashtag_fetcher.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/composable_video_grid.dart';
import 'package:openvine/widgets/video_feed_item.dart';

class HashtagFeedScreen extends ConsumerStatefulWidget {
  const HashtagFeedScreen({required this.hashtag, this.embedded = false, this.onVideoTap, super.key});
  final String hashtag;
  final bool embedded;  // If true, don't show Scaffold/AppBar (for embedding in explore)
  final void Function(List<VideoEvent> videos, int index)? onVideoTap;  // Callback for video navigation when embedded

  @override
  ConsumerState<HashtagFeedScreen> createState() => _HashtagFeedScreenState();
}

class _HashtagFeedScreenState extends ConsumerState<HashtagFeedScreen> {
  List<VideoEvent> _videos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHashtagVideos();
  }

  Future<void> _fetchHashtagVideos() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Log.info('[HASHTAG] 🏷️  Fetching videos for hashtag: ${widget.hashtag}',
          category: LogCategory.video);

      final videos = await CustomHashtagFetcher.fetchHashtagVideos(
        hashtag: widget.hashtag,
        limit: 100,
      );

      if (!mounted) return;

      setState(() {
        _videos = videos;
        _isLoading = false;
      });

      Log.info('[HASHTAG] ✅ Successfully loaded ${videos.length} videos for #${widget.hashtag}',
          category: LogCategory.video);
    } catch (error) {
      Log.error('[HASHTAG] ❌ Failed to fetch hashtag ${widget.hashtag}: $error',
          category: LogCategory.video, error: error);

      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Builder(
          builder: (context) {
            // Sort videos by loops, then time
            final videos = List<VideoEvent>.from(_videos)
              ..sort(VideoEvent.compareByLoopsThenTime);

            if (_isLoading && videos.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: VineTheme.vineGreen),
                    const SizedBox(height: 24),
                    Text(
                      'Loading videos about #${widget.hashtag}...',
                      style: const TextStyle(
                        color: VineTheme.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This may take a few moments',
                      style: TextStyle(
                        color: VineTheme.secondaryText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (videos.isEmpty) {
              return Center(
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
                      'No videos found for #${widget.hashtag}',
                      style: const TextStyle(
                        color: VineTheme.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Be the first to post a video with this hashtag!',
                      style: TextStyle(
                        color: VineTheme.secondaryText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Use grid view when embedded (in explore), full-screen list when standalone
            if (widget.embedded) {
              return ComposableVideoGrid(
                videos: videos,
                onVideoTap: widget.onVideoTap ?? (videos, index) {
                  // Default behavior: navigate to hashtag feed mode using GoRouter
                  context.goHashtag(widget.hashtag, index);
                },
                onRefresh: () async {
                  Log.info('🔄 HashtagFeedScreen: Refreshing hashtag #${widget.hashtag}',
                      category: LogCategory.video);
                  // Refetch videos from relay
                  await _fetchHashtagVideos();
                },
              );
            }

            // Standalone mode: full-screen scrollable list
            final isLoadingMore = _isLoading;

            return RefreshIndicator(
              semanticsLabel: 'searching for more videos',
              onRefresh: () async {
                Log.info('🔄 HashtagFeedScreen: Refreshing hashtag #${widget.hashtag}',
                    category: LogCategory.video);
                // Refetch videos from relay
                await _fetchHashtagVideos();
              },
              child: ListView.builder(
              // Add 1 for loading indicator if still loading
              itemCount: videos.length + (isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                // Show loading indicator as last item
                if (index == videos.length) {
                  return Container(
                    height: MediaQuery.of(context).size.height,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: VineTheme.vineGreen),
                        const SizedBox(height: 24),
                        Text(
                          'Getting more videos about #${widget.hashtag}...',
                          style: const TextStyle(
                            color: VineTheme.primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please wait while we fetch from relays',
                          style: TextStyle(
                            color: VineTheme.secondaryText,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final video = videos[index];
                return GestureDetector(
                  onTap: () {
                    // Navigate to hashtag feed mode using GoRouter
                    context.goHashtag(widget.hashtag, index);
                  },
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height,
                    width: double.infinity,
                    child: VideoFeedItem(
                      video: video,
                      index: index,
                      contextTitle: '#${widget.hashtag}',
                      forceShowOverlay: true,
                    ),
                  ),
                );
              },
            ),
            );
          },
        );

    // If embedded, return body only; otherwise wrap with Scaffold
    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      backgroundColor: VineTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: VineTheme.vineGreen,
        elevation: 0,
        title: Text(
          '#${widget.hashtag}',
          style: const TextStyle(
            color: VineTheme.whiteText,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VineTheme.whiteText),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: body,
    );
  }
}
