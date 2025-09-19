// ABOUTME: VideoPlayerWidget component for displaying videos with video_player_media_kit backend
// ABOUTME: Handles video initialization, controls, error states, and lifecycle management

import 'package:cached_network_image/cached_network_image.dart';
import 'package:openvine/services/image_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:video_player/video_player.dart';

/// Video player widget with comprehensive state management
///
/// This widget handles video display using video_player with video_player_media_kit backend
/// and provides proper lifecycle management including error handling,
/// loading states, and memory cleanup.
class VideoPlayerWidget extends StatefulWidget {
  const VideoPlayerWidget({
    required this.videoEvent,
    super.key,
    this.controller,
    this.isActive = false,
    this.showControls = true,
    this.onVideoEnd,
    this.onVideoError,
    this.onVideoTap,
  });

  /// The video event to display
  final VideoEvent videoEvent;

  /// The video player controller (may be null during initialization)
  final VideoPlayerController? controller;

  /// Whether this video is currently active (should auto-play)
  final bool isActive;

  /// Whether to show video controls
  final bool showControls;

  /// Callback when video reaches end
  final VoidCallback? onVideoEnd;

  /// Callback when video encounters an error
  final VoidCallback? onVideoError;

  /// Callback when video is tapped
  final VoidCallback? onVideoTap;

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  bool _hasError = false;
  String? _errorMessage;
  bool _isInitializing = false;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reinitialize if controller changed
    if (widget.controller != oldWidget.controller) {
      _initializePlayer();
    }

    // Handle active state changes
    if (widget.isActive != oldWidget.isActive) {
      _handleActiveStateChange();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initializePlayer() {
    _hasError = false;
    _errorMessage = null;

    if (widget.controller == null) {
      setState(() {
        _isInitializing = true;
      });
      return;
    }

    try {
      if (widget.controller!.value.hasError) {
        _handleError('Video controller has error');
        return;
      }

      if (!widget.controller!.value.isInitialized) {
        setState(() {
          _isInitializing = true;
        });

        // Listen for initialization
        widget.controller!.addListener(_onControllerUpdate);
        return;
      }

      setState(() {
        _isInitializing = false;
        _hasError = false;
      });
    } catch (e) {
      _handleError('Failed to initialize video player: $e');
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;

    try {
      final controller = widget.controller;
      if (controller == null) return;

      if (controller.value.hasError) {
        _handleError(
            controller.value.errorDescription ?? 'Video playback error');
        return;
      }

      if (controller.value.isInitialized) {
        setState(() {
          _isInitializing = false;
          _hasError = false;
        });

        // Remove listener once initialized
        controller.removeListener(_onControllerUpdate);
      }

      // Handle video end
      if (controller.value.position >= controller.value.duration &&
          controller.value.duration > Duration.zero) {
        widget.onVideoEnd?.call();
      }
    } catch (e) {
      _handleError('Controller update error: $e');
    }
  }

  void _handleActiveStateChange() {
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (widget.isActive) {
        controller.play();
      } else {
        controller.pause();
      }
    } catch (e) {
      Log.error('Error handling active state change: $e',
          name: 'VideoPlayerWidget', category: LogCategory.ui);
    }
  }

  void _handleError(String message) {
    setState(() {
      _hasError = true;
      _errorMessage = message;
      _isInitializing = false;
    });

    widget.onVideoError?.call();
    Log.error('VideoPlayerWidget error: $message',
        name: 'VideoPlayerWidget', category: LogCategory.ui);
  }

  void _onRetryTap() {
    widget.onVideoError?.call();
    _initializePlayer();
  }

  void _toggleControls() {
    if (widget.showControls) {
      setState(() {
        _showControls = !_showControls;
      });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          widget.onVideoTap?.call();
          _toggleControls();
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background thumbnail
              if (widget.videoEvent.thumbnailUrl != null) _buildThumbnail(),

              // Video player or states
              if (_hasError)
                _buildErrorWidget(_errorMessage ?? 'Video failed to load')
              else if (_isInitializing || widget.controller == null)
                _buildLoadingWidget()
              else if (widget.controller?.value.isInitialized ?? false)
                _buildVideoPlayer()
              else
                _buildLoadingWidget(),

              // Video controls overlay
              if (_showControls && widget.showControls && !_hasError)
                _buildControlsOverlay(),
            ],
          ),
        ),
      );

  Widget _buildThumbnail() => CachedNetworkImage(
        imageUrl: widget.videoEvent.thumbnailUrl!,
        fit: BoxFit.cover,
        cacheManager: openVineImageCache,
        placeholder: (context, url) => Container(
          color: Colors.grey[900],
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[900],
        ),
      );

  Widget _buildVideoPlayer() => AspectRatio(
        aspectRatio: widget.controller!.value.aspectRatio,
        child: VideoPlayer(widget.controller!),
      );

  Widget _buildControlsOverlay() => Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () {
                  final controller = widget.controller;
                  if (controller?.value.isInitialized ?? false) {
                    if (controller!.value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  }
                },
                icon: Icon(
                  (widget.controller?.value.isPlaying ?? false)
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildLoadingWidget() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              SizedBox(height: 16),
              Text(
                'Initializing video...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildErrorWidget(String message) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Video failed to load',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _onRetryTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Tap to retry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
