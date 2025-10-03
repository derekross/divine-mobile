// ABOUTME: Video feed item using individual controller architecture
// ABOUTME: Each video gets its own controller with automatic lifecycle management via Riverpod autoDispose

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:video_player/video_player.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/individual_video_providers.dart';
import 'package:openvine/providers/social_providers.dart';
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/screens/comments_screen.dart';
import 'package:openvine/widgets/video_thumbnail_widget.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/share_video_menu.dart';
import 'package:openvine/widgets/video_metrics_tracker.dart';
import 'package:openvine/main.dart';
import 'package:openvine/utils/string_utils.dart';
import 'package:openvine/widgets/clickable_hashtag_text.dart';

/// Video feed item using individual controller architecture
class VideoFeedItem extends ConsumerStatefulWidget {
  const VideoFeedItem({
    super.key,
    required this.video,
    required this.index,
    this.onTap,
    this.forceShowOverlay = false,
    this.hasBottomNavigation = true,
    this.contextTitle,
  });

  final VideoEvent video;
  final int index;
  final VoidCallback? onTap;
  final bool forceShowOverlay;
  final bool hasBottomNavigation;
  final String? contextTitle;

  @override
  ConsumerState<VideoFeedItem> createState() => _VideoFeedItemState();
}

class _VideoFeedItemState extends ConsumerState<VideoFeedItem> {
  Offset? _tapStartPosition;
  DateTime? _tapStartTime;
  int _playbackGeneration = 0; // Prevents race conditions with rapid state changes

  /// Translate error messages to user-friendly text
  static String _getErrorMessage(String? errorDescription) {
    if (errorDescription == null) return 'Video playback error';

    final lowerError = errorDescription.toLowerCase();

    if (lowerError.contains('404') || lowerError.contains('not found')) {
      return 'Video not found';
    }
    if (lowerError.contains('network') || lowerError.contains('connection')) {
      return 'Network error';
    }
    if (lowerError.contains('timeout')) {
      return 'Loading timeout';
    }
    if (lowerError.contains('byte range') || lowerError.contains('coremediaerrordomain')) {
      return 'Video format error\n(Try again or use different browser)';
    }
    if (lowerError.contains('format') || lowerError.contains('codec')) {
      return 'Unsupported video format';
    }

    return 'Video playback error';
  }

  @override
  void initState() {
    super.initState();

    // Listen for active state changes to control playback
    // Widget is responsible for play/pause, NOT the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check initial state and start playback if already active
      final isActive = ref.read(isVideoActiveProvider(widget.video.id));
      if (isActive) {
        _handlePlaybackChange(true);
      }

      // Listen for future changes
      ref.listenManual(
        isVideoActiveProvider(widget.video.id),
        (prev, next) => _handlePlaybackChange(next),
      );
    });
  }

  @override
  void dispose() {
    // CRITICAL: Always pause video when widget is disposed
    // This ensures videos don't play in background tabs
    try {
      final controllerParams = VideoControllerParams(
        videoId: widget.video.id,
        videoUrl: widget.video.videoUrl!,
        videoEvent: widget.video,
      );
      final controller = ref.read(individualVideoControllerProvider(controllerParams));

      if (controller.value.isPlaying) {
        final videoIdDisplay = widget.video.id.length > 8 ? widget.video.id.substring(0, 8) : widget.video.id;
        Log.info('⏸️ Pausing video $videoIdDisplay... on widget dispose',
            name: 'VideoFeedItem', category: LogCategory.ui);
        controller.pause(); // Fire and forget - widget is disposing
      }
    } catch (e) {
      Log.error('❌ Error pausing video on dispose: $e',
          name: 'VideoFeedItem', category: LogCategory.ui);
    }

    super.dispose();
  }

  /// Handle playback state changes with generation counter to prevent race conditions
  void _handlePlaybackChange(bool shouldPlay) {
    final gen = ++_playbackGeneration;
    final videoIdDisplay = widget.video.id.length > 8 ? widget.video.id.substring(0, 8) : widget.video.id;

    try {
      final controllerParams = VideoControllerParams(
        videoId: widget.video.id,
        videoUrl: widget.video.videoUrl!,
        videoEvent: widget.video,
      );
      final controller = ref.read(individualVideoControllerProvider(controllerParams));

      if (shouldPlay && controller.value.isInitialized && !controller.value.isPlaying) {
        Log.info('▶️ Widget starting video $videoIdDisplay...',
            name: 'VideoFeedItem', category: LogCategory.ui);
        controller.play().then((_) {
          if (gen != _playbackGeneration) {
            Log.debug('⏭️ Ignoring stale play() completion for $videoIdDisplay...',
                name: 'VideoFeedItem', category: LogCategory.ui);
          }
        }).catchError((error) {
          if (gen == _playbackGeneration) {
            Log.error('❌ Widget failed to play video $videoIdDisplay...: $error',
                name: 'VideoFeedItem', category: LogCategory.ui);
          }
        });
      } else if (!shouldPlay && controller.value.isPlaying) {
        Log.info('⏸️ Widget pausing video $videoIdDisplay...',
            name: 'VideoFeedItem', category: LogCategory.ui);
        controller.pause().then((_) {
          if (gen != _playbackGeneration) {
            Log.debug('⏭️ Ignoring stale pause() completion for $videoIdDisplay...',
                name: 'VideoFeedItem', category: LogCategory.ui);
          }
        }).catchError((error) {
          if (gen == _playbackGeneration) {
            Log.error('❌ Widget failed to pause video $videoIdDisplay...: $error',
                name: 'VideoFeedItem', category: LogCategory.ui);
          }
        });
      }
    } catch (e) {
      Log.error('❌ Error in playback change handler: $e',
          name: 'VideoFeedItem', category: LogCategory.ui);
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final videoIdDisplay = video.id.length > 8 ? video.id.substring(0, 8) : video.id;
    Log.debug('🏗️ VideoFeedItem.build() for video $videoIdDisplay..., index: ${widget.index}',
        name: 'VideoFeedItem', category: LogCategory.ui);

    // Skip rendering if no video URL
    if (video.videoUrl == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.error_outline, color: Colors.white, size: 48),
        ),
      );
    }

    // Watch if this video is currently active
    final isActive = ref.watch(isVideoActiveProvider(video.id));

    Log.debug('📱 VideoFeedItem state: isActive=$isActive',
        name: 'VideoFeedItem', category: LogCategory.ui);

    return VisibilityDetector(
      key: Key('video_${video.id}'),
      onVisibilityChanged: (info) {
        final isVisible = info.visibleFraction > 0.7;
        Log.debug('👁️ Visibility callback: $videoIdDisplay... fraction=${info.visibleFraction.toStringAsFixed(3)}, isVisible=$isVisible',
            name: 'VideoFeedItem', category: LogCategory.ui);

        try {
          final currentActiveId = ref.read(activeVideoProvider);
          if (isVisible) {
            if (currentActiveId != video.id) {
              Log.debug('📱 Video $videoIdDisplay... visible, setting as active',
                  name: 'VideoFeedItem', category: LogCategory.ui);
              ref.read(activeVideoProvider.notifier).setActiveVideo(video.id);
            }
          } else {
            // Don't clear active state when scrolling - let other videos set themselves as active
            // Only clear if this was the active video and no other video will become active
            Log.debug('📱 Video $videoIdDisplay... no longer visible (keeping active state for smooth transitions)',
                name: 'VideoFeedItem', category: LogCategory.ui);
          }
        } catch (e) {
          Log.error('❌ Error in VisibilityDetector callback for $videoIdDisplay...: $e',
              name: 'VideoFeedItem', category: LogCategory.ui);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () {
          Log.debug('📱 Tap detected on VideoFeedItem for $videoIdDisplay...',
              name: 'VideoFeedItem', category: LogCategory.ui);
          try {
            if (isActive) {
              // Toggle play/pause only if currently active
              final controllerParams = VideoControllerParams(
                videoId: video.id,
                videoUrl: video.videoUrl!,
                videoEvent: video,
              );
              final controller = ref.read(individualVideoControllerProvider(controllerParams));
              if (controller.value.isPlaying) {
                controller.pause();
              } else if (controller.value.isInitialized) {
                controller.play();
              }
            } else {
              // Make this video active when tapped
              ref.read(activeVideoProvider.notifier).setActiveVideo(video.id);
            }
            widget.onTap?.call();
          } catch (e) {
            Log.error('❌ Error in VideoFeedItem tap handler for $videoIdDisplay...: $e',
                name: 'VideoFeedItem', category: LogCategory.ui);
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Per-item video controller rendering when active
              if (isActive)
                Consumer(
                  builder: (context, ref, child) {
                    final controllerParams = VideoControllerParams(
                      videoId: video.id,
                      videoUrl: video.videoUrl!,
                      videoEvent: video,
                    );
                    final controller = ref.watch(
                      individualVideoControllerProvider(controllerParams),
                    );

                    // Wrap with VideoMetricsTracker to track engagement and mark as seen
                    return VideoMetricsTracker(
                      video: video,
                      controller: controller,
                      // Listen to controller value so UI updates when initialized/playing state changes
                      child: ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          // Let the individual controller handle autoplay based on active state
                          // Don't interfere with playback control here

                          // Check for video error state
                          if (value.hasError) {
                          final errorMessage = _getErrorMessage(value.errorDescription);
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              // Show thumbnail as background
                              VideoThumbnailWidget(
                                video: video,
                                fit: BoxFit.cover,
                                showPlayIcon: false,
                              ),
                              // Error overlay
                              Container(
                                color: Colors.black54,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        errorMessage,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: () {
                                          // Retry by invalidating and recreating the controller
                                          ref.invalidate(
                                            individualVideoControllerProvider(controllerParams),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                        ),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (!value.isInitialized) {
                          // Show thumbnail/blurhash while the video initializes
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              VideoThumbnailWidget(
                                video: video,
                                fit: BoxFit.cover,
                                showPlayIcon: false,
                              ),
                              const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                ),
                              ),
                            ],
                          );
                        }

                        // Use BoxFit.contain for square/landscape videos to avoid cropping
                        // Use BoxFit.cover for portrait videos to fill the screen
                        final aspectRatio = value.size.width / value.size.height;
                        final isPortraitVideo = aspectRatio < 0.9; // Portrait if width < height (with 10% tolerance)

                        return SizedBox.expand(
                          child: FittedBox(
                            fit: isPortraitVideo ? BoxFit.cover : BoxFit.contain,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: value.size.width == 0 ? 1 : value.size.width,
                              height: value.size.height == 0 ? 1 : value.size.height,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        );
                        },
                      ),
                    );
                  },
                )
              else
                // Inactive: show thumbnail/blurhash with play overlay
                VideoThumbnailWidget(
                  video: video,
                  fit: BoxFit.cover,
                  showPlayIcon: true,
                ),

              // Video overlay with actions
              VideoOverlayActions(
                video: video,
                isVisible: widget.forceShowOverlay || isActive,
                hasBottomNavigation: widget.hasBottomNavigation,
                contextTitle: widget.contextTitle,
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Video overlay actions widget with working functionality
class VideoOverlayActions extends ConsumerWidget {
  const VideoOverlayActions({
    super.key,
    required this.video,
    required this.isVisible,
    this.hasBottomNavigation = true,
    this.contextTitle,
  });

  final VideoEvent video;
  final bool isVisible;
  final bool hasBottomNavigation;
  final String? contextTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isVisible) return const SizedBox();

    final socialState = ref.watch(socialProvider);
    final isLiked = socialState.isLiked(video.id);
    final isLikeInProgress = socialState.isLikeInProgress(video.id);
    final likeCount = socialState.likeCounts[video.id] ?? 0;

    return Stack(
      children: [
        // Publisher chip (tap to profile)
        Positioned(
          top: MediaQuery.of(context).viewPadding.top + 16,
          left: 16,
          child: Consumer(builder: (context, ref, _) {
            final profileAsync = ref.watch(fetchUserProfileProvider(video.pubkey));
            final display = profileAsync.maybeWhen(
                  data: (p) => p?.bestDisplayName ?? p?.displayName ?? p?.name,
                  orElse: () => null,
                ) ?? 'npub:${video.pubkey.length > 8 ? video.pubkey.substring(0, 8) : video.pubkey}';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    try {
                      mainNavigationKey.currentState?.navigateToProfile(video.pubkey);
                    } catch (_) {}
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          display,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Context title chip (e.g., hashtag)
                if (contextTitle != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tag, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          contextTitle!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
        // Video title overlay at bottom left
        Positioned(
          bottom: 0,
          left: 16,
          right: 80, // Leave space for action buttons
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Video title with clickable hashtags
                ClickableHashtagText(
                  text: video.content.isNotEmpty ? video.content : video.title ?? 'Untitled',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 2,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  hashtagStyle: TextStyle(
                    color: Colors.blue[300],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    shadows: const [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 2,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Show original loop count if available
                if (video.originalLoops != null && video.originalLoops! > 0) ...[
                  Text(
                    '🔁 ${StringUtils.formatCompactNumber(video.originalLoops!)} loops',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 2,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ),
        // Action buttons at bottom right
        Positioned(
          bottom: 0,
          right: 16,
          child: Column(
            children: [
          // Like button
          Column(
            children: [
              IconButton(
                onPressed: isLikeInProgress ? null : () async {
                  Log.info(
                    '❤️ Like button tapped for ${video.id}',
                    name: 'VideoFeedItem',
                    category: LogCategory.ui,
                  );
                  await ref.read(socialProvider.notifier)
                    .toggleLike(video.id, video.pubkey);
                },
                icon: isLikeInProgress
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isLiked ? Icons.favorite : Icons.favorite_outline,
                      color: isLiked ? Colors.red : Colors.white,
                      size: 32,
                    ),
              ),
              // Show total like count: new likes + original Vine likes
              if (likeCount > 0 || (video.originalLikes != null && video.originalLikes! > 0)) ...[
                const SizedBox(height: 4),
                Text(
                  StringUtils.formatCompactNumber(likeCount + (video.originalLikes ?? 0)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Comment button with count
          Column(
            children: [
              IconButton(
                onPressed: () {
                  Log.info(
                    '💬 Comment button tapped for ${video.id}',
                    name: 'VideoFeedItem',
                    category: LogCategory.ui,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => CommentsScreen(videoEvent: video),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.comment_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              // Show original comment count if available
              if (video.originalComments != null && video.originalComments! > 0) ...[
                const SizedBox(height: 4),
                Text(
                  StringUtils.formatCompactNumber(video.originalComments!),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Share button
          IconButton(
            onPressed: () {
              Log.info(
                '📤 Share button tapped for ${video.id}',
                name: 'VideoFeedItem',
                category: LogCategory.ui,
              );
              _showShareMenu(context, video);
            },
            icon: const Icon(
              Icons.share_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
            ],
          ),
        ),
      ],
    );
  }

  void _showShareMenu(BuildContext context, VideoEvent video) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareVideoMenu(video: video),
    );
  }
}