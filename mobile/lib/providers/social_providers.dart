// ABOUTME: Riverpod providers for social service with reactive state management
// ABOUTME: Pure @riverpod functions for social interactions like likes, follows, and reposts

import 'dart:async';

import 'package:nostr_sdk/event.dart';
import 'package:nostr_sdk/filter.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/state/social_state.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'social_providers.g.dart';

/// Social state notifier with reactive state management
@Riverpod(keepAlive: true)
class SocialNotifier extends _$SocialNotifier {
  // Managed subscription IDs
  String? _likeSubscriptionId;
  String? _followSubscriptionId;
  String? _repostSubscriptionId;
  String? _userLikesSubscriptionId;
  String? _userRepostsSubscriptionId;

  @override
  SocialState build() {
    ref.onDispose(_cleanupSubscriptions);

    return SocialState.initial;
  }

  /// Initialize the service
  Future<void> initialize() async {
    if (state.isInitialized) {
      Log.info(
          '🤝 SocialNotifier already initialized with ${state.followingPubkeys.length} following',
          name: 'SocialNotifier',
          category: LogCategory.system);
      return;
    }

    Log.info('🤝 Initializing SocialNotifier',
        name: 'SocialNotifier', category: LogCategory.system);

    state = state.copyWith(isLoading: true);

    try {
      final authService = ref.read(authServiceProvider);

      Log.info(
          '🤝 SocialNotifier: Auth state = ${authService.isAuthenticated}, pubkey = ${authService.currentPublicKeyHex?.substring(0, 8)}',
          name: 'SocialNotifier',
          category: LogCategory.system);

      // Initialize current user's social data if authenticated
      if (authService.isAuthenticated &&
          authService.currentPublicKeyHex != null) {
        Log.info(
            '🤝 SocialNotifier: Fetching contact list for authenticated user',
            name: 'SocialNotifier',
            category: LogCategory.system);
        // Load follow list and user's own reactions in parallel
        await Future.wait([
          fetchCurrentUserFollowList(),
          fetchAllUserReactions(), // Bulk load user's own reactions
        ]);

        Log.info(
            '🤝 SocialNotifier: Contact list fetch complete, following=${state.followingPubkeys.length}, liked=${state.likedEventIds.length}, reposted=${state.repostedEventIds.length}',
            name: 'SocialNotifier',
            category: LogCategory.system);
      } else {
        Log.warning(
            '🤝 SocialNotifier: Skipping contact list fetch - not authenticated',
            name: 'SocialNotifier',
            category: LogCategory.system);
      }

      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        error: null,
      );

      Log.info(
          '✅ SocialNotifier initialized successfully with ${state.followingPubkeys.length} following',
          name: 'SocialNotifier',
          category: LogCategory.system);
    } catch (e) {
      Log.error('❌ SocialNotifier initialization error: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Toggle like on/off for an event
  Future<void> toggleLike(String eventId, String authorPubkey) async {
    final authService = ref.read(authServiceProvider);

    if (!authService.isAuthenticated) {
      Log.error('Cannot like - user not authenticated',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    // Check if operation is already in progress
    if (state.isLikeInProgress(eventId)) {
      Log.debug('Like operation already in progress for $eventId',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    Log.debug('❤️ Toggling like for event: ${eventId.substring(0, 8)}...',
        name: 'SocialNotifier', category: LogCategory.system);

    // Add to in-progress set
    state = state.copyWith(
      likesInProgress: {...state.likesInProgress, eventId},
    );

    try {
      final wasLiked = state.isLiked(eventId);

      if (!wasLiked) {
        // Add like
        final reactionEventId = await _publishLike(eventId, authorPubkey);

        // Update state
        state = state.copyWith(
          likedEventIds: {...state.likedEventIds, eventId},
          likeEventIdToReactionId: {
            ...state.likeEventIdToReactionId,
            eventId: reactionEventId
          },
          likeCounts: {
            ...state.likeCounts,
            eventId: (state.likeCounts[eventId] ?? 0) + 1
          },
        );

        Log.info('Like published for event: ${eventId.substring(0, 8)}...',
            name: 'SocialNotifier', category: LogCategory.system);
      } else {
        // Unlike by publishing NIP-09 deletion event
        final reactionEventId = state.likeEventIdToReactionId[eventId];
        if (reactionEventId != null) {
          await _publishUnlike(reactionEventId);

          // Update state
          final newLikedEventIds = {...state.likedEventIds}..remove(eventId);
          final newLikeEventIdToReactionId = {...state.likeEventIdToReactionId}
            ..remove(eventId);
          final currentCount = state.likeCounts[eventId] ?? 0;

          state = state.copyWith(
            likedEventIds: newLikedEventIds,
            likeEventIdToReactionId: newLikeEventIdToReactionId,
            likeCounts: {
              ...state.likeCounts,
              eventId: currentCount > 0 ? currentCount - 1 : 0
            },
          );

          Log.info(
              'Unlike (deletion) published for event: ${eventId.substring(0, 8)}...',
              name: 'SocialNotifier',
              category: LogCategory.system);
        } else {
          Log.warning('Cannot unlike - reaction event ID not found',
              name: 'SocialNotifier', category: LogCategory.system);

          // Fallback: remove from local state only
          final newLikedEventIds = {...state.likedEventIds}..remove(eventId);
          final currentCount = state.likeCounts[eventId] ?? 0;

          state = state.copyWith(
            likedEventIds: newLikedEventIds,
            likeCounts: {
              ...state.likeCounts,
              eventId: currentCount > 0 ? currentCount - 1 : 0
            },
          );
        }
      }

      // Remove from in-progress set on success
      final newLikesInProgress = {...state.likesInProgress}..remove(eventId);
      state = state.copyWith(likesInProgress: newLikesInProgress);
    } catch (e) {
      Log.error('Error toggling like: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      // Remove from in-progress set before updating error
      final newLikesInProgress = {...state.likesInProgress}..remove(eventId);
      state = state.copyWith(
        error: e.toString(),
        likesInProgress: newLikesInProgress,
      );
      rethrow;
    }
  }

  /// Follow a user
  Future<void> followUser(String pubkeyToFollow) async {
    final authService = ref.read(authServiceProvider);

    if (!authService.isAuthenticated) {
      Log.error('Cannot follow - user not authenticated',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    if (state.isFollowing(pubkeyToFollow)) {
      Log.debug('Already following user: $pubkeyToFollow',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    if (state.isFollowInProgress(pubkeyToFollow)) {
      Log.debug('Follow operation already in progress for $pubkeyToFollow',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    // Add to in-progress set
    state = state.copyWith(
      followsInProgress: {...state.followsInProgress, pubkeyToFollow},
    );

    try {
      final newFollowingList = [...state.followingPubkeys, pubkeyToFollow];

      // Publish updated contact list
      await _publishContactList(newFollowingList);

      // Update state
      state = state.copyWith(followingPubkeys: newFollowingList);

      Log.info('Now following: $pubkeyToFollow',
          name: 'SocialNotifier', category: LogCategory.system);
    } catch (e) {
      Log.error('Error following user: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      state = state.copyWith(error: e.toString());
      rethrow;
    } finally {
      // Remove from in-progress set
      final newFollowsInProgress = {...state.followsInProgress}
        ..remove(pubkeyToFollow);
      state = state.copyWith(followsInProgress: newFollowsInProgress);
    }
  }

  /// Unfollow a user
  Future<void> unfollowUser(String pubkeyToUnfollow) async {
    final authService = ref.read(authServiceProvider);

    if (!authService.isAuthenticated) {
      Log.error('Cannot unfollow - user not authenticated',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    if (!state.isFollowing(pubkeyToUnfollow)) {
      Log.debug('Not following user: $pubkeyToUnfollow',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    if (state.isFollowInProgress(pubkeyToUnfollow)) {
      Log.debug('Follow operation already in progress for $pubkeyToUnfollow',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    // Add to in-progress set
    state = state.copyWith(
      followsInProgress: {...state.followsInProgress, pubkeyToUnfollow},
    );

    try {
      final newFollowingList =
          state.followingPubkeys.where((p) => p != pubkeyToUnfollow).toList();

      // Publish updated contact list
      await _publishContactList(newFollowingList);

      // Update state
      state = state.copyWith(followingPubkeys: newFollowingList);

      Log.info('Unfollowed: $pubkeyToUnfollow',
          name: 'SocialNotifier', category: LogCategory.system);
    } catch (e) {
      Log.error('Error unfollowing user: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      state = state.copyWith(error: e.toString());
      rethrow;
    } finally {
      // Remove from in-progress set
      final newFollowsInProgress = {...state.followsInProgress}
        ..remove(pubkeyToUnfollow);
      state = state.copyWith(followsInProgress: newFollowsInProgress);
    }
  }

  /// Repost an event
  Future<void> repostEvent(Event eventToRepost) async {
    final authService = ref.read(authServiceProvider);

    if (!authService.isAuthenticated) {
      Log.error('Cannot repost - user not authenticated',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    final eventId = eventToRepost.id;

    if (state.hasReposted(eventId)) {
      Log.debug('Already reposted event: $eventId',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    if (state.isRepostInProgress(eventId)) {
      Log.debug('Repost operation already in progress for $eventId',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    // Add to in-progress set
    state = state.copyWith(
      repostsInProgress: {...state.repostsInProgress, eventId},
    );

    try {
      // Publish repost event (Kind 6)
      final repostEventId = await _publishRepost(eventToRepost);

      // Update state
      state = state.copyWith(
        repostedEventIds: {...state.repostedEventIds, eventId},
        repostEventIdToRepostId: {
          ...state.repostEventIdToRepostId,
          eventId: repostEventId
        },
      );

      Log.info('Reposted event: ${eventId.substring(0, 8)}...',
          name: 'SocialNotifier', category: LogCategory.system);
    } catch (e) {
      Log.error('Error reposting event: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      state = state.copyWith(error: e.toString());
      rethrow;
    } finally {
      // Remove from in-progress set
      final newRepostsInProgress = {...state.repostsInProgress}
        ..remove(eventId);
      state = state.copyWith(repostsInProgress: newRepostsInProgress);
    }
  }

  /// Update follower stats for a user
  void updateFollowerStats(String pubkey, Map<String, int> stats) {
    state = state.copyWith(
      followerStats: {...state.followerStats, pubkey: stats},
    );
  }

  /// Update following list (for testing or external updates)
  void updateFollowingList(List<String> followingPubkeys) {
    state = state.copyWith(followingPubkeys: followingPubkeys);
  }

  /// Manually refresh the contact list
  Future<void> refreshContactList() async {
    Log.info('🔄 Manually refreshing contact list',
        name: 'SocialNotifier', category: LogCategory.system);

    state = state.copyWith(isLoading: true);

    try {
      await fetchCurrentUserFollowList();

      state = state.copyWith(
        isLoading: false,
        error: null,
      );

      Log.info(
          '✅ Contact list refresh complete with ${state.followingPubkeys.length} following',
          name: 'SocialNotifier',
          category: LogCategory.system);
    } catch (e) {
      Log.error('❌ Contact list refresh error: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Fetch current user's follow list
  Future<void> fetchCurrentUserFollowList() async {
    final authService = ref.read(authServiceProvider);
    final nostrService = ref.read(nostrServiceProvider);

    if (!authService.isAuthenticated ||
        authService.currentPublicKeyHex == null) {
      Log.warning('Cannot fetch follow list - user not authenticated',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    try {
      Log.info(
          '📋 Fetching current user follow list for: ${authService.currentPublicKeyHex!.substring(0, 8)}...',
          name: 'SocialNotifier',
          category: LogCategory.system);

      // Query for Kind 3 events (contact lists) from current user
      final filter = Filter(
        kinds: const [3],
        authors: [authService.currentPublicKeyHex!],
        limit: 1,
      );

      // Use stream subscription to get events
      final completer = Completer<List<Event>>();
      final events = <Event>[];
      StreamSubscription<Event>? subscription;

      // Set up a timer to complete after getting at least one event or timeout
      Timer? timer;

      void completeAndCleanup() {
        timer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete(events);
        }
      }

      final stream = nostrService.subscribeToEvents(filters: [filter]);
      subscription = stream.listen(
        (event) {
          Log.debug(
              '📋 Received contact list event: ${event.id.substring(0, 8)}...',
              name: 'SocialNotifier',
              category: LogCategory.system);

          // Process contact list event immediately
          _processContactListEvent(event);

          // Add to events list for potential sorting
          events.add(event);

          Log.info(
              '✅ Processed contact list with ${state.followingPubkeys.length} following immediately',
              name: 'SocialNotifier',
              category: LogCategory.system);

          // Complete immediately after processing first contact list event
          completeAndCleanup();
        },
        onDone: () {
          Log.debug(
              '📋 Stream completed - contact list subscription remains open for real-time updates',
              name: 'SocialNotifier',
              category: LogCategory.system);
          // Don't complete here - let timeout handle it if no events received
          if (events.isEmpty) {
            completeAndCleanup();
          }
        },
        onError: (error) {
          Log.error('📋 Stream error: $error',
              name: 'SocialNotifier', category: LogCategory.system);
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      // Set timeout timer
      timer = Timer(const Duration(seconds: 10), () {
        Log.warning(
            '📋 Contact list fetch timeout after 10 seconds with ${events.length} events',
            name: 'SocialNotifier',
            category: LogCategory.system);
        completeAndCleanup();
      });

      // Wait for events
      final fetchedEvents = await completer.future;

      if (fetchedEvents.isNotEmpty) {
        // Get the most recent contact list event
        fetchedEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final latestContactList = fetchedEvents.first;

        _processContactListEvent(latestContactList);

        Log.info(
          'Loaded ${state.followingPubkeys.length} following pubkeys',
          name: 'SocialNotifier',
          category: LogCategory.system,
        );

        // Log first few pubkeys for debugging
        if (state.followingPubkeys.isNotEmpty) {
          final preview = state.followingPubkeys.take(3).join(', ');
          final suffix = state.followingPubkeys.length > 3 ? '...' : '';
          Log.debug(
            'Following pubkeys sample: $preview$suffix',
            name: 'SocialNotifier',
            category: LogCategory.system,
          );
        }
      } else {
        Log.info('No contact list found for current user',
            name: 'SocialNotifier', category: LogCategory.system);
      }
    } catch (e) {
      Log.error('Error fetching follow list: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      state = state.copyWith(error: e.toString());
    }
  }

  /// Fetch all user's reactions and reposts in bulk on startup
  Future<void> fetchAllUserReactions() async {
    final authService = ref.read(authServiceProvider);
    final nostrService = ref.read(nostrServiceProvider);

    if (!authService.isAuthenticated ||
        authService.currentPublicKeyHex == null) {
      return;
    }

    try {
      Log.info('📥 Fetching all user reactions and reposts',
          name: 'SocialNotifier', category: LogCategory.system);

      // Create filters for user's reactions and reposts
      final reactionFilter = Filter(
        kinds: const [7], // reactions
        authors: [authService.currentPublicKeyHex!],
        limit: 500, // Get last 500 reactions
      );

      final repostFilter = Filter(
        kinds: const [6], // reposts  
        authors: [authService.currentPublicKeyHex!],
        limit: 500, // Get last 500 reposts
      );

      // Query for reactions and reposts
      final completer = Completer<void>();
      final reactionEvents = <Event>[];
      final repostEvents = <Event>[];
      
      // Subscribe to both filters
      final stream = nostrService.subscribeToEvents(
        filters: [reactionFilter, repostFilter],
      );
      
      late final StreamSubscription<Event> subscription;
      
      // Set timeout for bulk fetch
      final timer = Timer(const Duration(seconds: 5), () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      subscription = stream.listen(
        (event) {
          if (event.kind == 7) {
            reactionEvents.add(event);
          } else if (event.kind == 6) {
            repostEvents.add(event);
          }
        },
        onDone: () {
          timer.cancel();
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onError: (error) {
          Log.error('Error fetching user reactions: $error',
              name: 'SocialNotifier', category: LogCategory.system);
          timer.cancel();
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await completer.future;

      // Process reactions
      final likedEventIds = <String>{};
      final likeEventIdToReactionId = <String, String>{};
      
      for (final event in reactionEvents) {
        if (event.content == '+') {
          // Find the 'e' tag which references the liked event
          final eTags = event.tags.where((tag) => tag.length >= 2 && tag[0] == 'e');
          if (eTags.isNotEmpty) {
            final likedEventId = eTags.first[1];
            likedEventIds.add(likedEventId);
            likeEventIdToReactionId[likedEventId] = event.id;
          }
        }
      }

      // Process reposts
      final repostedEventIds = <String>{};
      final repostEventIdToRepostId = <String, String>{};
      
      for (final event in repostEvents) {
        // Find the 'e' tag which references the reposted event
        final eTags = event.tags.where((tag) => tag.length >= 2 && tag[0] == 'e');
        if (eTags.isNotEmpty) {
          final repostedEventId = eTags.first[1];
          repostedEventIds.add(repostedEventId);
          repostEventIdToRepostId[repostedEventId] = event.id;
        }
      }

      // Update state with all reactions
      state = state.copyWith(
        likedEventIds: likedEventIds,
        likeEventIdToReactionId: likeEventIdToReactionId,
        repostedEventIds: repostedEventIds,
        repostEventIdToRepostId: repostEventIdToRepostId,
      );

      Log.info(
        '✅ Loaded ${likedEventIds.length} likes and ${repostedEventIds.length} reposts',
        name: 'SocialNotifier',
        category: LogCategory.system,
      );
    } catch (e) {
      Log.error('Error fetching user reactions: $e',
          name: 'SocialNotifier', category: LogCategory.system);
    }
  }

  // Private helper methods

  Future<String> _publishLike(String eventId, String authorPubkey) async {
    try {
      final authService = ref.read(authServiceProvider);
      final nostrService = ref.read(nostrServiceProvider);

      // Create NIP-25 reaction event (Kind 7)
      final event = await authService.createAndSignEvent(
        kind: 7,
        content: '+', // Standard like reaction
        tags: [
          ['e', eventId], // Reference to liked event
          ['p', authorPubkey], // Reference to liked event author
        ],
      );

      if (event == null) {
        throw Exception('Failed to create like event');
      }

      // Broadcast the like event
      final result = await nostrService.broadcastEvent(event);

      if (!result.isSuccessful) {
        final errorMessages = result.errors.values.join(', ');
        throw Exception('Failed to broadcast like event: $errorMessages');
      }

      Log.debug('Like event broadcasted: ${event.id}',
          name: 'SocialNotifier', category: LogCategory.system);
      return event.id;
    } catch (e) {
      Log.error('Error publishing like: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      rethrow;
    }
  }

  Future<void> _publishUnlike(String reactionEventId) async {
    try {
      final authService = ref.read(authServiceProvider);
      final nostrService = ref.read(nostrServiceProvider);

      // Create NIP-09 deletion event (Kind 5)
      final deletionEvent = await authService.createAndSignEvent(
        kind: 5,
        content: 'Deleting like reaction',
        tags: [
          ['e', reactionEventId], // Reference to the reaction event to delete
        ],
      );

      if (deletionEvent == null) {
        throw Exception('Failed to create deletion event');
      }

      // Broadcast the deletion event
      final result = await nostrService.broadcastEvent(deletionEvent);

      if (!result.isSuccessful) {
        final errorMessages = result.errors.values.join(', ');
        throw Exception('Failed to broadcast deletion event: $errorMessages');
      }

      Log.debug('Unlike (deletion) event broadcasted: ${deletionEvent.id}',
          name: 'SocialNotifier', category: LogCategory.system);
    } catch (e) {
      Log.error('Error publishing unlike: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      rethrow;
    }
  }

  Future<void> _publishContactList(List<String> followingPubkeys) async {
    try {
      final authService = ref.read(authServiceProvider);
      final nostrService = ref.read(nostrServiceProvider);

      // Build tags for contact list (NIP-02)
      final tags = followingPubkeys.map((pubkey) => ['p', pubkey]).toList();

      // Create Kind 3 event (contact list)
      final event = await authService.createAndSignEvent(
        kind: 3,
        content: '', // Contact lists typically have empty content
        tags: tags,
      );

      if (event == null) {
        throw Exception('Failed to create contact list event');
      }

      // Broadcast the contact list event
      final result = await nostrService.broadcastEvent(event);

      if (!result.isSuccessful) {
        final errorMessages = result.errors.values.join(', ');
        throw Exception('Failed to broadcast contact list: $errorMessages');
      }

      // Update current contact list event
      state = state.copyWith(currentUserContactListEvent: event);

      Log.debug(
        'Contact list published with ${followingPubkeys.length} contacts',
        name: 'SocialNotifier',
        category: LogCategory.system,
      );
    } catch (e) {
      Log.error('Error publishing contact list: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      rethrow;
    }
  }

  Future<String> _publishRepost(Event eventToRepost) async {
    try {
      final authService = ref.read(authServiceProvider);
      final nostrService = ref.read(nostrServiceProvider);

      // Build tags for repost (NIP-18)
      final tags = <List<String>>[
        ['e', eventToRepost.id, '', 'mention'],
        ['p', eventToRepost.pubkey],
      ];

      // Add original event kind tag if it's a video
      if (eventToRepost.kind == 32222) {
        tags.add(['k', '32222']);
      }

      // Create Kind 6 event (repost)
      final event = await authService.createAndSignEvent(
        kind: 6,
        content: '', // Content is typically empty for reposts
        tags: tags,
      );

      if (event == null) {
        throw Exception('Failed to create repost event');
      }

      // Broadcast the repost event
      final result = await nostrService.broadcastEvent(event);

      if (!result.isSuccessful) {
        final errorMessages = result.errors.values.join(', ');
        throw Exception('Failed to broadcast repost: $errorMessages');
      }

      Log.debug('Repost event broadcasted: ${event.id}',
          name: 'SocialNotifier', category: LogCategory.system);
      return event.id;
    } catch (e) {
      Log.error('Error publishing repost: $e',
          name: 'SocialNotifier', category: LogCategory.system);
      rethrow;
    }
  }

  void _processContactListEvent(Event event) {
    if (event.kind != 3) {
      Log.warning('📋 Received non-contact list event: kind=${event.kind}',
          name: 'SocialNotifier', category: LogCategory.system);
      return;
    }

    Log.info(
        '📋 Processing contact list event: ${event.id.substring(0, 8)}... with ${event.tags.length} tags',
        name: 'SocialNotifier',
        category: LogCategory.system);

    final followingPubkeys = <String>[];

    // Extract pubkeys from 'p' tags
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'p') {
        followingPubkeys.add(tag[1]);
        Log.debug('📋 Found following: ${tag[1].substring(0, 8)}...',
            name: 'SocialNotifier', category: LogCategory.system);
      }
    }

    // Update state
    state = state.copyWith(
      followingPubkeys: followingPubkeys,
      currentUserContactListEvent: event,
    );

    Log.info(
      '✅ Processed contact list with ${followingPubkeys.length} pubkeys',
      name: 'SocialNotifier',
      category: LogCategory.system,
    );

    // Log sample of following list
    if (followingPubkeys.isNotEmpty) {
      final sample =
          followingPubkeys.take(5).map((p) => p.substring(0, 8)).join(', ');
      Log.info(
        '👥 Following sample: $sample${followingPubkeys.length > 5 ? "..." : ""}',
        name: 'SocialNotifier',
        category: LogCategory.system,
      );
    }
  }

  /// Check if current user has liked/reposted a specific video
  /// This replaces the bulk loading approach with per-video queries
  Future<void> checkVideoReactions(String videoId) async {
    final authService = ref.read(authServiceProvider);
    final nostrService = ref.read(nostrServiceProvider);

    if (!authService.isAuthenticated ||
        authService.currentPublicKeyHex == null) {
      return;
    }

    // Skip if we already have this video's reaction state
    if (state.likedEventIds.contains(videoId) ||
        state.repostedEventIds.contains(videoId)) {
      return;
    }

    try {
      Log.debug(
          '🔍 Checking reactions for video: ${videoId.substring(0, 8)}...',
          name: 'SocialNotifier',
          category: LogCategory.system);

      // Query for user's reactions to this specific video
      final reactionFilter = Filter(
        kinds: const [7], // reactions
        authors: [authService.currentPublicKeyHex!],
        e: [videoId], // reactions to this specific video
        limit: 1,
      );

      // Query for user's reposts of this specific video
      final repostFilter = Filter(
        kinds: const [6], // reposts
        authors: [authService.currentPublicKeyHex!],
        e: [videoId], // reposts of this specific video
        limit: 1,
      );

      // Check both reactions and reposts in parallel
      final futures = [
        _queryForSingleReaction(nostrService, reactionFilter, videoId),
        _queryForSingleRepost(nostrService, repostFilter, videoId),
      ];

      await Future.wait(futures);

      Log.debug(
          '✅ Completed reaction check for video: ${videoId.substring(0, 8)}...',
          name: 'SocialNotifier',
          category: LogCategory.system);
    } catch (e) {
      Log.error('Error checking video reactions: $e',
          name: 'SocialNotifier', category: LogCategory.system);
    }
  }

  Future<void> _queryForSingleReaction(
      dynamic nostrService, Filter filter, String videoId) async {
    final completer = Completer<void>();
    final events = <Event>[];

    final stream = nostrService.subscribeToEvents(filters: [filter]);
    late final StreamSubscription<Event> subscription;

    final timer = Timer(const Duration(seconds: 3), () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    subscription = stream.listen(
      (event) {
        // Process reaction immediately when received
        if (event.content == '+') {
          // Found a like for this video - update state immediately
          state = state.copyWith(
            likedEventIds: {...state.likedEventIds, videoId},
            likeEventIdToReactionId: {
              ...state.likeEventIdToReactionId,
              videoId: event.id
            },
          );
          Log.debug(
              'Found existing like for video: ${videoId.substring(0, 8)}... - processed immediately',
              name: 'SocialNotifier',
              category: LogCategory.system);

          // Complete immediately after finding the reaction
          timer.cancel();
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.complete();
          }
        } else {
          // Add to events list for other processing if needed
          events.add(event);
        }
      },
      onDone: () {
        Log.debug(
            'Reaction query stream completed - subscription remains open for real-time updates',
            name: 'SocialNotifier',
            category: LogCategory.system);
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (error) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    await completer.future;
  }

  Future<void> _queryForSingleRepost(
      dynamic nostrService, Filter filter, String videoId) async {
    final completer = Completer<void>();

    final stream = nostrService.subscribeToEvents(filters: [filter]);
    late final StreamSubscription<Event> subscription;

    final timer = Timer(const Duration(seconds: 3), () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    subscription = stream.listen(
      (event) {
        // Process repost immediately when received
        state = state.copyWith(
          repostedEventIds: {...state.repostedEventIds, videoId},
          repostEventIdToRepostId: {
            ...state.repostEventIdToRepostId,
            videoId: event.id
          },
        );
        Log.debug(
            'Found existing repost for video: ${videoId.substring(0, 8)}... - processed immediately',
            name: 'SocialNotifier',
            category: LogCategory.system);

        // Complete immediately after finding the repost
        timer.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onDone: () {
        Log.debug(
            'Repost query stream completed - subscription remains open for real-time updates',
            name: 'SocialNotifier',
            category: LogCategory.system);
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (error) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    await completer.future;
  }

  void _cleanupSubscriptions() {
    try {
      // Only try to clean up if the ref is still valid
      final subscriptionManager = ref.read(subscriptionManagerProvider);

      if (_likeSubscriptionId != null) {
        subscriptionManager.cancelSubscription(_likeSubscriptionId!);
      }
      if (_followSubscriptionId != null) {
        subscriptionManager.cancelSubscription(_followSubscriptionId!);
      }
      if (_repostSubscriptionId != null) {
        subscriptionManager.cancelSubscription(_repostSubscriptionId!);
      }
      if (_userLikesSubscriptionId != null) {
        subscriptionManager.cancelSubscription(_userLikesSubscriptionId!);
      }
      if (_userRepostsSubscriptionId != null) {
        subscriptionManager.cancelSubscription(_userRepostsSubscriptionId!);
      }
    } catch (e) {
      // Container might be disposed, ignore cleanup errors
      Log.debug('Cleanup error during disposal: $e',
          name: 'SocialNotifier', category: LogCategory.system);
    }
  }
}
