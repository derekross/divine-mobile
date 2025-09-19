// ABOUTME: Service for tracking which videos have been viewed by the user
// ABOUTME: Prevents duplicate videos from appearing in the feed by filtering seen content

import 'dart:async';

import 'package:openvine/utils/unified_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for tracking seen videos to prevent duplicates in feed
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class SeenVideosService {
  static const String _seenVideosKey = 'seen_video_ids';
  static const int _maxSeenVideos =
      1000; // Limit storage to prevent unbounded growth

  final Set<String> _seenVideoIds = {};
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  /// Whether the service has been initialized
  bool get isInitialized => _isInitialized;

  /// Get count of seen videos
  int get seenVideoCount => _seenVideoIds.length;

  /// Initialize the service and load seen videos from storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadSeenVideos();
      _isInitialized = true;

      Log.info(
          '📱️ SeenVideosService initialized with ${_seenVideoIds.length} seen videos',
          name: 'SeenVideosService',
          category: LogCategory.system);
    } catch (e) {
      Log.error('Failed to initialize SeenVideosService: $e',
          name: 'SeenVideosService', category: LogCategory.system);
    }
  }

  /// Load seen videos from persistent storage
  Future<void> _loadSeenVideos() async {
    if (_prefs == null) return;

    try {
      final seenList = _prefs!.getStringList(_seenVideosKey) ?? [];
      _seenVideoIds.clear();
      _seenVideoIds.addAll(seenList);
      Log.debug('📱 Loaded ${_seenVideoIds.length} seen videos from storage',
          name: 'SeenVideosService', category: LogCategory.system);
    } catch (e) {
      Log.error('Error loading seen videos: $e',
          name: 'SeenVideosService', category: LogCategory.system);
    }
  }

  /// Save seen videos to persistent storage
  Future<void> _saveSeenVideos() async {
    if (_prefs == null) return;

    try {
      // Convert to list and limit size if needed
      var videoList = _seenVideoIds.toList();

      // If we exceed max, keep only the most recent
      if (videoList.length > _maxSeenVideos) {
        videoList = videoList.sublist(videoList.length - _maxSeenVideos);
        _seenVideoIds.clear();
        _seenVideoIds.addAll(videoList);
      }

      await _prefs!.setStringList(_seenVideosKey, videoList);
      Log.debug('📱 Saved ${videoList.length} seen videos to storage',
          name: 'SeenVideosService', category: LogCategory.system);
    } catch (e) {
      Log.error('Error saving seen videos: $e',
          name: 'SeenVideosService', category: LogCategory.system);
    }
  }

  /// Check if a video has been seen
  bool hasSeenVideo(String videoId) => _seenVideoIds.contains(videoId);

  /// Mark a video as seen
  Future<void> markVideoAsSeen(String videoId) async {
    if (_seenVideoIds.contains(videoId)) {
      return; // Already seen
    }

    Log.debug('📱️ Marking video as seen: ${videoId.substring(0, 8)}...',
        name: 'SeenVideosService', category: LogCategory.system);
    _seenVideoIds.add(videoId);

    // Save to storage asynchronously
    await _saveSeenVideos();

    // Notify listeners that seen videos have changed
  }

  /// Mark multiple videos as seen (batch operation)
  Future<void> markVideosAsSeen(List<String> videoIds) async {
    var hasChanges = false;

    for (final videoId in videoIds) {
      if (!_seenVideoIds.contains(videoId)) {
        _seenVideoIds.add(videoId);
        hasChanges = true;
      }
    }

    if (hasChanges) {
      await _saveSeenVideos();
    }
  }

  /// Clear all seen videos (for testing or user preference)
  Future<void> clearSeenVideos() async {
    Log.debug('📱️ Clearing all seen videos',
        name: 'SeenVideosService', category: LogCategory.system);
    _seenVideoIds.clear();

    if (_prefs != null) {
      await _prefs!.remove(_seenVideosKey);
    }
  }

  /// Remove a specific video from seen list (mark as unseen)
  Future<void> markVideoAsUnseen(String videoId) async {
    if (!_seenVideoIds.contains(videoId)) {
      return; // Not in seen list
    }

    Log.debug('📱️ Marking video as unseen: ${videoId.substring(0, 8)}...',
        name: 'SeenVideosService', category: LogCategory.system);
    _seenVideoIds.remove(videoId);

    await _saveSeenVideos();
  }

  /// Get statistics about seen videos
  Map<String, dynamic> getStatistics() => {
        'totalSeen': _seenVideoIds.length,
        'storageLimit': _maxSeenVideos,
        'percentageFull':
            (_seenVideoIds.length / _maxSeenVideos * 100).toStringAsFixed(1),
      };

  void dispose() {
    // Save any pending changes before disposing
    _saveSeenVideos();
  }
}
