// ABOUTME: Manages video event subscriptions and real-time feed updates
// ABOUTME: Handles subscription lifecycle, filtering, and event distribution

import 'dart:async';

import 'package:nostr_sdk/event.dart';
import 'package:nostr_sdk/filter.dart';
import 'package:openvine/services/nostr_service_interface.dart';

/// Manages Nostr subscriptions for video events and other content
class SubscriptionManager {
  SubscriptionManager(this._nostrService);

  final INostrService _nostrService;
  final Map<String, StreamSubscription<Event>> _activeSubscriptions = {};
  final Map<String, StreamController<Event>> _controllers = {};

  bool _isDisposed = false;

  /// Creates a new subscription with the given parameters
  Future<String> createSubscription({
    required String name,
    required List<Filter> filters,
    required Function(Event) onEvent,
    Function(dynamic)? onError,
    Function()? onComplete,
    Duration? timeout,
    int priority = 5,
  }) async {
    if (_isDisposed) throw StateError('SubscriptionManager is disposed');

    final id = '${name}_${DateTime.now().millisecondsSinceEpoch}';

    // Create event stream from NostrService
    final eventStream = _nostrService.subscribeToEvents(filters: filters);

    // Set up subscription
    final subscription = eventStream.listen(
      onEvent,
      onError: onError,
      onDone: onComplete,
    );

    _activeSubscriptions[id] = subscription;

    // Handle timeout if specified
    if (timeout != null) {
      Timer(timeout, () {
        if (_activeSubscriptions.containsKey(id)) {
          cancelSubscription(id);
          onComplete?.call();
        }
      });
    }

    return id;
  }

  /// Cancels an active subscription
  Future<void> cancelSubscription(String subscriptionId) async {
    final subscription = _activeSubscriptions.remove(subscriptionId);
    await subscription?.cancel();

    final controller = _controllers.remove(subscriptionId);
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  /// Cancels all active subscriptions
  Future<void> cancelAllSubscriptions() async {
    final subscriptions = List.from(_activeSubscriptions.values);
    _activeSubscriptions.clear();

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }

    final controllers = List.from(_controllers.values);
    _controllers.clear();

    for (final controller in controllers) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// Gets the list of active subscription IDs
  List<String> get activeSubscriptionIds =>
      List.from(_activeSubscriptions.keys);

  /// Gets the count of active subscriptions
  int get activeSubscriptionCount => _activeSubscriptions.length;

  /// Checks if a subscription is active
  bool isSubscriptionActive(String subscriptionId) {
    return _activeSubscriptions.containsKey(subscriptionId);
  }

  /// Cancels all subscriptions that match a name pattern
  Future<void> cancelSubscriptionsByName(String namePattern) async {
    final subscriptionsToCancel = _activeSubscriptions.keys
        .where((id) => id.contains(namePattern))
        .toList();

    for (final subscriptionId in subscriptionsToCancel) {
      await cancelSubscription(subscriptionId);
    }
  }

  /// Disposes the subscription manager and all active subscriptions
  Future<void> dispose() async {
    if (_isDisposed) return;

    await cancelAllSubscriptions();
    _isDisposed = true;
  }
}
