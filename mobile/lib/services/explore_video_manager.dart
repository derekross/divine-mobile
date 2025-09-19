// ABOUTME: Service to provide curated video feeds using the VideoManager pipeline
// ABOUTME: Bridges CurationService with VideoManager for consistent video playback

import 'package:openvine/models/curation_set.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/curation_service.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Service that provides curated video collections
///
/// This provides curated content from CurationService. VideoManager integration
/// is handled at the call site to avoid circular dependencies.
/// FIXED: Removed VideoManager dependency to break circular dependency
class ExploreVideoManager {
  ExploreVideoManager({
    required CurationService curationService,
  })  : _curationService = curationService {
    // Listen to curation service changes
    // REFACTORED: Service no longer extends ChangeNotifier - use Riverpod ref.watch instead

    // Initialize with current content
    _initializeCollections();
  }
  final CurationService _curationService;

  // Current collections available in VideoManager
  final Map<CurationSetType, List<VideoEvent>> _availableCollections = {};
  final Map<CurationSetType, int> _lastVideoCount =
      {}; // Track counts to reduce duplicate logging

  /// Get videos for a specific curation type, ensuring they're in VideoManager
  List<VideoEvent> getVideosForType(CurationSetType type) =>
      _availableCollections[type] ?? [];

  /// Check if videos are loading
  bool get isLoading => _curationService.isLoading;

  /// Get any error
  String? get error => _curationService.error;

  /// Initialize collections by ensuring curated videos are in VideoManager
  Future<void> _initializeCollections() async {
    await _syncAllCollections();
  }

  /// Sync all curation collections to VideoManager
  Future<void> _syncAllCollections() async {
    // Sync each collection and ensure videos are added to VideoManager
    for (final type in CurationSetType.values) {
      await _syncCollectionInternal(type);
    }
  }

  /// Internal sync method that doesn't notify listeners
  Future<void> _syncCollectionInternal(CurationSetType type) async {
    try {
      // Get videos from curation service
      final curatedVideos = _curationService.getVideosForSetType(type);

      // Store videos in our collection
      // NOTE: VideoManager integration is now handled at call sites to avoid circular dependency
      _availableCollections[type] = curatedVideos;

      // Debug: Log what we're getting (reduce spam by only logging on changes)
      if (type == CurationSetType.editorsPicks) {
        final lastCount = _lastVideoCount[type] ?? -1;
        if (lastCount != curatedVideos.length) {
          Log.debug(
              "ExploreVideoManager: Editor's Picks has ${curatedVideos.length} videos",
              name: 'ExploreVideoManager',
              category: LogCategory.system);
          if (curatedVideos.isNotEmpty) {
            final firstVideo = curatedVideos.first;
            Log.debug(
                '  First video: ${firstVideo.title ?? firstVideo.id.substring(0, 8)} from pubkey ${firstVideo.pubkey.substring(0, 8)}',
                name: 'ExploreVideoManager',
                category: LogCategory.system);
          }
          _lastVideoCount[type] = curatedVideos.length;
        }
      }

      Log.verbose('Synced ${curatedVideos.length} videos for ${type.name}',
          name: 'ExploreVideoManager', category: LogCategory.system);
    } catch (e) {
      Log.error('Failed to sync collection ${type.name}: $e',
          name: 'ExploreVideoManager', category: LogCategory.system);
      _availableCollections[type] = [];
    }
  }

  /// Refresh collections from curation service
  Future<void> refreshCollections() async {
    await _curationService.refreshCurationSets();
    // _onCurationChanged will be called automatically
  }

  /// Get videos for preloading for a specific collection
  /// NOTE: Caller must handle VideoManager integration to avoid circular dependency
  List<VideoEvent> getVideosForPreloading(CurationSetType type, {int startIndex = 0}) {
    final videos = _availableCollections[type];
    if (videos == null || videos.isEmpty || startIndex >= videos.length) {
      return [];
    }

    // Calculate preload range around the starting position
    final preloadStart = (startIndex - 2).clamp(0, videos.length - 1);
    final preloadEnd = (startIndex + 3).clamp(0, videos.length);

    final videosToPreload = videos.sublist(preloadStart, preloadEnd);

    Log.debug('⚡ ${type.name} collection preload range: $preloadStart-$preloadEnd (${videosToPreload.length} videos)',
        name: 'ExploreVideoManager', category: LogCategory.system);

    return videosToPreload;
  }

  /// Get total video count across all collections
  int get totalVideoCount {
    return _availableCollections.values.fold(0, (sum, videos) => sum + videos.length);
  }

  void dispose() {
    // REFACTORED: Service no longer needs manual listener cleanup
  }
}
