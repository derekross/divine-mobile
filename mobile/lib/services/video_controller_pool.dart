// ABOUTME: Pool service for managing video controller lifecycle and preventing background playback
// ABOUTME: Keeps controllers initialized in memory but paused, widgets control playback

import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Entry in the controller pool with metadata
class _PoolEntry {
  _PoolEntry({
    required this.controller,
    required this.videoId,
    required this.videoUrl,
  }) : lastUsedTime = DateTime.now();

  final VideoPlayerController controller;
  final String videoId;
  final String videoUrl;
  DateTime lastUsedTime;
  int borrowCount = 0;

  bool get isBorrowed => borrowCount > 0;
  bool get isInitialized => controller.value.isInitialized;

  void touch() {
    lastUsedTime = DateTime.now();
  }
}

/// Pool service for managing video controller lifecycle
///
/// Controllers in the pool are:
/// - Fully initialized and ready to play
/// - Always paused (pool never calls play())
/// - Reference counted to prevent premature disposal
/// - Evicted via LRU when pool is full
///
/// Widgets borrow controllers from pool and control playback.
class VideoControllerPool {
  static final VideoControllerPool _instance = VideoControllerPool._internal();
  factory VideoControllerPool() => _instance;
  VideoControllerPool._internal();

  final Map<String, _PoolEntry> _pool = {};

  /// Maximum number of controllers to keep in pool
  /// Videos are small (~2-10MB), so we can afford to keep more
  static const int maxPoolSize = 20;

  /// Get a controller from the pool, creating if necessary
  ///
  /// Returns null if controller needs initialization (async).
  /// Callers should handle null by creating controller via provider.
  VideoPlayerController? tryBorrowController(String videoId) {
    final entry = _pool[videoId];
    if (entry == null) {
      Log.debug('📦 Controller for ${videoId.substring(0, 8)}... not in pool',
          name: 'VideoControllerPool', category: LogCategory.video);
      return null;
    }

    if (!entry.isInitialized) {
      Log.warning('⚠️ Controller for ${videoId.substring(0, 8)}... in pool but not initialized',
          name: 'VideoControllerPool', category: LogCategory.video);
      return null;
    }

    entry.borrowCount++;
    entry.touch();

    Log.info('📦 Borrowed controller for ${videoId.substring(0, 8)}... (borrowCount=${entry.borrowCount})',
        name: 'VideoControllerPool', category: LogCategory.video);

    return entry.controller;
  }

  /// Return a controller to the pool (must be paused first)
  ///
  /// The controller should be paused by the caller before returning.
  void returnController(String videoId, VideoPlayerController controller) {
    final entry = _pool[videoId];
    if (entry == null) {
      Log.warning('⚠️ Attempted to return controller for ${videoId.substring(0, 8)}... but not in pool',
          name: 'VideoControllerPool', category: LogCategory.video);
      return;
    }

    if (entry.controller != controller) {
      Log.error('❌ Controller mismatch when returning ${videoId.substring(0, 8)}...',
          name: 'VideoControllerPool', category: LogCategory.video);
      return;
    }

    entry.borrowCount = (entry.borrowCount - 1).clamp(0, 999);
    entry.touch();

    Log.info('📦 Returned controller for ${videoId.substring(0, 8)}... (borrowCount=${entry.borrowCount})',
        name: 'VideoControllerPool', category: LogCategory.video);
  }

  /// Add a newly created controller to the pool
  ///
  /// Controller should be initialized before adding to pool.
  /// If pool is full, evicts least recently used controllers.
  Future<void> addController(String videoId, String videoUrl, VideoPlayerController controller) async {
    // Don't add if already in pool
    if (_pool.containsKey(videoId)) {
      Log.debug('📦 Controller for ${videoId.substring(0, 8)}... already in pool',
          name: 'VideoControllerPool', category: LogCategory.video);
      return;
    }

    // Evict excess controllers before adding
    await _evictExcessControllers();

    final entry = _PoolEntry(
      controller: controller,
      videoId: videoId,
      videoUrl: videoUrl,
    );

    _pool[videoId] = entry;

    Log.info('📦 Added controller to pool for ${videoId.substring(0, 8)}... (pool size: ${_pool.length})',
        name: 'VideoControllerPool', category: LogCategory.video);
  }

  /// Evict excess controllers from pool using LRU strategy
  Future<void> _evictExcessControllers() async {
    if (_pool.length < maxPoolSize) return;

    // Find unborrowed controllers sorted by last used time
    final evictionCandidates = _pool.values
        .where((entry) => !entry.isBorrowed)
        .toList()
        ..sort((a, b) => a.lastUsedTime.compareTo(b.lastUsedTime));

    final toEvict = _pool.length - maxPoolSize + 1; // +1 to make room for new entry
    final evicted = <String>[];

    for (var i = 0; i < toEvict && i < evictionCandidates.length; i++) {
      final entry = evictionCandidates[i];

      Log.info('🗑️ Evicting controller for ${entry.videoId.substring(0, 8)}... (LRU)',
          name: 'VideoControllerPool', category: LogCategory.video);

      try {
        await entry.controller.dispose();
      } catch (e) {
        Log.error('❌ Error disposing controller during eviction: $e',
            name: 'VideoControllerPool', category: LogCategory.video);
      }

      _pool.remove(entry.videoId);
      evicted.add(entry.videoId);
    }

    if (evicted.isNotEmpty) {
      Log.info('🗑️ Evicted ${evicted.length} controllers (pool size now: ${_pool.length})',
          name: 'VideoControllerPool', category: LogCategory.video);
    }
  }

  /// Check if a controller exists in pool
  bool hasController(String videoId) {
    return _pool.containsKey(videoId);
  }

  /// Get pool statistics for debugging
  Map<String, dynamic> getStats() {
    final borrowed = _pool.values.where((e) => e.isBorrowed).length;
    final initialized = _pool.values.where((e) => e.isInitialized).length;

    return {
      'totalControllers': _pool.length,
      'borrowed': borrowed,
      'available': _pool.length - borrowed,
      'initialized': initialized,
      'maxPoolSize': maxPoolSize,
    };
  }

  /// Clear all controllers from pool (for testing/cleanup)
  Future<void> clearAll() async {
    Log.info('🧹 Clearing all controllers from pool (${_pool.length})',
        name: 'VideoControllerPool', category: LogCategory.video);

    for (final entry in _pool.values) {
      if (entry.isBorrowed) {
        Log.warning('⚠️ Disposing borrowed controller for ${entry.videoId.substring(0, 8)}...',
            name: 'VideoControllerPool', category: LogCategory.video);
      }

      try {
        await entry.controller.dispose();
      } catch (e) {
        Log.error('❌ Error disposing controller: $e',
            name: 'VideoControllerPool', category: LogCategory.video);
      }
    }

    _pool.clear();
  }
}
