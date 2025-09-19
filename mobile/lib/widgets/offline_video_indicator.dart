// ABOUTME: Offline Video Indicator Widget - shows offline status of videos
// ABOUTME: Visual indicator for cached/uncached videos and connectivity status

import 'package:flutter/material.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/services/offline_video_service.dart';

/// Widget that displays the offline status of a video
class OfflineVideoIndicator extends StatelessWidget {
  final String eventId;
  final OfflineVideoService offlineService;
  final bool showLabel;
  final double size;

  const OfflineVideoIndicator({
    super.key,
    required this.eventId,
    required this.offlineService,
    this.showLabel = false,
    this.size = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoOfflineStatus>(
      future: offlineService.getVideoStatus(eventId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final status = snapshot.data!;
        final (icon, color, label) = _getStatusDisplay(context, status);

        if (showLabel) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: size, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.75,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        }

        return Icon(icon, size: size, color: color);
      },
    );
  }

  (IconData, Color, String) _getStatusDisplay(
    BuildContext context,
    VideoOfflineStatus status,
  ) {
    switch (status) {
      case VideoOfflineStatus.fullyCached:
        return (Icons.offline_pin, VineTheme.vineGreen, 'Cached');
      case VideoOfflineStatus.metadataOnly:
        return (
          Icons.cloud_download_outlined,
          Theme.of(context).colorScheme.primary,
          'Partial'
        );
      case VideoOfflineStatus.notCached:
        return (
          Icons.cloud_outlined,
          Theme.of(context).colorScheme.onSurfaceVariant,
          'Online'
        );
    }
  }
}

/// Widget that shows overall connectivity status
class ConnectivityIndicator extends StatelessWidget {
  final OfflineVideoService offlineService;
  final bool showLabel;

  const ConnectivityIndicator({
    super.key,
    required this.offlineService,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: offlineService,
      builder: (context, child) {
        final isOnline = offlineService.isOnline;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isOnline
                ? VineTheme.vineGreen.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnline ? Icons.wifi : Icons.wifi_off,
                size: 16,
                color: isOnline ? VineTheme.vineGreen : Colors.orange,
              ),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isOnline ? VineTheme.vineGreen : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Widget for displaying video cache statistics
class VideoCacheStats extends StatelessWidget {
  final OfflineVideoService offlineService;

  const VideoCacheStats({
    super.key,
    required this.offlineService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: offlineService,
      builder: (context, child) {
        final stats = offlineService.getOfflineStats();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline Video Cache',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildStatRow(
                  context,
                  'Connection',
                  stats['is_online'] ? 'Online' : 'Offline',
                  stats['is_online'] ? Icons.wifi : Icons.wifi_off,
                  stats['is_online'] ? VineTheme.vineGreen : Colors.orange,
                ),
                _buildStatRow(
                  context,
                  'Cached Videos',
                  '${stats['cached_videos_count']}',
                  Icons.video_library,
                  Theme.of(context).colorScheme.primary,
                ),
                if (stats['is_preloading']) ...[
                  _buildStatRow(
                    context,
                    'Preloading',
                    '${stats['preload_queue_size']} videos',
                    Icons.download,
                    Theme.of(context).colorScheme.secondary,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
