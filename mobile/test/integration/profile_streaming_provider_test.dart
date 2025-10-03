// ABOUTME: Integration tests for profile streaming providers using real Nostr relay
// ABOUTME: Tests cache-first behavior, reactive updates, and real event propagation

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:openvine/models/user_profile.dart' as models;
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/nostr_service.dart';
import 'package:openvine/services/profile_cache_service.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:path/path.dart' as path;

void main() {
  // Use shared test directory for all tests
  late Directory testDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Create test directory
    testDir = await Directory.systemTemp.createTemp('openvine_test_');

    // Initialize Hive with test directory
    Hive.init(testDir.path);

    // Mock flutter_secure_storage channel
    const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final Map<String, String> secureStorage = {};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'read':
          final String? key = methodCall.arguments['key'];
          return secureStorage[key];
        case 'write':
          final String? key = methodCall.arguments['key'];
          final String? value = methodCall.arguments['value'];
          if (key != null && value != null) {
            secureStorage[key] = value;
          }
          return null;
        case 'delete':
          final String? key = methodCall.arguments['key'];
          if (key != null) {
            secureStorage.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStorage.clear();
          return null;
        default:
          return null;
      }
    });

    // Mock path_provider channel
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getApplicationDocumentsDirectory':
          return testDir.path;
        case 'getTemporaryDirectory':
          return testDir.path;
        case 'getApplicationSupportDirectory':
          return testDir.path;
        default:
          return testDir.path;
      }
    });

    // Mock openvine.secure_storage capability channel
    const capabilityChannel = MethodChannel('openvine.secure_storage');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capabilityChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'getCapabilities') {
        return {
          'hasHardwareSecurity': false,
          'hasBiometrics': false,
          'hasKeychain': true,
        };
      }
      return null;
    });
  });

  tearDownAll(() async {
    // Cleanup test directory
    if (testDir.existsSync()) {
      await testDir.delete(recursive: true);
    }
  });

  group('Profile Streaming Provider Integration Tests', () {
    late NostrService nostrService;
    late AuthService authService;
    late NostrKeyManager keyManager;
    late SubscriptionManager subscriptionManager;
    late ProfileCacheService profileCache;
    late ProviderContainer container;

    setUp(() async {
      // Initialize services with real relay
      keyManager = NostrKeyManager();
      nostrService = NostrService(keyManager);
      authService = AuthService();
      subscriptionManager = SubscriptionManager(nostrService);
      profileCache = ProfileCacheService();

      await authService.initialize();
      await nostrService.initialize();
      await profileCache.initialize();

      // Ensure authenticated user for publishing
      if (!authService.isAuthenticated) {
        await authService.createNewIdentity();
      }

      // Create Riverpod container with real services
      container = ProviderContainer(
        overrides: [
          nostrServiceProvider.overrideWithValue(nostrService),
          profileCacheServiceProvider.overrideWithValue(profileCache),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      subscriptionManager.dispose();
      nostrService.dispose();
      authService.dispose();
      profileCache.dispose();
    });

    test('userProfileStream emits cached profile immediately', () async {
      // Arrange - Pre-populate cache
      const testPubkey = 'test_cached_pubkey_1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab';

      final cachedProfile = models.UserProfile(
        eventId: 'cached_event_id_123',
        pubkey: testPubkey,
        name: 'Cached User',
        displayName: 'Cached Display',
        about: 'From cache',
        picture: 'https://cached.com/avatar.jpg',
        createdAt: DateTime.now().subtract(Duration(hours: 1)),
        rawData: {},
      );

      await profileCache.cacheProfile(cachedProfile);

      // Act - Subscribe to stream
      final streamProvider = userProfileStreamProvider(testPubkey);
      models.UserProfile? firstEmission;

      container.listen(
        streamProvider,
        (previous, next) {
          next.whenData((profile) {
            if (profile != null && firstEmission == null) {
              firstEmission = profile;
            }
          });
        },
      );

      // Wait briefly for initial emission
      await Future.delayed(Duration(milliseconds: 200));

      // Assert - Should emit cached profile immediately
      expect(firstEmission, isNotNull,
          reason: 'Should emit cached profile immediately');
      expect(firstEmission?.name, equals('Cached User'));
      expect(firstEmission?.displayName, equals('Cached Display'));

      Log.info('✅ Cache-first test passed - emitted in <200ms');
    });

    test('userProfileStream receives real profile from relay', () async {
      // Arrange - Create and broadcast a real profile event
      final pubkey = authService.currentPublicKeyHex!;

      final profileData = {
        'name': 'Real Relay User',
        'display_name': 'Relay Display ${DateTime.now().millisecondsSinceEpoch}',
        'about': 'Published to real relay',
        'picture': 'https://relay.com/avatar.jpg',
      };

      Log.info('📤 Publishing profile event to relay...');

      final event = await authService.createAndSignEvent(
        kind: 0,
        content: jsonEncode(profileData),
        tags: [
          ['expiration', (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800).toString()],
        ],
      );

      expect(event, isNotNull);

      final broadcastResult = await nostrService.broadcastEvent(event!);
      expect(broadcastResult.isSuccessful, isTrue,
          reason: 'Profile event should broadcast successfully');

      Log.info('✅ Broadcasted to ${broadcastResult.successCount} relay(s)');
      Log.info('⏳ Waiting for relay to process and stream back...');

      // Act - Subscribe to stream
      final streamProvider = userProfileStreamProvider(pubkey);
      final receivedProfiles = <models.UserProfile>[];

      container.listen(
        streamProvider,
        (previous, next) {
          next.whenData((profile) {
            if (profile != null) {
              receivedProfiles.add(profile);
              Log.info('📨 Received profile: ${profile.displayName}');
            }
          });
        },
      );

      // Wait for profile to propagate through relay
      await Future.delayed(Duration(seconds: 5));

      // Assert - Should receive the profile via stream
      expect(receivedProfiles, isNotEmpty,
          reason: 'Should receive at least one profile from stream');

      final latestProfile = receivedProfiles.last;
      expect(latestProfile.displayName, contains('Relay Display'),
          reason: 'Should receive the profile we published');
      expect(latestProfile.name, equals('Real Relay User'));

      Log.info('✅ Stream test passed - received ${receivedProfiles.length} emission(s)');
    }, timeout: Timeout(Duration(seconds: 15)));

    test('userProfileStream updates when new profile event arrives', () async {
      // Arrange - Publish initial profile
      final pubkey = authService.currentPublicKeyHex!;

      final initialData = {
        'name': 'Initial Name',
        'display_name': 'Initial ${DateTime.now().millisecondsSinceEpoch}',
      };

      Log.info('📤 Publishing initial profile...');
      var event = await authService.createAndSignEvent(
        kind: 0,
        content: jsonEncode(initialData),
        tags: [
          ['expiration', (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800).toString()],
        ],
      );
      await nostrService.broadcastEvent(event!);

      // Subscribe to stream
      final streamProvider = userProfileStreamProvider(pubkey);
      final receivedNames = <String>[];

      container.listen(
        streamProvider,
        (previous, next) {
          next.whenData((profile) {
            if (profile?.name != null && !receivedNames.contains(profile!.name)) {
              receivedNames.add(profile.name!);
              Log.info('📨 Received: ${profile.name}');
            }
          });
        },
      );

      await Future.delayed(Duration(seconds: 3));

      // Act - Publish updated profile
      final updatedData = {
        'name': 'Updated Name',
        'display_name': 'Updated ${DateTime.now().millisecondsSinceEpoch}',
        'about': 'This is an update',
      };

      Log.info('📤 Publishing updated profile...');
      event = await authService.createAndSignEvent(
        kind: 0,
        content: jsonEncode(updatedData),
        tags: [
          ['expiration', (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800).toString()],
        ],
      );
      await nostrService.broadcastEvent(event!);

      // Wait for update to propagate
      await Future.delayed(Duration(seconds: 5));

      // Assert - Should have received both versions
      expect(receivedNames, contains('Initial Name'),
          reason: 'Should receive initial profile');
      expect(receivedNames, contains('Updated Name'),
          reason: 'Should receive updated profile');
      expect(receivedNames.length, greaterThanOrEqualTo(2),
          reason: 'Should emit both initial and updated profiles');

      Log.info('✅ Update test passed - received ${receivedNames.length} updates');
    }, timeout: Timeout(Duration(seconds: 20)));

    test('profiles are persisted to cache service', () async {
      // Arrange
      final pubkey = authService.currentPublicKeyHex!;

      final profileData = {
        'name': 'Cache Test User',
        'display_name': 'Cache ${DateTime.now().millisecondsSinceEpoch}',
      };

      Log.info('📤 Publishing profile for cache test...');
      final event = await authService.createAndSignEvent(
        kind: 0,
        content: jsonEncode(profileData),
        tags: [
          ['expiration', (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800).toString()],
        ],
      );
      await nostrService.broadcastEvent(event!);

      // Act - Subscribe and wait
      final streamProvider = userProfileStreamProvider(pubkey);
      container.listen(streamProvider, (previous, next) {});

      await Future.delayed(Duration(seconds: 5));

      // Assert - Profile should be in persistent cache
      final cachedProfile = profileCache.getCachedProfile(pubkey);

      expect(cachedProfile, isNotNull,
          reason: 'Profile should be persisted to cache service');
      expect(cachedProfile?.name, equals('Cache Test User'),
          reason: 'Cached profile should match published data');

      Log.info('✅ Cache persistence test passed');
    }, timeout: Timeout(Duration(seconds: 15)));

    test('batchProfilesStream fetches multiple profiles', () async {
      // Arrange - Get current user's pubkey (we know it has a profile)
      final knownPubkey = authService.currentPublicKeyHex!;

      // Use a second known pubkey (Jack Dorsey) that likely has a profile
      const jackPubkey = '82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2';

      final pubkeys = [knownPubkey, jackPubkey];

      Log.info('📤 Fetching profiles for ${pubkeys.length} users...');

      // Act - Subscribe to batch stream
      final streamProvider = batchProfilesStreamProvider(pubkeys);
      final profileMaps = <Map<String, models.UserProfile>>[];

      container.listen(
        streamProvider,
        (previous, next) {
          next.whenData((profiles) {
            if (profiles.isNotEmpty) {
              profileMaps.add(Map.from(profiles));
              Log.info('📨 Received ${profiles.length} profile(s)');
            }
          });
        },
      );

      // Wait for profiles to arrive
      await Future.delayed(Duration(seconds: 8));

      // Assert - Should receive at least one profile
      expect(profileMaps, isNotEmpty,
          reason: 'Should receive batch profile emissions');

      final latestProfiles = profileMaps.last;
      expect(latestProfiles.length, greaterThan(0),
          reason: 'Should have at least one profile in batch');

      Log.info('✅ Batch test passed - received ${latestProfiles.length} profile(s)');
    }, timeout: Timeout(Duration(seconds: 15)));

    test('fetchUserProfile returns cached immediately and refreshes background', () async {
      // Arrange - Cache a profile
      const testPubkey = 'test_async_pubkey_1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab';

      final cachedProfile = models.UserProfile(
        eventId: 'async_cached_event_id_456',
        pubkey: testPubkey,
        name: 'Async Cached',
        displayName: 'Async Display',
        createdAt: DateTime.now(),
        rawData: {},
      );

      await profileCache.cacheProfile(cachedProfile);

      // Act - Call async fetch provider
      final startTime = DateTime.now();
      final profile = await container.read(fetchUserProfileProvider(testPubkey).future);
      final loadTime = DateTime.now().difference(startTime);

      // Assert - Should return quickly from cache
      expect(profile, isNotNull, reason: 'Should return cached profile');
      expect(profile?.displayName, equals('Async Display'));
      expect(loadTime.inMilliseconds, lessThan(500),
          reason: 'Should return from cache in <500ms');

      Log.info('✅ Async provider test passed - returned in ${loadTime.inMilliseconds}ms');
    });
  });
}
