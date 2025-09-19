// ABOUTME: Widget that displays the first frame of a video as a thumbnail
// ABOUTME: Uses VideoPlayer in a paused state at position 0 to show as thumbnail

import 'package:flutter/material.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:video_player/video_player.dart';

/// Widget that shows the first frame of a video as a thumbnail
/// This is used as a fallback when no thumbnail URL is available
class VideoFrameThumbnail extends StatefulWidget {
  const VideoFrameThumbnail({
    required this.videoUrl,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<VideoFrameThumbnail> createState() => _VideoFrameThumbnailState();
}

class _VideoFrameThumbnailState extends State<VideoFrameThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    try {
      Log.info(
        '📹 Initializing video for thumbnail: ${widget.videoUrl.substring(0, 50)}...',
        name: 'VideoFrameThumbnail',
        category: LogCategory.video,
      );

      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      
      await _controller!.initialize();
      
      // Seek to first frame
      await _controller!.seekTo(Duration.zero);
      
      // Ensure it's paused
      await _controller!.pause();
      
      // Set volume to 0 to ensure no sound
      await _controller!.setVolume(0);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      
      Log.info(
        '✅ Video thumbnail initialized successfully',
        name: 'VideoFrameThumbnail',
        category: LogCategory.video,
      );
    } catch (e) {
      Log.error(
        'Failed to initialize video thumbnail: $e',
        name: 'VideoFrameThumbnail',
        category: LogCategory.video,
      );
      
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    
    if (_hasError) {
      // Show error placeholder
      content = Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[900],
        child: const Center(
          child: Icon(
            Icons.error_outline,
            color: Colors.grey,
            size: 32,
          ),
        ),
      );
    } else if (!_isInitialized) {
      // Show loading state
      content = Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[900],
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
            ),
          ),
        ),
      );
    } else {
      // Show video frame
      content = SizedBox(
        width: widget.width,
        height: widget.height,
        child: FittedBox(
          fit: widget.fit,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }
    
    // Apply border radius if specified
    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }
    
    return content;
  }
}