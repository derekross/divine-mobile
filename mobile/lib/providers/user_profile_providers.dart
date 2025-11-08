// ABOUTME: Riverpod providers for user profile service with reactive state management
// ABOUTME: Pure @riverpod functions for user profile management and caching

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openvine/models/user_profile.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/state/user_profile_state.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';

part 'user_profile_providers.g.dart';

// Helper function for safe pubkey truncation in logs
String _safePubkeyTrunc(String pubkey) =>
    pubkey.length > 8 ? pubkey : pubkey;

// Cache for user profiles
final Map<String, UserProfile> _userProfileCache = {};
final Map<String, DateTime> _userProfileCacheTimestamps = {};
final Set<String> _knownMissingProfiles = {};
final Map<String, DateTime> _missingProfileRetryAfter = {};
const Duration _userProfileCacheExpiry = Duration(minutes: 10);

/// Get cached profile if available and not expired
UserProfile? _getCachedUserProfile(String pubkey) {
  final profile = _userProfileCache[pubkey];
  final timestamp = _userProfileCacheTimestamps[pubkey];

  if (profile != null && timestamp != null) {
    final age = DateTime.now().difference(timestamp);
    if (age < _userProfileCacheExpiry) {
      Log.debug(
          '👤 Using cached profile for ${_safePubkeyTrunc(pubkey)} (age: ${age.inMinutes}min)',
          name: 'UserProfileProvider',
          category: LogCategory.ui);
      return profile;
    } else {
      Log.debug(
          '⏰ Profile cache expired for ${_safePubkeyTrunc(pubkey)} (age: ${age.inMinutes}min)',
          name: 'UserProfileProvider',
          category: LogCategory.ui);
      _clearUserProfileCache(pubkey);
    }
  }

  return null;
}

/// Cache profile for a user
void _cacheUserProfile(String pubkey, UserProfile profile) {
  _userProfileCache[pubkey] = profile;
  _userProfileCacheTimestamps[pubkey] = DateTime.now();
  Log.debug(
      '👤 Cached profile for ${_safePubkeyTrunc(pubkey)}: ${profile.bestDisplayName}',
      name: 'UserProfileProvider',
      category: LogCategory.ui);
}

/// Clear cache for a specific user
void _clearUserProfileCache(String pubkey) {
  _userProfileCache.remove(pubkey);
  _userProfileCacheTimestamps.remove(pubkey);
}

/// Mark a profile as missing to avoid spam
void _markProfileAsMissing(String pubkey) {
  final retryAfter = DateTime.now().add(const Duration(minutes: 10));
  _knownMissingProfiles.add(pubkey);
  _missingProfileRetryAfter[pubkey] = retryAfter;

  Log.debug(
    'Marked profile as missing: ${_safePubkeyTrunc(pubkey)}... (retry after 10 minutes)',
    name: 'UserProfileProvider',
    category: LogCategory.ui,
  );
}

/// Check if we should skip fetching (known missing)
bool _shouldSkipFetch(String pubkey) {
  if (!_knownMissingProfiles.contains(pubkey)) return false;

  final retryAfter = _missingProfileRetryAfter[pubkey];
  if (retryAfter == null) return false;

  return DateTime.now().isBefore(retryAfter);
}

/// Async provider for loading a single user profile
@riverpod
Future<UserProfile?> fetchUserProfile(Ref ref, String pubkey) async {
  // Check module-level cache first
  final cached = _getCachedUserProfile(pubkey);
  if (cached != null) {
    return cached;
  }

  // Check UserProfileService cache (profiles fetched by VideoEventService end up here)
  final userProfileService = ref.watch(userProfileServiceProvider);
  final serviceCached = userProfileService.getCachedProfile(pubkey);
  if (serviceCached != null) {
    // Sync to module-level cache for faster future access
    _cacheUserProfile(pubkey, serviceCached);
    Log.debug(
      '✅ Found profile in service cache: ${serviceCached.bestDisplayName}',
      name: 'UserProfileProvider',
      category: LogCategory.ui,
    );
    return serviceCached;
  }

  // Check if should skip (known missing)
  if (_shouldSkipFetch(pubkey)) {
    Log.debug(
      'Skipping fetch for known missing profile: ${_safePubkeyTrunc(pubkey)}...',
      name: 'UserProfileProvider',
      category: LogCategory.ui,
    );
    return null;
  }

  Log.debug('🔍 Loading profile for: ${_safePubkeyTrunc(pubkey)}...',
      name: 'UserProfileProvider', category: LogCategory.ui);

  try {
    // Use UserProfileService for proper profile fetching
    final profile = await userProfileService.fetchProfile(pubkey);

    if (profile != null) {
      // Cache the profile
      _cacheUserProfile(pubkey, profile);

      Log.info(
        '✅ Fetched profile for ${_safePubkeyTrunc(pubkey)}: ${profile.bestDisplayName}',
        name: 'UserProfileProvider',
        category: LogCategory.ui,
      );
    } else {
      // If no profile found, mark as missing
      _markProfileAsMissing(pubkey);
    }

    return profile;
  } catch (e) {
    Log.error('Error loading profile: $e',
        name: 'UserProfileProvider', category: LogCategory.ui);
    _markProfileAsMissing(pubkey);
    return null;
  }
}

// User profile state notifier with reactive state management
@riverpod
class UserProfileNotifier extends _$UserProfileNotifier {
  // UserProfileService handles all subscription management
  Timer? _batchDebounceTimer;

  @override
  UserProfileState build() {
    // Keep this provider alive to avoid repeated init/dispose thrash when accessed via ref.read
    // (AutoDispose is default for @riverpod; keep it alive explicitly.)
    // This prevents log spam like "User profile notifier initialized" on every rebuild.
    // ignore: unused_local_variable
    final keepAliveLink = ref.keepAlive();
    ref.onDispose(() {
      _cleanupAllSubscriptions();
      _batchDebounceTimer?.cancel();
    });

    return UserProfileState.initial;
  }

  /// Initialize the profile service
  Future<void> initialize() async {
    if (state.isInitialized) return;

    Log.verbose('Initializing user profile notifier...',
        name: 'UserProfileNotifier', category: LogCategory.system);

    final nostrService = ref.read(nostrServiceProvider);

    if (!nostrService.isInitialized) {
      Log.warning('Nostr service not initialized, profile notifier will wait',
          name: 'UserProfileNotifier', category: LogCategory.system);
      return;
    }

    state = state.copyWith(isInitialized: true);
    Log.info('User profile notifier initialized',
        name: 'UserProfileNotifier', category: LogCategory.system);
  }

  /// Get cached profile for a user
  UserProfile? getCachedProfile(String pubkey) {
    // Check memory cache first
    final cached = _getCachedUserProfile(pubkey);
    if (cached != null) return cached;

    // Check state cache
    return state.getCachedProfile(pubkey);
  }

  /// Update a cached profile
  void updateCachedProfile(UserProfile profile) {
    // Update both memory cache and state
    _cacheUserProfile(profile.pubkey, profile);

    final newCache = {...state.profileCache, profile.pubkey: profile};
    state = state.copyWith(
      profileCache: newCache,
      totalProfilesCached: newCache.length,
    );

    Log.debug(
      'Updated cached profile for ${_safePubkeyTrunc(profile.pubkey)}: ${profile.bestDisplayName}',
      name: 'UserProfileNotifier',
      category: LogCategory.system,
    );
  }

  /// Fetch profile for a specific user (uses async provider under the hood)
  Future<UserProfile?> fetchProfile(String pubkey,
      {bool forceRefresh = false}) async {
    if (!state.isInitialized) {
      await initialize();
    }

    // If forcing refresh, clear cache first
    if (forceRefresh) {
      Log.debug(
        '🔄 Force refresh requested for ${_safePubkeyTrunc(pubkey)}... - clearing cache',
        name: 'UserProfileNotifier',
        category: LogCategory.system,
      );

      _clearUserProfileCache(pubkey);
      ref.invalidate(fetchUserProfileProvider(pubkey));

      final newCache = Map<String, UserProfile>.from(state.profileCache)..remove(pubkey);
      state = state.copyWith(profileCache: newCache);

      // Cancel any existing subscriptions
      await _cleanupProfileRequest(pubkey);
    }

    // Check if already requesting
    if (state.isRequestPending(pubkey)) {
      Log.warning(
        '⏳ Profile request already pending for ${_safePubkeyTrunc(pubkey)}...',
        name: 'UserProfileNotifier',
        category: LogCategory.system,
      );
      return null;
    }

    try {
      // Mark as pending
      state = state.copyWith(
        pendingRequests: {...state.pendingRequests, pubkey},
        isLoading: true,
        totalProfilesRequested: state.totalProfilesRequested + 1,
      );

      // Use the async provider to fetch profile
      final profile = await ref.read(fetchUserProfileProvider(pubkey).future);

      if (profile != null) {
        // Update state cache
        final newCache = Map<String, UserProfile>.from(state.profileCache);
        newCache[pubkey] = profile;
        state = state.copyWith(
          profileCache: newCache,
          totalProfilesCached: newCache.length,
        );
      }

      return profile;
    } finally {
      // Remove from pending
      final newPending = {...state.pendingRequests}..remove(pubkey);
      state = state.copyWith(
        pendingRequests: newPending,
        isLoading: newPending.isEmpty && state.pendingBatchPubkeys.isEmpty,
      );
    }
  }

  /// Sync a profile from UserProfileService cache into notifier state
  /// Used when VideoEventService fetches profiles but doesn't update notifier
  void syncProfileFromService(String pubkey, UserProfile profile) {
    if (state.hasProfile(pubkey)) {
      return; // Already in cache
    }

    // Update state cache
    final newCache = Map<String, UserProfile>.from(state.profileCache);
    newCache[pubkey] = profile;
    state = state.copyWith(
      profileCache: newCache,
      totalProfilesCached: newCache.length,
    );

    // Also update module-level cache
    _cacheUserProfile(pubkey, profile);

    Log.debug(
      '🔄 Synced profile from service cache: ${profile.bestDisplayName}',
      name: 'UserProfileNotifier',
      category: LogCategory.ui,
    );
  }

  /// Aggressively pre-fetch profiles for immediate display (no debouncing)
  Future<void> prefetchProfilesImmediately(List<String> pubkeys) async {
    // Only prefetch when a relevant UI tab is active to avoid background churn
    final isFeedActive = ref.read(isFeedTabActiveProvider);
    final isExploreActive = ref.read(isExploreTabActiveProvider);
    final isProfileActive = ref.read(isProfileTabActiveProvider);
    if (!(isFeedActive || isExploreActive || isProfileActive)) {
      Log.info(
          '🚫 Prefetch suppressed: Feed=$isFeedActive, Explore=$isExploreActive, Profile=$isProfileActive',
          name: 'UserProfileNotifier',
          category: LogCategory.system);
      return;
    }

    Log.info(
        '✅ Prefetch allowed: Feed=$isFeedActive, Explore=$isExploreActive, Profile=$isProfileActive',
        name: 'UserProfileNotifier',
        category: LogCategory.system);

    if (!state.isInitialized) {
      await initialize();
    }

    // Filter out already cached profiles and known missing profiles
    final pubkeysToFetch = pubkeys
        .where((p) => !state.hasProfile(p) && !_shouldSkipFetch(p))
        .toList();

    if (pubkeysToFetch.isEmpty) {
      Log.debug('All requested profiles already cached or known missing',
          name: 'UserProfileNotifier', category: LogCategory.system);
      return;
    }

    Log.debug('⚡ Immediate pre-fetch for ${pubkeysToFetch.length} profiles',
        name: 'UserProfileNotifier', category: LogCategory.system);

    try {
      // Use UserProfileService for immediate batch requests
      final userProfileService = ref.read(userProfileServiceProvider);

      // Prefetch profiles using UserProfileService
      await userProfileService.prefetchProfilesImmediately(pubkeysToFetch);

      // Get profiles from cache after prefetch
      final fetchedPubkeys = <String>{};
      for (final pubkey in pubkeysToFetch) {
        final profile = userProfileService.getCachedProfile(pubkey);

        if (profile != null) {
          fetchedPubkeys.add(pubkey);

          // Update both memory cache and state cache
          _cacheUserProfile(pubkey, profile);

          final newCache = Map<String, UserProfile>.from(state.profileCache);
          newCache[pubkey] = profile;
          state = state.copyWith(
            profileCache: newCache,
            totalProfilesCached: newCache.length,
          );

          Log.debug(
            '⚡ Prefetched profile: ${profile.bestDisplayName}',
            name: 'UserProfileNotifier',
            category: LogCategory.system,
          );
        }
      }

      // Mark unfetched profiles as missing
      for (final pubkey in pubkeysToFetch) {
        if (!fetchedPubkeys.contains(pubkey)) {
          markProfileAsMissing(pubkey);
        }
      }

      Log.debug(
          '⚡ Prefetch completed: ${fetchedPubkeys.length}/${pubkeysToFetch.length} profiles fetched',
          name: 'UserProfileNotifier',
          category: LogCategory.system);
    } catch (e) {
      Log.error('Error in prefetch: $e',
          name: 'UserProfileNotifier', category: LogCategory.system);
    }
  }

  /// Fetch multiple profiles with batching
  Future<void> fetchMultipleProfiles(List<String> pubkeys,
      {bool forceRefresh = false}) async {
    if (!state.isInitialized) {
      await initialize();
    }

    // Filter out already cached profiles (unless forcing refresh)
    final pubkeysToFetch = forceRefresh
        ? pubkeys
        : pubkeys
            .where((p) => !state.hasProfile(p) && !_shouldSkipFetch(p))
            .toList();

    if (pubkeysToFetch.isEmpty) {
      Log.debug('All requested profiles already cached',
          name: 'UserProfileNotifier', category: LogCategory.system);
      return;
    }

    Log.info('📋 Batch fetching ${pubkeysToFetch.length} profiles',
        name: 'UserProfileNotifier', category: LogCategory.system);

    // Add to pending batch
    state = state.copyWith(
      pendingBatchPubkeys: {...state.pendingBatchPubkeys, ...pubkeysToFetch},
      isLoading: true,
    );

    // Debounce batch execution (reduced delay for faster UI)
    _batchDebounceTimer?.cancel();
    _batchDebounceTimer =
        Timer(const Duration(milliseconds: 50), executeBatchFetch);
  }

  /// Mark a profile as missing to avoid spam
  void markProfileAsMissing(String pubkey) {
    // Update memory cache
    _markProfileAsMissing(pubkey);

    // Update state
    final retryAfter = DateTime.now().add(const Duration(minutes: 10));
    state = state.copyWith(
      knownMissingProfiles: {...state.knownMissingProfiles, pubkey},
      missingProfileRetryAfter: {
        ...state.missingProfileRetryAfter,
        pubkey: retryAfter
      },
    );

    Log.debug(
      'Marked profile as missing: ${_safePubkeyTrunc(pubkey)}... (retry after 10 minutes)',
      name: 'UserProfileNotifier',
      category: LogCategory.system,
    );
  }

  // Private helper methods

  // Made package-private for testing
  @visibleForTesting
  Future<void> executeBatchFetch() async {
    if (state.pendingBatchPubkeys.isEmpty) return;

    final pubkeysToFetch = state.pendingBatchPubkeys.toList();
    Log.debug(
      '_executeBatchFetch called with ${pubkeysToFetch.length} pubkeys',
      name: 'UserProfileNotifier',
      category: LogCategory.system,
    );

    try {
      // Use UserProfileService for batch requests instead of individual subscriptions
      final userProfileService = ref.read(userProfileServiceProvider);

      Log.debug(
        'Using UserProfileService for batch fetch...',
        name: 'UserProfileNotifier',
        category: LogCategory.system,
      );

      // Prefetch profiles using UserProfileService
      await userProfileService.prefetchProfilesImmediately(pubkeysToFetch);

      // Get profiles from cache after prefetch
      final fetchedPubkeys = <String>{};
      for (final pubkey in pubkeysToFetch) {
        final profile = userProfileService.getCachedProfile(pubkey);

        if (profile != null) {
          fetchedPubkeys.add(pubkey);

          // Update both memory cache and state cache
          _cacheUserProfile(pubkey, profile);

          final newCache = Map<String, UserProfile>.from(state.profileCache);
          newCache[pubkey] = profile;
          state = state.copyWith(
            profileCache: newCache,
            totalProfilesCached: newCache.length,
          );

          Log.debug(
            'Batch fetched profile: ${profile.bestDisplayName}',
            name: 'UserProfileNotifier',
            category: LogCategory.system,
          );
        }
      }

      // Finalize the batch
      _finalizeBatchFetch(pubkeysToFetch, fetchedPubkeys);
    } catch (e) {
      Log.error('Error executing batch fetch: $e',
          name: 'UserProfileNotifier', category: LogCategory.system);
      state = state.copyWith(
        pendingBatchPubkeys: {},
        isLoading: state.pendingRequests.isEmpty,
        error: e.toString(),
      );
    }
  }

  void _finalizeBatchFetch(List<String> requested, Set<String> fetched) {
    // Mark unfetched profiles as missing
    for (final pubkey in requested) {
      if (!fetched.contains(pubkey)) {
        markProfileAsMissing(pubkey);
      }
    }

    // Clear batch state
    state = state.copyWith(
      pendingBatchPubkeys: {},
      isLoading: state.pendingRequests.isNotEmpty,
    );

    Log.info(
      'Batch fetch complete: ${fetched.length}/${requested.length} profiles fetched',
      name: 'UserProfileNotifier',
      category: LogCategory.system,
    );
  }

  Future<void> _cleanupProfileRequest(String pubkey) async {
    // No longer needed - UserProfileService handles cleanup internally
    Log.debug(
        'Profile request cleanup no longer needed for: ${_safePubkeyTrunc(pubkey)}',
        name: 'UserProfileNotifier',
        category: LogCategory.system);
  }

  void _cleanupAllSubscriptions() {
    // UserProfileService handles all subscription cleanup automatically
    // No manual cleanup needed here
    Log.debug('Subscription cleanup delegated to UserProfileService',
        name: 'UserProfileNotifier', category: LogCategory.system);
  }

  /// Check if we have a cached profile
  bool hasProfile(String pubkey) => state.hasProfile(pubkey);
}
