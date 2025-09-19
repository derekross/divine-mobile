// ABOUTME: Service for handling video-related network operations extracted from VideoEventService
// ABOUTME: Manages subscriptions, event streams, and queries for NIP-32222 kind 32222 video events

import 'dart:async';

import 'package:nostr_sdk/event.dart';
import 'package:nostr_sdk/filter.dart';
import 'package:openvine/exceptions/video_exceptions.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Service responsible for video-related network operations
class VideoNetworkService {
  VideoNetworkService({
    required INostrService nostrService,
    required SubscriptionManager subscriptionManager,
  })  : _nostrService = nostrService,
        _subscriptionManager = subscriptionManager;
  final INostrService _nostrService;
  final SubscriptionManager _subscriptionManager;

  // Stream controllers for events and errors
  final StreamController<VideoEvent> _videoEventController =
      StreamController<VideoEvent>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Subscription tracking
  String? _activeSubscriptionId;
  StreamSubscription<Event>? _eventSubscription;
  Map<String, dynamic> _currentSubscriptionParams = {};
  bool _isSubscribed = false;

  // Public streams
  Stream<VideoEvent> get videoEventStream => _videoEventController.stream;
  Stream<String> get errorStream => _errorController.stream;
  bool get isSubscribed => _isSubscribed;

  /// Subscribe to video feed with various filters
  Future<void> subscribeToVideoFeed({
    List<String>? authors,
    List<String>? hashtags,
    String? group,
    int? since,
    int? until,
    int limit = 50,
    bool includeReposts = false,
  }) async {
    // Check connection
    if (_nostrService.connectedRelayCount == 0) {
      throw ConnectionException('Not connected to any relays');
    }

    // Check for duplicate subscription
    final newParams = {
      'authors': authors,
      'hashtags': hashtags,
      'group': group,
      'since': since,
      'until': until,
      'limit': limit,
      'includeReposts': includeReposts,
    };

    if (_isSubscribed &&
        _parametersMatch(_currentSubscriptionParams, newParams)) {
      throw DuplicateSubscriptionException(
          'Already subscribed with same parameters');
    }

    // Cancel existing subscription if any
    await _cancelExistingSubscription();

    // Build filters
    final filters = <Filter>[];

    // Video events filter (kind 32222)
    final videoFilter = Filter(
      kinds: [32222],
      authors: authors,
      t: hashtags,
      h: group != null ? [group] : null,
      since: since,
      until: until,
      limit: limit,
    );
    filters.add(videoFilter);

    // Repost filter (kind 6) if requested
    if (includeReposts) {
      final repostFilter = Filter(
        kinds: [6],
        authors: authors,
        since: since,
        until: until,
        limit: limit ~/ 2, // Half limit for reposts
      );
      filters.add(repostFilter);
    }

    // Create subscription
    try {
      // Single source of events: use SubscriptionManager only to avoid duplicate listeners
      _activeSubscriptionId = await _subscriptionManager.createSubscription(
        name: 'video_feed',
        filters: filters,
        onEvent: _handleVideoEvent,
        onError: _handleError,
        onComplete: _handleDone,
      );

      _isSubscribed = true;
      _currentSubscriptionParams = newParams;

      Log.info(
        'Subscribed to video feed with ${filters.length} filters',
        name: 'VideoNetworkService',
        category: LogCategory.video,
      );
    } catch (e) {
      Log.error(
        'Failed to subscribe to video feed: $e',
        name: 'VideoNetworkService',
        category: LogCategory.video,
      );
      rethrow;
    }
  }

  /// Unsubscribe from current video feed
  Future<void> unsubscribe() async {
    await _cancelExistingSubscription();
    _isSubscribed = false;
    _currentSubscriptionParams = {};
  }

  /// Query for a specific video by ID
  Future<VideoEvent?> queryVideoByVineId(String vineId) async {
    try {
      final filter = Filter(
        ids: [vineId],
      );

      // Create a completer that resolves immediately when video is found
      final completer = Completer<VideoEvent?>();
      StreamSubscription<Event>? subscription;

      // Set up timeout for cases where video truly doesn't exist
      Timer timeoutTimer = Timer(const Duration(seconds: 5), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          Log.debug('Video query timeout for ID: $vineId',
              name: 'VideoNetworkService', category: LogCategory.video);
          completer.complete(null);
        }
      });

      subscription = _nostrService.subscribeToEvents(
        filters: [filter],
      ).listen(
        (event) {
          // Process matching video immediately when received
          if (event.id == vineId && event.kind == 32222) {
            timeoutTimer.cancel();
            if (!completer.isCompleted) {
              completer.complete(VideoEvent.fromNostrEvent(event));
            }
            // Keep subscription open for potential updates to video metadata
            // Don't cancel here - let the caller manage subscription lifecycle
          }
        },
        onError: (error) {
          Log.error('Error querying video by ID: $error',
              name: 'VideoNetworkService', category: LogCategory.video);
          timeoutTimer.cancel();
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
        onDone: () {
          timeoutTimer.cancel();
          // Only complete with null if we haven't found the video yet
          if (!completer.isCompleted) {
            Log.debug(
                'Video query stream closed without finding video: $vineId',
                name: 'VideoNetworkService',
                category: LogCategory.video);
            completer.complete(null);
          }
        },
      );

      return completer.future;
    } catch (e) {
      Log.error(
        'Failed to query video by ID: $e',
        name: 'VideoNetworkService',
        category: LogCategory.video,
      );
      return null;
    }
  }

  void dispose() {
    _cancelExistingSubscription();
    _videoEventController.close();
    _errorController.close();
  }

  // Private methods

  void _handleVideoEvent(Event event) {
    try {
      if (event.kind == 32222) {
        final videoEvent = VideoEvent.fromNostrEvent(event);
        _videoEventController.add(videoEvent);
      } else if (event.kind == 6) {
        // Handle reposts - extract the original video event
        // This would need more implementation based on repost structure
        Log.debug(
          'Received repost event, processing not yet implemented',
          name: 'VideoNetworkService',
          category: LogCategory.video,
        );
      }
    } catch (e) {
      Log.error(
        'Error processing video event: $e',
        name: 'VideoNetworkService',
        category: LogCategory.video,
      );
    }
  }

  void _handleError(dynamic error) {
    final errorMessage = error.toString();
    _errorController.add(errorMessage);
    Log.error(
      'Subscription error: $errorMessage',
      name: 'VideoNetworkService',
      category: LogCategory.video,
    );
  }

  void _handleDone() {
    Log.debug(
      'Video subscription completed',
      name: 'VideoNetworkService',
      category: LogCategory.video,
    );
  }

  Future<void> _cancelExistingSubscription() async {
    if (_activeSubscriptionId != null) {
      await _subscriptionManager.cancelSubscription(_activeSubscriptionId!);
      _activeSubscriptionId = null;
    }

    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  bool _parametersMatch(
          Map<String, dynamic> params1, Map<String, dynamic> params2) =>
      params1.toString() == params2.toString();
}
