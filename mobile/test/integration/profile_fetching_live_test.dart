// ABOUTME: Integration test for profile fetching against live Nostr relays
// ABOUTME: Verifies Kind 0 events are fetched when videos are received

import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/services/nostr_service.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/services/user_profile_service.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/profile_cache_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:nostr_sdk/nostr_sdk.dart' as nostr_sdk;

void main() {
  late NostrService nostrService;
  late SubscriptionManager subscriptionManager;
  late UserProfileService profileService;
  late VideoEventService videoEventService;
  late ProfileCacheService cacheService;

  setUpAll(() {
    // Initialize logging
    Log.initialize(
      logLevel: LogLevel.verbose,
      enableFileLogging: false,
    );
  });

  setUp(() async {
    // Initialize Nostr SDK
    await nostr_sdk.loadRust();
    
    // Create services
    nostrService = NostrService();
    subscriptionManager = SubscriptionManager(nostrService);
    cacheService = ProfileCacheService();
    await cacheService.initialize();
    
    profileService = UserProfileService(
      nostrService,
      subscriptionManager: subscriptionManager,
    );
    profileService.setPersistentCache(cacheService);
    
    videoEventService = VideoEventService(
      nostrService,
      subscriptionManager: subscriptionManager,
      userProfileService: profileService,
    );
    
    // Initialize services
    await nostrService.initialize();
    await profileService.initialize();
  });

  tearDown(() async {
    await nostrService.dispose();
    profileService.dispose();
    videoEventService.dispose();
    await cacheService.dispose();
  });

  group('Live Relay Profile Fetching', () {
    test('should fetch profiles when connecting to OpenVine relay', () async {
      // Connect to OpenVine relay
      await nostrService.connectToRelay('wss://relay3.openvine.co');
      
      // Wait for connection
      await Future.delayed(const Duration(seconds: 2));
      
      // Check connection status
      expect(nostrService.connectedRelayCount, greaterThan(0),
          reason: 'Should be connected to at least one relay');
      
      // Subscribe to video feed to trigger profile fetching
      await videoEventService.subscribeToVideoFeed(
        subscriptionType: SubscriptionType.discovery,
        limit: 10,
      );
      
      // Wait for events to arrive
      await Future.delayed(const Duration(seconds: 5));
      
      // Check if we received any videos
      final videos = videoEventService.discoveryVideos;
      print('Received ${videos.length} videos from relay');
      
      if (videos.isNotEmpty) {
        // Check if profiles were fetched for video authors
        int profilesFound = 0;
        for (final video in videos) {
          final profile = profileService.getCachedProfile(video.pubkey);
          if (profile != null) {
            profilesFound++;
            print('Profile found for ${video.pubkey.substring(0, 8)}: ${profile.bestDisplayName}');
          } else {
            print('No profile for ${video.pubkey.substring(0, 8)} yet');
          }
        }
        
        // At least some profiles should have been fetched
        expect(profilesFound, greaterThan(0),
            reason: 'Should have fetched at least one profile');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('should fetch specific known profile from relay', () async {
      // Connect to relay
      await nostrService.connectToRelay('wss://relay.damus.io');
      
      // Wait for connection
      await Future.delayed(const Duration(seconds: 2));
      
      // Known pubkey with profile (Jack Dorsey)
      const knownPubkey = '82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2';
      
      // Fetch profile
      await profileService.fetchProfile(knownPubkey);
      
      // Wait for profile to arrive
      await Future.delayed(const Duration(seconds: 3));
      
      // Check if profile was fetched
      final profile = profileService.getCachedProfile(knownPubkey);
      expect(profile, isNotNull, reason: 'Profile should have been fetched');
      
      if (profile != null) {
        print('Profile fetched: ${profile.bestDisplayName}');
        print('  Name: ${profile.name}');
        print('  Display Name: ${profile.displayName}');
        print('  About: ${profile.about?.substring(0, 50)}...');
        
        // Verify profile has content
        expect(profile.name ?? profile.displayName, isNotEmpty,
            reason: 'Profile should have a name');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('should batch fetch multiple profiles efficiently', () async {
      // Connect to relay
      await nostrService.connectToRelay('wss://relay3.openvine.co');
      
      // Wait for connection
      await Future.delayed(const Duration(seconds: 2));
      
      // Subscribe to get some video events
      await videoEventService.subscribeToVideoFeed(
        subscriptionType: SubscriptionType.discovery,
        limit: 20,
      );
      
      // Wait for events
      await Future.delayed(const Duration(seconds: 3));
      
      final videos = videoEventService.discoveryVideos;
      if (videos.isEmpty) {
        print('No videos received, skipping batch test');
        return;
      }
      
      // Get unique pubkeys
      final pubkeys = videos.map((v) => v.pubkey).toSet().toList();
      print('Batch fetching ${pubkeys.length} unique profiles');
      
      // Batch fetch profiles
      await profileService.fetchMultipleProfiles(pubkeys);
      
      // Wait for profiles to arrive
      await Future.delayed(const Duration(seconds: 5));
      
      // Count fetched profiles
      int fetchedCount = 0;
      for (final pubkey in pubkeys) {
        if (profileService.hasProfile(pubkey)) {
          fetchedCount++;
          final profile = profileService.getCachedProfile(pubkey);
          print('✓ ${pubkey.substring(0, 8)}: ${profile?.bestDisplayName}');
        } else {
          print('✗ ${pubkey.substring(0, 8)}: No profile');
        }
      }
      
      print('Fetched $fetchedCount/${pubkeys.length} profiles');
      
      // Should fetch at least some profiles
      expect(fetchedCount, greaterThan(0),
          reason: 'Should have fetched at least one profile in batch');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}