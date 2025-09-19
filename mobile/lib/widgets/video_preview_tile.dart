// ABOUTME: Lightweight video preview tile for explore screen with auto-play functionality
// ABOUTME: Uses VideoManager providers for secure controller creation and memory management

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_thumbnail_widget.dart';
import 'package:video_player/video_player.dart';

/// Lightweight video preview widget for explore screens
/// Automatically plays when visible, pauses when scrolled away
class VideoPreviewTile extends ConsumerStatefulWidget {
  const VideoPreviewTile({
    required this.video,
    required this.isActive,
    super.key,
    this.height,
    this.onTap,
  });
  final VideoEvent video;
  final bool isActive;
  final double? height;
  final VoidCallback? onTap;

  @override
  ConsumerState<VideoPreviewTile> createState() => _VideoPreviewTileState();
}

class _VideoPreviewTileState extends ConsumerState<VideoPreviewTile>
    with AutomaticKeepAliveClientMixin {
  String? _videoControllerId;
  bool _isInitializing = false;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => false; // Don't keep alive to save memory

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      // Delay initialization slightly to ensure widget is mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeVideo();
        }
      });
    }
  }

  @override
  void didUpdateWidget(VideoPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _initializeVideo();
      } else {
        _disposeVideo();
      }
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (_isInitializing ||
        _videoControllerId != null ||
        !widget.video.hasVideo) {
      return;
    }

    setState(() {
      _isInitializing = true;
      _hasError = false;
    });

    try {
      Log.debug(
          'Initializing preview for ${widget.video.id.substring(0, 8)}...',
          name: 'VideoPreviewTile',
          category: LogCategory.ui);
      Log.debug('   Video URL: ${widget.video.videoUrl}',
          name: 'VideoPreviewTile', category: LogCategory.ui);
      Log.debug('   Thumbnail URL: ${widget.video.effectiveThumbnailUrl}',
          name: 'VideoPreviewTile', category: LogCategory.ui);

      // Use VideoManager to create controller securely
      final videoManager = ref.read(videoManagerProvider.notifier);
      final controllerId = 'preview_${widget.video.id}';

      final controller = await videoManager.createNetworkController(
        controllerId,
        widget.video.videoUrl!,
        priority: PreloadPriority.current,
      );

      if (controller != null && mounted && widget.isActive) {
        _videoControllerId = controllerId;

        // Pause all other videos before playing this one
        videoManager.pauseAllVideos();

        await controller.setLooping(true);
        await controller.setVolume(0); // Mute for preview
        await controller.play();

        setState(() {
          _isInitializing = false;
        });

        Log.info('Preview playing for ${widget.video.id.substring(0, 8)}',
            name: 'VideoPreviewTile', category: LogCategory.ui);
      } else {
        setState(() {
          _hasError = true;
          _isInitializing = false;
        });
      }
    } catch (e) {
      Log.error(
          'Preview initialization failed for ${widget.video.id.substring(0, 8)}: $e',
          name: 'VideoPreviewTile',
          category: LogCategory.ui);
      Log.debug('   Video URL was: ${widget.video.videoUrl}',
          name: 'VideoPreviewTile', category: LogCategory.ui);
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitializing = false;
        });
      }
    }
  }

  void _disposeVideo() {
    Log.debug('📱️ Disposing preview for ${widget.video.id.substring(0, 8)}...',
        name: 'VideoPreviewTile', category: LogCategory.ui);
    if (_videoControllerId != null) {
      // VideoManager will handle cleanup and GlobalVideoRegistry coordination
      ref.read(videoManagerProvider.notifier).disposeVideo(_videoControllerId!);
      _videoControllerId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Watch for the controller via VideoManager provider
    final controller = _videoControllerId != null
        ? ref.watch(videoPlayerControllerProvider(_videoControllerId!))
        : null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video or thumbnail
              if (controller != null && controller.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                )
              else
                VideoThumbnailWidget(
                  video: widget.video,
                  fit: BoxFit.cover,
                  showPlayIcon: false,
                ),

              // Loading indicator
              if (_isInitializing)
                const ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: VineTheme.vineGreen,
                      strokeWidth: 2,
                    ),
                  ),
                ),

              // Play button overlay (only show when not playing)
              if (!widget.isActive ||
                  controller == null ||
                  !controller.value.isInitialized)
                const Center(
                  child: Icon(
                    Icons.play_circle_filled,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),

              // Error overlay
              if (_hasError)
                const ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Failed to load',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
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
}
