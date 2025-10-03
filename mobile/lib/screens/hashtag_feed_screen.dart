// ABOUTME: Screen displaying videos filtered by a specific hashtag
// ABOUTME: Allows users to explore all videos with a particular hashtag

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/screens/pure/explore_video_screen_pure.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:openvine/widgets/video_thumbnail_widget.dart';

class HashtagFeedScreen extends ConsumerStatefulWidget {
  const HashtagFeedScreen({required this.hashtag, this.embedded = false, this.onVideoTap, super.key});
  final String hashtag;
  final bool embedded;  // If true, don't show Scaffold/AppBar (for embedding in explore)
  final void Function(List<VideoEvent> videos, int index)? onVideoTap;  // Callback for video navigation when embedded

  @override
  ConsumerState<HashtagFeedScreen> createState() => _HashtagFeedScreenState();
}

class _HashtagFeedScreenState extends ConsumerState<HashtagFeedScreen> {

  Widget _buildVideoTile(VideoEvent video, int index, List<VideoEvent> videos, BuildContext context) {
    return GestureDetector(
      onTap: () {
        // If embedded, use callback to tell parent to enter feed mode
        // Otherwise, navigate to full-screen video player
        if (widget.embedded && widget.onVideoTap != null) {
          widget.onVideoTap!(videos, index);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ExploreVideoScreenPure(
                startingVideo: video,
                videoList: videos,
                contextTitle: '#${widget.hashtag}',
                startingIndex: index,
              ),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: VineTheme.cardBackground,
          borderRadius: BorderRadius.circular(0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Column(
            children: [
              // Video thumbnail with play overlay
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: VineTheme.cardBackground,
                      child: video.thumbnailUrl != null
                          ? VideoThumbnailWidget(
                              video: video,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Container(
                              color: VineTheme.cardBackground,
                              child: Icon(
                                Icons.videocam,
                                size: 40,
                                color: VineTheme.secondaryText,
                              ),
                            ),
                    ),
                    // Play button overlay
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: VineTheme.darkOverlay,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: VineTheme.whiteText,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Video info section
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        video.content.isNotEmpty ? video.content : video.title ?? 'Untitled',
                        style: const TextStyle(
                          color: VineTheme.primaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    // Subscribe to videos with this hashtag
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hashtagService = ref.read(hashtagServiceProvider);
      hashtagService.subscribeToHashtagVideos([widget.hashtag]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = Builder(
          builder: (context) {
            final videoService = ref.watch(videoEventServiceProvider);
            final hashtagService = ref.watch(hashtagServiceProvider);
            final videos = List<VideoEvent>.from(
              hashtagService.getVideosByHashtags([widget.hashtag]),
            )..sort(VideoEvent.compareByLoopsThenTime);

            if (videoService.isLoading && videos.isEmpty) {
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
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return _buildVideoTile(video, index, videos, context);
                },
              );
            }

            // Standalone mode: full-screen scrollable list
            final isLoadingMore = videoService.isLoading;

            return ListView.builder(
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
                    // If embedded, use callback to tell parent to enter feed mode
                    // Otherwise, navigate to inline video player
                    if (widget.embedded && widget.onVideoTap != null) {
                      widget.onVideoTap!(videos, index);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ExploreVideoScreenPure(
                            startingVideo: video,
                            videoList: videos,
                            contextTitle: '#${widget.hashtag}',
                            startingIndex: index,
                          ),
                        ),
                      );
                    }
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
