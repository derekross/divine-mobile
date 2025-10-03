// ABOUTME: Riverpod stream provider for managing Nostr video event subscriptions
// ABOUTME: Handles real-time video feed updates for discovery mode

import 'dart:async';

import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/seen_videos_notifier.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'video_events_providers.g.dart';

/// Provider for NostrService instance (Video Events specific)
@riverpod
INostrService videoEventsNostrService(Ref ref) {
  throw UnimplementedError(
      'VideoEventsNostrService must be overridden in ProviderScope');
}

/// Provider for SubscriptionManager instance (Video Events specific)
@riverpod
SubscriptionManager videoEventsSubscriptionManager(Ref ref) {
  throw UnimplementedError(
      'VideoEventsSubscriptionManager must be overridden in ProviderScope');
}

/// Stream provider for video events from Nostr
@Riverpod(keepAlive: false)
class VideoEvents extends _$VideoEvents {
  StreamController<List<VideoEvent>>? _controller;
  Timer? _debounceTimer;
  List<VideoEvent>? _pendingEvents;
  bool get _canEmit => _controller != null && !(_controller!.isClosed);

  @override
  Stream<List<VideoEvent>> build() {
    // Use existing VideoEventService for discovery mode
    final videoEventService = ref.watch(videoEventServiceProvider);
    final isExploreActive = ref.watch(isExploreTabActiveProvider);

    Log.info(
      'VideoEvents: Provider built with reactive listening (${videoEventService.discoveryVideos.length} cached events)',
      name: 'VideoEventsProvider',
      category: LogCategory.video,
    );

    // Always subscribe when provider is watched - disposal handles cleanup
    // Note: On web, IndexedStack pre-renders all tabs, so ExploreScreen widgets
    // are built even when main tab is not active. This is expected behavior.
    Log.debug('VideoEvents: Starting discovery subscription (tab active: $isExploreActive)',
        name: 'VideoEventsProvider', category: LogCategory.video);

    videoEventService.subscribeToDiscovery(limit: 100);

    // Create a new stream controller
    _controller = StreamController<List<VideoEvent>>.broadcast();

    // Emit current events immediately from discovery list
    final currentEvents =
        List<VideoEvent>.from(videoEventService.discoveryVideos);

    Log.info(
      'VideoEvents: Initial emission - ${currentEvents.length} events from service',
      name: 'VideoEventsProvider',
      category: LogCategory.video,
    );

    // Reorder to show unseen videos first
    final seenVideosState = ref.watch(seenVideosProvider);

    final unseen = <VideoEvent>[];
    final seen = <VideoEvent>[];

    for (final video in currentEvents) {
      if (seenVideosState.seenVideoIds.contains(video.id)) {
        seen.add(video);
      } else {
        unseen.add(video);
      }
    }

    final reorderedEvents = [...unseen, ...seen];

    Log.info(
      'VideoEvents: Reordered for emission - ${reorderedEvents.length} total (${unseen.length} unseen, ${seen.length} seen)',
      name: 'VideoEventsProvider',
      category: LogCategory.video,
    );

    // Emit after a microtask to ensure the stream has subscribers
    // This is critical for broadcast streams - synchronous emission before subscription
    // results in data loss when the provider rebuilds
    Future.microtask(() {
      if (_canEmit) {
        _controller!.add(reorderedEvents);
        Log.info(
          'VideoEvents: ✅ Emitted ${reorderedEvents.length} events to stream',
          name: 'VideoEventsProvider',
          category: LogCategory.video,
        );
      } else {
        Log.error(
          'VideoEvents: ❌ Cannot emit - controller unavailable',
          name: 'VideoEventsProvider',
          category: LogCategory.video,
        );
      }
    });

    // Listen to VideoEventService changes reactively (proper Riverpod way)
    void onVideoEventServiceChange() {
      final newEvents =
          List<VideoEvent>.from(videoEventService.discoveryVideos);

      // Reorder to show unseen videos first
      final unseenNew = <VideoEvent>[];
      final seenNew = <VideoEvent>[];

      for (final video in newEvents) {
        if (seenVideosState.seenVideoIds.contains(video.id)) {
          seenNew.add(video);
        } else {
          unseenNew.add(video);
        }
      }

      final reorderedNew = [...unseenNew, ...seenNew];

      // Store pending events for debounced emission
      _pendingEvents = reorderedNew;

      // Cancel any existing timer
      _debounceTimer?.cancel();

      // Create a new debounce timer to batch updates
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (_pendingEvents != null && _canEmit) {
          Log.debug(
            '📺 VideoEvents: Batched update - ${_pendingEvents!.length} discovery videos (${unseenNew.length} unseen, ${seenNew.length} seen)',
            name: 'VideoEventsProvider',
            category: LogCategory.video,
          );
          _controller!.add(_pendingEvents!);
          _pendingEvents = null;
        }
      });
    }

    // Add listener for reactive updates
    videoEventService.addListener(onVideoEventServiceChange);

    // Clean up on dispose
    ref.onDispose(() {
      _debounceTimer?.cancel();
      videoEventService.removeListener(onVideoEventServiceChange);
      // Close and null out the controller to signal no further emits
      _controller?.close();
      _controller = null;
      // Don't unsubscribe - keep the videos cached in the service
      // The service will manage its own lifecycle
    });

    return _controller!.stream;
  }

  /// Start discovery subscription when Explore tab is visible
  void startDiscoverySubscription() {
    final isExploreActive = ref.read(isExploreTabActiveProvider);
    if (!isExploreActive) {
      Log.debug('VideoEvents: Ignoring discovery start; Explore inactive',
          name: 'VideoEventsProvider', category: LogCategory.video);
      return;
    }
    final videoEventService = ref.read(videoEventServiceProvider);
    // Avoid noisy re-requests if already subscribed
    if (videoEventService.isSubscribed(SubscriptionType.discovery)) {
      Log.debug('VideoEvents: Discovery already active; skipping start',
          name: 'VideoEventsProvider', category: LogCategory.video);
      return;
    }

    Log.info(
      'VideoEvents: Starting discovery subscription on demand',
      name: 'VideoEventsProvider',
      category: LogCategory.video,
    );

    // Subscribe to discovery videos using dedicated subscription type
    // NostrService now handles deduplication automatically
    videoEventService.subscribeToDiscovery(limit: 100);
  }

  /// Load more historical events
  Future<void> loadMoreEvents() async {
    final videoEventService = ref.read(videoEventServiceProvider);

    // Delegate to VideoEventService with proper subscription type for discovery
    await videoEventService.loadMoreEvents(SubscriptionType.discovery,
        limit: 50);

    // The periodic timer will automatically pick up the new events
    // and emit them through the stream
  }

  /// Clear all events and refresh
  Future<void> refresh() async {
    final videoEventService = ref.read(videoEventServiceProvider);
    await videoEventService.refreshVideoFeed();
    // The stream will automatically emit the refreshed events
  }
}

/// Provider to check if video events are loading
@riverpod
bool videoEventsLoading(Ref ref) => ref.watch(videoEventsProvider).isLoading;

/// Provider to get video event count
@riverpod
int videoEventCount(Ref ref) {
  final asyncState = ref.watch(videoEventsProvider);
  return asyncState.hasValue ? (asyncState.value?.length ?? 0) : 0;
}
