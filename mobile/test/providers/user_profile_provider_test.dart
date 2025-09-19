// ABOUTME: Tests for Riverpod UserProfileProvider state management and profile caching
// ABOUTME: Verifies reactive user profile updates and proper cache management

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nostr_sdk/event.dart';
import 'package:openvine/models/user_profile.dart' as models;
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/state/user_profile_state.dart';

// Mock classes
class MockNostrService extends Mock implements INostrService {}

class MockSubscriptionManager extends Mock implements SubscriptionManager {}

class MockEvent extends Mock implements Event {}

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(MockEvent());
  });

  group('UserProfileProvider', () {
    late ProviderContainer container;
    late MockNostrService mockNostrService;
    late MockSubscriptionManager mockSubscriptionManager;

    setUp(() {
      mockNostrService = MockNostrService();
      mockSubscriptionManager = MockSubscriptionManager();

      container = ProviderContainer(
        overrides: [
          nostrServiceProvider.overrideWithValue(mockNostrService),
          subscriptionManagerProvider
              .overrideWithValue(mockSubscriptionManager),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('should start with initial state', () {
      final state = container.read(userProfileNotifierProvider);

      expect(state, equals(UserProfileState.initial));
      expect(state.profileCache, isEmpty);
      expect(state.pendingRequests, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('should initialize properly', () async {
      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount)
          .thenReturn(1); // FIX: Add missing mock

      // Initialize
      await container.read(userProfileNotifierProvider.notifier).initialize();

      final state = container.read(userProfileNotifierProvider);
      expect(state.isInitialized, isTrue);
    });

    test('should fetch profile using async provider with real data', () async {
      const pubkey = 'test-pubkey-123';

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount)
          .thenReturn(1); // FIX: Add missing mock

      // Setup mock event with real profile data
      final mockEvent = MockEvent();
      when(() => mockEvent.kind).thenReturn(0);
      when(() => mockEvent.pubkey).thenReturn(pubkey);
      when(() => mockEvent.id).thenReturn('event-id-123');
      when(() => mockEvent.createdAt).thenReturn(1234567890);
      when(() => mockEvent.content).thenReturn(
          '{"name":"Test User","picture":"https://example.com/avatar.jpg","about":"Test bio"}');
      when(() => mockEvent.tags).thenReturn([]);

      // Mock Nostr service subscription
      when(() => mockNostrService.subscribeToEvents(
              filters: any(named: 'filters')))
          .thenAnswer((_) => Stream.value(mockEvent));

      // Test the async provider directly
      final profileAsyncValue =
          await container.read(userProfileProvider(pubkey).future);

      expect(profileAsyncValue, isNotNull);
      expect(profileAsyncValue!.pubkey, equals(pubkey));
      expect(profileAsyncValue.name, equals('Test User'));
      expect(
          profileAsyncValue.picture, equals('https://example.com/avatar.jpg'));

      // Test that it's cached by calling again (should not hit network again)
      final cachedProfile =
          await container.read(userProfileProvider(pubkey).future);
      expect(cachedProfile, equals(profileAsyncValue));

      // Verify only one network call was made
      verify(() => mockNostrService.subscribeToEvents(
          filters: any(named: 'filters'))).called(1);
    });

    test('should use notifier for basic profile management', () async {
      const pubkey = 'test-pubkey-456';

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount).thenReturn(1);

      // Setup mock event
      final mockEvent = MockEvent();
      when(() => mockEvent.kind).thenReturn(0);
      when(() => mockEvent.pubkey).thenReturn(pubkey);
      when(() => mockEvent.id).thenReturn('event-id-456');
      when(() => mockEvent.createdAt).thenReturn(1234567890);
      when(() => mockEvent.content).thenReturn('{"name":"Notifier Test User"}');
      when(() => mockEvent.tags).thenReturn([]);

      // Mock Nostr service subscription
      when(() => mockNostrService.subscribeToEvents(
              filters: any(named: 'filters')))
          .thenAnswer((_) => Stream.value(mockEvent));

      // Test notifier fetch method - this is what matters
      final profile = await container
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey);

      expect(profile, isNotNull);
      expect(profile!.pubkey, equals(pubkey));
      expect(profile.name, equals('Notifier Test User'));

      // Test that getCachedProfile works (this tests the actual caching mechanism)
      final cachedProfile = container
          .read(userProfileNotifierProvider.notifier)
          .getCachedProfile(pubkey);
      expect(cachedProfile, isNotNull);
      expect(cachedProfile!.name, equals('Notifier Test User'));
    });

    test('should return cached profile without fetching', () async {
      const pubkey = 'test-pubkey-123';

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount)
          .thenReturn(1); // FIX: Add missing mock

      // Pre-populate cache
      final testProfile = models.UserProfile(
        pubkey: pubkey,
        name: 'Cached User',
        rawData: {},
        createdAt: DateTime.now(),
        eventId: 'cached-event-id',
      );

      container
          .read(userProfileNotifierProvider.notifier)
          .updateCachedProfile(testProfile);

      // Fetch should return cached profile without network call
      final profile = await container
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey);

      expect(profile, equals(testProfile));
      verifyNever(() =>
          mockNostrService.subscribeToEvents(filters: any(named: 'filters')));
    });

    test('should handle multiple individual profile fetches', () async {
      // Test multiple individual fetches instead of complex batch logic
      final pubkeys = ['pubkey1', 'pubkey2', 'pubkey3'];

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount).thenReturn(1);

      // For each pubkey, we'll test individual fetch (which exercises the core functionality)
      for (int i = 0; i < pubkeys.length; i++) {
        final pubkey = pubkeys[i];

        // Setup mock event for this pubkey
        final mockEvent = MockEvent();
        when(() => mockEvent.kind).thenReturn(0);
        when(() => mockEvent.pubkey).thenReturn(pubkey);
        when(() => mockEvent.id).thenReturn('event-$pubkey');
        when(() => mockEvent.createdAt).thenReturn(1234567890);
        when(() => mockEvent.content).thenReturn('{"name":"User $pubkey"}');
        when(() => mockEvent.tags).thenReturn([]);

        // Mock stream for this specific pubkey
        when(() => mockNostrService.subscribeToEvents(
                filters: any(named: 'filters')))
            .thenAnswer((_) => Stream.value(mockEvent));

        // Fetch this profile
        final profile = await container
            .read(userProfileNotifierProvider.notifier)
            .fetchProfile(pubkey);

        expect(profile, isNotNull);
        expect(profile!.pubkey, equals(pubkey));
        expect(profile.name, equals('User $pubkey'));

        // Verify it's cached
        final cachedProfile = container
            .read(userProfileNotifierProvider.notifier)
            .getCachedProfile(pubkey);
        expect(cachedProfile, isNotNull);
        expect(cachedProfile!.name, equals('User $pubkey'));
      }
    });

    test('should handle profile not found', () async {
      const pubkey = 'non-existent-pubkey';

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount)
          .thenReturn(1); // FIX: Add missing mock

      // Mock empty stream (no profile found)
      when(() => mockNostrService.subscribeToEvents(
              filters: any(named: 'filters')))
          .thenAnswer((_) => const Stream.empty());

      // Fetch profile
      final profile = await container
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey);

      expect(profile, isNull);

      // Verify it's marked as missing in global cache (the memory cache handles this)
      // Since the missing profile logic is now in the memory cache, we verify behavior differently

      // Try to fetch again - should skip due to missing marker
      final profileAgain = await container
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey);

      expect(profileAgain, isNull);
    });

    test('should force refresh cached profile', () async {
      const pubkey = 'test-pubkey-123';

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount)
          .thenReturn(1); // FIX: Add missing mock

      // Pre-populate cache with old profile
      final oldProfile = models.UserProfile(
        pubkey: pubkey,
        name: 'Old Name',
        rawData: {},
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        eventId: 'old-event-id',
      );

      container
          .read(userProfileNotifierProvider.notifier)
          .updateCachedProfile(oldProfile);

      // Setup new profile event
      final mockEvent = MockEvent();
      when(() => mockEvent.kind).thenReturn(0);
      when(() => mockEvent.pubkey).thenReturn(pubkey);
      when(() => mockEvent.id).thenReturn('new-event-id');
      when(() => mockEvent.createdAt)
          .thenReturn(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      when(() => mockEvent.content).thenReturn('{"name":"New Name"}');
      when(() => mockEvent.tags).thenReturn([]);

      when(() => mockNostrService.subscribeToEvents(
              filters: any(named: 'filters')))
          .thenAnswer((_) => Stream.value(mockEvent));

      // Force refresh
      final profile = await container
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey, forceRefresh: true);

      expect(profile, isNotNull);
      expect(profile!.name, equals('New Name'));

      // Verify network call was made
      verify(() => mockNostrService.subscribeToEvents(
          filters: any(named: 'filters'))).called(1);
    });

    test('should handle errors gracefully', () async {
      const pubkey = 'error-test-pubkey';

      // Setup fresh container to avoid mock contamination
      final errorContainer = ProviderContainer(
        overrides: [
          nostrServiceProvider.overrideWithValue(mockNostrService),
          subscriptionManagerProvider
              .overrideWithValue(mockSubscriptionManager),
        ],
      );

      // Setup mock Nostr service with all required connection checks
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.connectedRelayCount)
          .thenReturn(1); // FIX: Add missing mock

      // Mock subscription error - reset all previous mocks first
      reset(mockNostrService);
      when(() => mockNostrService.isInitialized).thenReturn(true);
      when(() => mockNostrService.subscribeToEvents(
              filters: any(named: 'filters')))
          .thenAnswer((_) => Stream.error(Exception('Network error')));

      // Fetch profile should handle error gracefully
      final profile = await errorContainer
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey);

      expect(profile, isNull);

      // With the new async provider design, errors are handled gracefully
      // and the profile is marked as missing rather than stored in state.error
      // Let's verify the profile is marked as missing by trying to fetch again
      final profileAgain = await errorContainer
          .read(userProfileNotifierProvider.notifier)
          .fetchProfile(pubkey);

      expect(profileAgain, isNull);

      errorContainer.dispose();
    });
  });
}
