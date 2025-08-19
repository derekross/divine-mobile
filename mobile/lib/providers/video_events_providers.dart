// ABOUTME: Riverpod stream provider for managing Nostr video event subscriptions
// ABOUTME: Handles real-time video feed updates for discovery mode

import 'dart:async';

import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'video_events_providers.g.dart';

/// Provider for NostrService instance (Video Events specific)
@riverpod
INostrService videoEventsNostrService(Ref ref) {
  throw UnimplementedError(
      'VideoEventsNostrService must be overridden in ProviderScope');
}

/// Provider for SubscriptionManager instance (Video Events specific)
@riverpod
SubscriptionManager videoEventsSubscriptionManager(
    Ref ref) {
  throw UnimplementedError(
      'VideoEventsSubscriptionManager must be overridden in ProviderScope');
}

/// Stream provider for video events from Nostr
@Riverpod(keepAlive: false)
class VideoEvents extends _$VideoEvents {
  StreamController<List<VideoEvent>>? _controller;

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

    // Only subscribe when Explore tab is active
    if (!isExploreActive) {
      Log.debug('VideoEvents: Explore tab inactive; not subscribing',
          name: 'VideoEventsProvider', category: LogCategory.video);
      // Return an empty broadcast stream to satisfy listeners without background work
      final controller = StreamController<List<VideoEvent>>.broadcast();
      ref.onDispose(() => controller.close());
      return controller.stream;
    }

    // Subscribe to discovery videos for Explore screen (active)
    videoEventService.subscribeToDiscovery(limit: 100);

    // Create a new stream controller
    _controller = StreamController<List<VideoEvent>>.broadcast();
    
    // Emit current events immediately from discovery list
    final currentEvents = List<VideoEvent>.from(videoEventService.discoveryVideos);
    _controller!.add(currentEvents);

    // Listen to VideoEventService changes reactively (proper Riverpod way)
    void onVideoEventServiceChange() {
      final newEvents = List<VideoEvent>.from(videoEventService.discoveryVideos);
      Log.info(
        '📺 VideoEvents: Reactive update - ${newEvents.length} discovery videos',
        name: 'VideoEventsProvider',
        category: LogCategory.video,
      );
      _controller!.add(newEvents);
    }
    
    // Add listener for reactive updates
    videoEventService.addListener(onVideoEventServiceChange);

    // Clean up on dispose
    ref.onDispose(() {
      videoEventService.removeListener(onVideoEventServiceChange);
      _controller?.close();
      // Ensure discovery subscription is torn down when provider is disposed
      videoEventService.unsubscribeFromVideoFeed();
    });

    return _controller!.stream;
  }


  /// Start discovery subscription when Explore tab is visible
  void startDiscoverySubscription() {
    final videoEventService = ref.read(videoEventServiceProvider);
    
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
    await videoEventService.loadMoreEvents(SubscriptionType.discovery, limit: 50);
    
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
bool videoEventsLoading(Ref ref) =>
    ref.watch(videoEventsProvider).isLoading;

/// Provider to get video event count
@riverpod
int videoEventCount(Ref ref) =>
    ref.watch(videoEventsProvider).valueOrNull?.length ?? 0;
