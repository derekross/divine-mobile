// ABOUTME: VideoManager-compatible provider for VideoOverlayModal integration
// ABOUTME: Bridges VideoOverlayModal's expected interface with working individual video providers

import 'package:flutter_riverpod/legacy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/individual_video_providers.dart';
import 'package:openvine/utils/unified_logger.dart';

part 'video_overlay_manager_provider.g.dart';

/// VideoManager-compatible interface for VideoOverlayModal
/// Provides the same methods that VideoOverlayModal expects from commented TODOs
class VideoOverlayManager {
  VideoOverlayManager(this._ref);

  final Ref _ref;
  final Set<String> _registeredVideos = <String>{};

  /// Add a video event to the manager (VideoOverlayModal expects this method)
  void addVideoEvent(VideoEvent video) {
    if (!_registeredVideos.contains(video.id)) {
      _registeredVideos.add(video.id);
      Log.debug('VideoOverlayManager: Added video ${video.id.substring(0, 8)}... - ${video.title ?? "No title"}',
          name: 'VideoOverlayManager', category: LogCategory.system);
    }
  }

  /// Preload a video by ID (VideoOverlayModal expects this method)
  Future<void> preloadVideo(String videoId) async {
    try {
      // Find video in registered set
      if (!_registeredVideos.contains(videoId)) {
        Log.warning('VideoOverlayManager: Cannot preload unregistered video ${videoId.substring(0, 8)}...',
            name: 'VideoOverlayManager', category: LogCategory.system);
        return;
      }

      // Set as active video to trigger preloading through existing system
      _ref.read(activeVideoProvider.notifier).setActiveVideo(videoId);

      Log.info('VideoOverlayManager: Preloading video ${videoId.substring(0, 8)}...',
          name: 'VideoOverlayManager', category: LogCategory.system);

      // Prewarming will be handled by existing individual video providers
      final currentPrewarm = _ref.read(prewarmManagerProvider);
      _ref.read(prewarmManagerProvider.notifier).setPrewarmed([videoId, ...currentPrewarm], cap: 3);

    } catch (e) {
      Log.error('VideoOverlayManager: Failed to preload video $videoId: $e',
          name: 'VideoOverlayManager', category: LogCategory.system);
    }
  }

  /// Pause all videos (VideoOverlayModal expects this method)
  void pauseAllVideos() {
    try {
      // Clear active video to pause current playback
      _ref.read(activeVideoProvider.notifier).clearActiveVideo();

      Log.info('VideoOverlayManager: Paused all videos',
          name: 'VideoOverlayManager', category: LogCategory.system);
    } catch (e) {
      Log.error('VideoOverlayManager: Failed to pause videos: $e',
          name: 'VideoOverlayManager', category: LogCategory.system);
    }
  }

  /// Force dispose all video controllers (for camera screen, full-screen modals, etc.)
  /// This invalidates ALL video controller providers, forcing them to recreate when needed
  void disposeAllControllers() {
    try {
      // First clear active video to stop playback
      _ref.read(activeVideoProvider.notifier).clearActiveVideo();

      // Invalidate the video controller family to dispose all instances
      // This forces ALL controllers to dispose, even those kept alive by IndexedStack
      _ref.invalidate(individualVideoControllerProvider);

      Log.info('VideoOverlayManager: Disposed all video controllers',
          name: 'VideoOverlayManager', category: LogCategory.system);
    } catch (e) {
      Log.error('VideoOverlayManager: Failed to dispose controllers: $e',
          name: 'VideoOverlayManager', category: LogCategory.system);
    }
  }

  /// Toggle play/pause for specific video (VideoOverlayModal expects this method)
  void togglePlayPause(VideoEvent video) {
    try {
      final currentActive = _ref.read(activeVideoProvider);

      if (currentActive == video.id) {
        // Currently active - pause by clearing
        _ref.read(activeVideoProvider.notifier).clearActiveVideo();
        Log.info('VideoOverlayManager: Paused video ${video.id.substring(0, 8)}...',
            name: 'VideoOverlayManager', category: LogCategory.system);
      } else {
        // Not active - set as active to play
        _ref.read(activeVideoProvider.notifier).setActiveVideo(video.id);
        Log.info('VideoOverlayManager: Playing video ${video.id.substring(0, 8)}...',
            name: 'VideoOverlayManager', category: LogCategory.system);
      }
    } catch (e) {
      Log.error('VideoOverlayManager: Failed to toggle play/pause for ${video.id}: $e',
          name: 'VideoOverlayManager', category: LogCategory.system);
    }
  }

  /// Toggle fullscreen for specific video (VideoOverlayModal expects this method)
  void toggleFullscreen(VideoEvent video) {
    try {
      // Set as active video and let VideoFeedItem handle fullscreen
      _ref.read(activeVideoProvider.notifier).setActiveVideo(video.id);

      Log.info('VideoOverlayManager: Toggled fullscreen for video ${video.id.substring(0, 8)}...',
          name: 'VideoOverlayManager', category: LogCategory.system);
    } catch (e) {
      Log.error('VideoOverlayManager: Failed to toggle fullscreen for ${video.id}: $e',
          name: 'VideoOverlayManager', category: LogCategory.system);
    }
  }

  /// Set active video for page changes (VideoOverlayModal needs this)
  void setActiveVideo(String videoId) {
    _ref.read(activeVideoProvider.notifier).setActiveVideo(videoId);
  }

  /// Clear active video when modal closes (VideoOverlayModal needs this)
  void clearActiveVideo() {
    _ref.read(activeVideoProvider.notifier).clearActiveVideo();
  }

  /// Get list of registered video IDs
  Set<String> get registeredVideos => Set.unmodifiable(_registeredVideos);

  /// Get currently active video ID
  String? get activeVideoId => _ref.read(activeVideoProvider);
}

/// Provider for VideoOverlayManager that VideoOverlayModal can use
/// This replaces the missing videoManagerProvider referenced in TODO comments
@riverpod
VideoOverlayManager videoOverlayManager(Ref ref) {
  return VideoOverlayManager(ref);
}

/// Backwards compatibility alias for VideoOverlayModal TODO restoration
/// This allows VideoOverlayModal to use `videoManagerProvider.notifier`
final videoManagerProvider = StateNotifierProvider<_VideoManagerNotifier, void>((ref) {
  return _VideoManagerNotifier(ref);
});

class _VideoManagerNotifier extends StateNotifier<void> {
  _VideoManagerNotifier(this._ref) : super(null);

  final Ref _ref;
  late final VideoOverlayManager _manager = _ref.read(videoOverlayManagerProvider);

  /// Provide VideoOverlayManager interface through .notifier
  VideoOverlayManager get notifier => _manager;

  // Delegate all VideoManager methods to VideoOverlayManager
  void addVideoEvent(VideoEvent video) => _manager.addVideoEvent(video);
  Future<void> preloadVideo(String videoId) => _manager.preloadVideo(videoId);
  void pauseAllVideos() => _manager.pauseAllVideos();
  void togglePlayPause(VideoEvent video) => _manager.togglePlayPause(video);
  void toggleFullscreen(VideoEvent video) => _manager.toggleFullscreen(video);
  void setActiveVideo(String videoId) => _manager.setActiveVideo(videoId);
  void clearActiveVideo() => _manager.clearActiveVideo();
}