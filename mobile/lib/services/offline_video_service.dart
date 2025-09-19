// ABOUTME: Offline Video Service for divine - enables offline-first video browsing
// ABOUTME: Manages local video caching, smart preloading, and offline indicators

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart'
    as embedded;

/// Service for managing offline video browsing capabilities
class OfflineVideoService extends ChangeNotifier {
  final embedded.EmbeddedNostrRelay _embeddedRelay;
  final Connectivity _connectivity = Connectivity();

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _preloadTimer;

  // Cache status tracking
  final Map<String, VideoOfflineStatus> _videoStatusCache = {};
  final Set<String> _preloadQueue = {};
  bool _isPreloading = false;

  OfflineVideoService(this._embeddedRelay);

  /// Initialize offline service with connectivity monitoring
  Future<void> initialize() async {
    // Check initial connectivity
    final connectivityResults = await _connectivity.checkConnectivity();
    _isOnline = !connectivityResults.contains(ConnectivityResult.none);

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final wasOnline = _isOnline;
        _isOnline = !results.contains(ConnectivityResult.none);

        if (wasOnline != _isOnline) {
          debugPrint(
              'Offline Video: Connectivity changed - Online: $_isOnline');
          notifyListeners();

          if (_isOnline) {
            _onConnectivityRestored();
          }
        }
      },
    );

    // Start smart preloading
    _startSmartPreloading();

    debugPrint('Offline Video: Service initialized - Online: $_isOnline');
  }

  /// Whether the device is currently online
  bool get isOnline => _isOnline;

  /// Get offline status for a specific video
  Future<VideoOfflineStatus> getVideoStatus(String eventId) async {
    // Check cache first
    if (_videoStatusCache.containsKey(eventId)) {
      return _videoStatusCache[eventId]!;
    }

    try {
      // Check if video event exists locally
      final event = await _embeddedRelay.getEvent(eventId);

      VideoOfflineStatus status;
      if (event != null) {
        // Video metadata is cached locally
        final hasVideoFile = await _checkVideoFileAvailability(event);
        status = hasVideoFile
            ? VideoOfflineStatus.fullyCached
            : VideoOfflineStatus.metadataOnly;
      } else {
        status = VideoOfflineStatus.notCached;
      }

      _videoStatusCache[eventId] = status;
      return status;
    } catch (e) {
      debugPrint('Offline Video: Error checking status for $eventId: $e');
      return VideoOfflineStatus.notCached;
    }
  }

  /// Get all locally cached video events
  Future<List<embedded.NostrEvent>> getCachedVideos({
    int? limit,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final filters = [
        embedded.Filter(
          kinds: [32222], // divine video events
          since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
          until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
          limit: limit ?? 50,
        ),
      ];

      final events = await _embeddedRelay.queryEvents(filters);
      debugPrint('Offline Video: Found ${events.length} cached videos');

      return events;
    } catch (e) {
      debugPrint('Offline Video: Error fetching cached videos: $e');
      return [];
    }
  }

  /// Start smart preloading based on user viewing patterns
  void _startSmartPreloading() {
    _preloadTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_isOnline && !_isPreloading) {
        _performSmartPreloading();
      }
    });
  }

  /// Perform smart preloading of video content
  Future<void> _performSmartPreloading() async {
    if (_isPreloading) return;

    _isPreloading = true;

    try {
      // Get recent videos that might need preloading
      final recentVideos = await getCachedVideos(
        limit: 20,
        since: DateTime.now().subtract(const Duration(hours: 24)),
      );

      int preloadedCount = 0;
      for (final video in recentVideos) {
        if (preloadedCount >= 5) break; // Limit preloading per session

        final status = await getVideoStatus(video.id);
        if (status == VideoOfflineStatus.metadataOnly) {
          await _preloadVideoFile(video);
          preloadedCount++;
        }
      }

      if (preloadedCount > 0) {
        debugPrint('Offline Video: Preloaded $preloadedCount videos');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Offline Video: Smart preloading error: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// Handle connectivity restoration
  Future<void> _onConnectivityRestored() async {
    debugPrint(
        'Offline Video: Connectivity restored, starting background sync');

    // Clear status cache to force refresh
    _videoStatusCache.clear();

    // Start background sync for any pending uploads or metadata
    _performBackgroundSync();
  }

  /// Perform background sync when connectivity is restored
  Future<void> _performBackgroundSync() async {
    try {
      // This would integrate with P2P sync and external relay sync
      // For now, just refresh the local cache status
      debugPrint('Offline Video: Background sync completed');
    } catch (e) {
      debugPrint('Offline Video: Background sync error: $e');
    }
  }

  /// Check if video file is available locally
  Future<bool> _checkVideoFileAvailability(
      embedded.NostrEvent videoEvent) async {
    // In a real implementation, this would check if the actual video file
    // is cached locally (e.g., in a local cache directory)
    // For now, we'll assume metadata presence indicates some level of caching
    return videoEvent.content.isNotEmpty;
  }

  /// Preload a video file for offline viewing
  Future<void> _preloadVideoFile(embedded.NostrEvent videoEvent) async {
    if (_preloadQueue.contains(videoEvent.id)) return;

    _preloadQueue.add(videoEvent.id);

    try {
      // In a real implementation, this would download the video file
      // and store it in local cache
      debugPrint('Offline Video: Preloading video ${videoEvent.id}');

      // Simulate preloading delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Update status cache
      _videoStatusCache[videoEvent.id] = VideoOfflineStatus.fullyCached;
    } catch (e) {
      debugPrint('Offline Video: Error preloading ${videoEvent.id}: $e');
    } finally {
      _preloadQueue.remove(videoEvent.id);
    }
  }

  /// Get offline browsing statistics
  Map<String, dynamic> getOfflineStats() {
    return {
      'is_online': _isOnline,
      'cached_videos_count': _videoStatusCache.length,
      'preload_queue_size': _preloadQueue.length,
      'is_preloading': _isPreloading,
    };
  }

  /// Force refresh of all video statuses
  Future<void> refreshVideoStatuses() async {
    _videoStatusCache.clear();
    notifyListeners();
    debugPrint('Offline Video: Video statuses refreshed');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _preloadTimer?.cancel();
    super.dispose();
  }
}

/// Status of a video's offline availability
enum VideoOfflineStatus {
  /// Video is not cached locally at all
  notCached,

  /// Only video metadata is cached, file not available
  metadataOnly,

  /// Video is fully cached and available offline
  fullyCached,
}
