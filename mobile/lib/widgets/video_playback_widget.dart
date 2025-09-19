// ABOUTME: Reusable video playback widget using consolidated VideoPlaybackController
// ABOUTME: Provides consistent video behavior with configuration-based customization

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/video_playback_controller.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:video_player/video_player.dart';

/// Reusable video widget with consolidated playback behavior
class VideoPlaybackWidget extends StatefulWidget {
  const VideoPlaybackWidget({
    required this.video,
    super.key,
    this.config = VideoPlaybackConfig.feed,
    this.isActive = true,
    this.placeholder,
    this.errorWidget,
    this.onTap,
    this.onDoubleTap,
    this.onError,
    this.overlayPadding,
    this.overlayWidgets,
    this.showControls = false,
    this.showPlayPauseIcon = true,
  });
  final VideoEvent video;
  final VideoPlaybackConfig config;
  final bool isActive;
  final Widget? placeholder;
  final Widget? errorWidget;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Function(String)? onError;
  final EdgeInsetsGeometry? overlayPadding;
  final List<Widget>? overlayWidgets;
  final bool showControls;
  final bool showPlayPauseIcon;

  /// Create widget configured for feed videos
  static VideoPlaybackWidget feed({
    required VideoEvent video,
    required bool isActive,
    Key? key,
    VoidCallback? onTap,
    Function(String)? onError,
    List<Widget>? overlayWidgets,
  }) =>
      VideoPlaybackWidget(
        key: key,
        video: video,
        config: VideoPlaybackConfig.feed,
        isActive: isActive,
        onTap: onTap,
        onError: onError,
        overlayWidgets: overlayWidgets,
        showPlayPauseIcon: true,
      );

  /// Create widget configured for fullscreen videos
  static VideoPlaybackWidget fullscreen({
    required VideoEvent video,
    Key? key,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    Function(String)? onError,
    List<Widget>? overlayWidgets,
  }) =>
      VideoPlaybackWidget(
        key: key,
        video: video,
        config: VideoPlaybackConfig.fullscreen,
        isActive: true,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onError: onError,
        overlayWidgets: overlayWidgets,
        showPlayPauseIcon: true,
      );

  /// Create widget configured for preview/thumbnail videos
  static VideoPlaybackWidget preview({
    required VideoEvent video,
    Key? key,
    Widget? placeholder,
    VoidCallback? onTap,
    Function(String)? onError,
  }) =>
      VideoPlaybackWidget(
        key: key,
        video: video,
        config: VideoPlaybackConfig.preview,
        isActive: false,
        placeholder: placeholder,
        onTap: onTap,
        onError: onError,
        showPlayPauseIcon: false,
      );

  @override
  State<VideoPlaybackWidget> createState() => _VideoPlaybackWidgetState();
}

class _VideoPlaybackWidgetState extends State<VideoPlaybackWidget>
    with TickerProviderStateMixin {
  late VideoPlaybackController _playbackController;
  late AnimationController _playPauseIconController;
  late Animation<double> _playPauseIconAnimation;
  bool _showPlayPauseIcon = false;

  @override
  void initState() {
    super.initState();

    _playbackController = VideoPlaybackController(
      video: widget.video,
      config: widget.config,
    );

    _playPauseIconController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _playPauseIconAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(
      CurvedAnimation(
        parent: _playPauseIconController,
        curve: Curves.elasticOut,
      ),
    );

    // REFACTORED: Service no longer extends ChangeNotifier - use Riverpod ref.watch instead
    _playbackController.events.listen(_onPlaybackEvent);

    _initializeVideo();
  }

  @override
  void didUpdateWidget(VideoPlaybackWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive != oldWidget.isActive) {
      _playbackController.setActive(widget.isActive);
    }
  }

  @override
  void dispose() {
    _playPauseIconController.dispose();
    _playbackController.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    try {
      await _playbackController.initialize();
      _playbackController.setActive(widget.isActive);
    } catch (e) {
      widget.onError?.call('Failed to initialize video: $e');
    }
  }

  // Removed unused _onPlaybackStateChange method

  void _onPlaybackEvent(VideoPlaybackEvent event) {
    if (event is VideoError) {
      widget.onError?.call(event.message);
    }
  }

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      // Default behavior: toggle play/pause
      _playbackController.togglePlayPause();
      if (widget.showPlayPauseIcon) {
        _showPlayPauseIconBriefly();
      }
    }
  }

  void _handleDoubleTap() {
    if (widget.onDoubleTap != null) {
      widget.onDoubleTap!();
    }
  }

  void _showPlayPauseIconBriefly() {
    if (!_playbackController.isInitialized) return;

    setState(() {
      _showPlayPauseIcon = true;
    });

    // FIXED: Use animation completion instead of arbitrary delay
    _playPauseIconController.forward().then((_) {
      _playPauseIconController.reverse().then((_) {
        // Hide icon after animation completes
        if (mounted) {
          setState(() {
            _showPlayPauseIcon = false;
          });
        }
      });
    });
  }

  /// Navigation helper for consistent pause/resume behavior
  Future<T?> navigateWithPause<T>(Widget destination) async =>
      _playbackController.navigateWithPause(
        () async => Navigator.of(context).push<T>(
          MaterialPageRoute(builder: (context) => destination),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            // Main video content
            _buildVideoContent(),

            // Custom overlay widgets
            if (widget.overlayWidgets != null) ...widget.overlayWidgets!,

            // Play/pause icon overlay
            if (_showPlayPauseIcon && widget.showPlayPauseIcon)
              _buildPlayPauseIconOverlay(),

            // Touch handlers
            Positioned.fill(
              child: GestureDetector(
                onTap: _handleTap,
                onDoubleTap: _handleDoubleTap,
                child: Container(color: Colors.transparent),
              ),
            ),
          ],
        ),
      );

  Widget _buildVideoContent() {
    switch (_playbackController.state) {
      case VideoPlaybackState.notInitialized:
      case VideoPlaybackState.initializing:
        return _buildLoadingState();

      case VideoPlaybackState.ready:
      case VideoPlaybackState.playing:
      case VideoPlaybackState.paused:
      case VideoPlaybackState.buffering:
        return _buildVideoPlayer();

      case VideoPlaybackState.error:
        return _buildErrorState();

      case VideoPlaybackState.disposed:
        return _buildDisposedState();
    }
  }

  Widget _buildVideoPlayer() {
    final controller = _playbackController.controller;
    if (controller == null) {
      return _buildLoadingState();
    }

    // Calculate display size - for Mac, scale up small videos for better visibility
    final videoSize = controller.value.size;
    final isSmallVideo = videoSize.width <= 400 && videoSize.height <= 400;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;

    // Double size for small videos on Mac to improve visibility
    final displayScale = (isMac && isSmallVideo) ? 2.0 : 1.0;

    // Different behavior based on configuration
    if (widget.config == VideoPlaybackConfig.fullscreen) {
      // Fullscreen mode: fill the entire screen
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Transform.scale(
            scale: displayScale,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      // Feed and preview modes: maintain square aspect ratio for old school vine style
      return Center(
        child: AspectRatio(
          aspectRatio: 1.0, // Force 1:1 square aspect ratio
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit
                    .cover, // Cover the square area, cropping if necessary
                child: Transform.scale(
                  scale: displayScale,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildLoadingState() =>
      widget.placeholder ??
      Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Loading...',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );

  Widget _buildErrorState() =>
      widget.errorWidget ??
      Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_off,
                size: 64,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              const Text(
                'Video unavailable',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_playbackController.errorMessage != null)
                Text(
                  _playbackController.errorMessage!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _playbackController.retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VineTheme.vineGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _buildDisposedState() => Container(
        color: Colors.grey[700],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.delete_outline,
                size: 64,
                color: Colors.white54,
              ),
              SizedBox(height: 16),
              Text(
                'Video disposed',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildPlayPauseIconOverlay() {
    final isPlaying = _playbackController.isPlaying;

    return AnimatedBuilder(
      animation: _playPauseIconAnimation,
      builder: (context, child) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Transform.scale(
            scale: _playPauseIconAnimation.value,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.black,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
