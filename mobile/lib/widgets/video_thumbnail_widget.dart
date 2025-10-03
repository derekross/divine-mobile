// ABOUTME: Smart video thumbnail widget that displays thumbnails or blurhash placeholders
// ABOUTME: Uses existing thumbnail URLs from video events and falls back to blurhash when missing

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/thumbnail_api_service.dart'
    show ThumbnailSize;
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/blurhash_display.dart';
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
          // Actual thumbnail image with error boundary
          _SafeNetworkImage(
            url: _thumbnailUrl!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            videoId: widget.video.id,
            blurhash: widget.video.blurhash,
            showPlayIcon: widget.showPlayIcon,
            borderRadius: widget.borderRadius,
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

    // Avoid spinning video controllers for thumbnails; fall back to icon
    if (widget.video.videoUrl != null && widget.video.videoUrl!.isNotEmpty) {
      return VideoIconPlaceholder(
        width: widget.width,
        height: widget.height,
        showPlayIcon: widget.showPlayIcon,
        borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
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

/// Error-safe network image widget that prevents HTTP 404 and other network exceptions
/// Uses CachedNetworkImage which handles network errors more gracefully than Image.network
class _SafeNetworkImage extends StatelessWidget {
  const _SafeNetworkImage({
    required this.url,
    required this.videoId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.blurhash,
    this.showPlayIcon = false,
    this.borderRadius,
  });

  final String url;
  final String videoId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? blurhash;
  final bool showPlayIcon;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => _buildFallback(),
      errorWidget: (context, url, error) {
        // Log the specific error for debugging
        Log.error('Network image failed: $url',
            name: 'VideoThumbnailWidget', category: LogCategory.video);
        Log.error('Error type: ${error.runtimeType}, Details: $error',
            name: 'VideoThumbnailWidget', category: LogCategory.video);

        // Check if this is specifically a 404 or HTTP error
        if (error.toString().contains('404') ||
            error.toString().contains('statusCode')) {
          Log.warning(
              '🖼️ HTTP error loading thumbnail for video ${videoId.substring(0, 8)}, URL: $url',
              name: 'VideoThumbnailWidget',
              category: LogCategory.video);
        }

        return _buildFallback();
      },
    );
  }

  Widget _buildFallback() {
    // Try to use blurhash first
    if (blurhash != null && blurhash!.isNotEmpty) {
      return BlurhashDisplay(
        blurhash: blurhash!,
        width: width,
        height: height,
        fit: fit,
      );
    }
    // Fall back to icon placeholder
    return VideoIconPlaceholder(
      width: width,
      height: height,
      showPlayIcon: showPlayIcon,
      borderRadius: borderRadius?.topLeft.x ?? 8.0,
    );
  }
}
