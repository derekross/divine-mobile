// ABOUTME: Smart video thumbnail widget that displays thumbnails or blurhash placeholders
// ABOUTME: Uses existing thumbnail URLs from video events and falls back to blurhash when missing

import 'package:flutter/material.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/thumbnail_api_service.dart'
    show ThumbnailSize;
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/blurhash_display.dart';
import 'package:openvine/widgets/video_frame_thumbnail.dart';
import 'package:openvine/widgets/video_icon_placeholder.dart';

/// Smart thumbnail widget that displays thumbnails with blurhash fallback
class VideoThumbnailWidget extends StatefulWidget {
  const VideoThumbnailWidget({
    required this.video,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.timeSeconds = 2.5,
    this.size = ThumbnailSize.medium,
    this.showPlayIcon = false,
    this.borderRadius,
  });
  final VideoEvent video;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double timeSeconds;
  final ThumbnailSize size;
  final bool showPlayIcon;
  final BorderRadius? borderRadius;

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  String? _thumbnailUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if video ID changed
    if (oldWidget.video.id != widget.video.id) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    // Check if we have an existing thumbnail URL
    if (widget.video.thumbnailUrl != null &&
        widget.video.thumbnailUrl!.isNotEmpty) {
      setState(() {
        _thumbnailUrl = widget.video.thumbnailUrl;
        _isLoading = false;
      });
      return;
    }

    try {
      final generatedThumbnailUrl = await widget.video.getApiThumbnailUrl();
      if (generatedThumbnailUrl != null && generatedThumbnailUrl.isNotEmpty) {
        setState(() {
          _thumbnailUrl = generatedThumbnailUrl;
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      // Silently fail - will use blurhash or placeholder
    }

    setState(() {
      _thumbnailUrl = null;
      _isLoading = false;
    });
  }

  Widget _buildContent() {
    // While determining what thumbnail to use, show blurhash if available
    if (_isLoading && widget.video.blurhash != null) {
      return Stack(
        children: [
          BlurhashDisplay(
            blurhash: widget.video.blurhash!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
          ),
          if (widget.showPlayIcon)
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      );
    }

    if (_isLoading) {
      return VideoIconPlaceholder(
        width: widget.width,
        height: widget.height,
        showLoading: true,
        showPlayIcon: widget.showPlayIcon,
        borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
      );
    }

    if (_thumbnailUrl != null) {
      // Show the thumbnail with blurhash as placeholder while loading
      return Stack(
        fit: StackFit.expand,
        children: [
          // Show blurhash as background while image loads
          if (widget.video.blurhash != null)
            BlurhashDisplay(
              blurhash: widget.video.blurhash!,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
            ),
          // Actual thumbnail image
          Image.network(
            _thumbnailUrl!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child; // Image loaded
              }
              // While loading, show blurhash or placeholder
              if (widget.video.blurhash != null) {
                return BlurhashDisplay(
                  blurhash: widget.video.blurhash!,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                );
              }
              return VideoIconPlaceholder(
                width: widget.width,
                height: widget.height,
                showLoading: true,
                showPlayIcon: widget.showPlayIcon,
                borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
              );
            },
            errorBuilder: (context, error, stackTrace) {
              Log.error('Failed to load thumbnail: $_thumbnailUrl',
                  name: 'VideoThumbnailWidget', category: LogCategory.video);
              Log.error(
                  '🐛 THUMBNAIL ERROR for ${widget.video.id.substring(0, 8)}: blurhash="${widget.video.blurhash}"',
                  name: 'VideoThumbnailWidget',
                  category: LogCategory.video);
              // On error, show blurhash or placeholder
              if (widget.video.blurhash != null) {
                return BlurhashDisplay(
                  blurhash: widget.video.blurhash!,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                );
              }
              return VideoIconPlaceholder(
                width: widget.width,
                height: widget.height,
                showPlayIcon: widget.showPlayIcon,
                borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
              );
            },
          ),
          // Play icon overlay if requested
          if (widget.showPlayIcon)
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      );
    }

    // No thumbnail URL - show blurhash if available, otherwise placeholder
    if (widget.video.blurhash != null) {
      Log.debug(
        '🖼️ Using blurhash as fallback',
        name: 'VideoThumbnailWidget',
        category: LogCategory.ui,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          BlurhashDisplay(
            blurhash: widget.video.blurhash!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
          ),
          if (widget.showPlayIcon)
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      );
    }

    // Try to use video first frame as fallback
    if (widget.video.videoUrl != null && widget.video.videoUrl!.isNotEmpty) {
      Log.debug(
        '🖼️ No blurhash available - using video first frame',
        name: 'VideoThumbnailWidget',
        category: LogCategory.ui,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          VideoFrameThumbnail(
            videoUrl: widget.video.videoUrl!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            borderRadius: widget.borderRadius,
          ),
          if (widget.showPlayIcon)
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      );
    }
    
    // Final fallback - icon placeholder
    Log.debug(
      '🖼️ No video URL available - using icon placeholder',
      name: 'VideoThumbnailWidget',
      category: LogCategory.ui,
    );
    return VideoIconPlaceholder(
      width: widget.width,
      height: widget.height,
      showPlayIcon: widget.showPlayIcon,
      borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    var content = _buildContent();

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }
}
