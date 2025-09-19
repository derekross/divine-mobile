// ABOUTME: Comprehensive Riverpod providers for all application services
// ABOUTME: Replaces Provider MultiProvider setup with pure Riverpod dependency injection

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openvine/services/age_verification_service.dart';
import 'package:openvine/services/analytics_service.dart';
import 'package:openvine/services/api_service.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/bookmark_service.dart';
import 'package:openvine/services/nostr_service_factory.dart';
import 'package:openvine/services/connection_status_service.dart';
import 'package:openvine/services/content_blocklist_service.dart';
import 'package:openvine/services/content_deletion_service.dart';
import 'package:openvine/services/content_reporting_service.dart';
import 'package:openvine/services/curated_list_service.dart';
import 'package:openvine/services/curation_service.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/explore_video_manager.dart';
import 'package:openvine/providers/analytics_providers.dart';
import 'package:openvine/services/hashtag_service.dart';
import 'package:openvine/services/mute_service.dart';
import 'package:openvine/services/nip05_service.dart';
import 'package:openvine/services/nip98_auth_service.dart';
import 'package:openvine/services/nostr_key_manager.dart';
// NostrService now includes embedded relay functionality
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/notification_service_enhanced.dart';
import 'package:openvine/services/personal_event_cache_service.dart';
import 'package:openvine/services/profile_cache_service.dart';
import 'package:openvine/services/secure_key_storage_service.dart';
import 'package:openvine/services/seen_videos_service.dart';
import 'package:openvine/services/social_service.dart';
import 'package:openvine/services/hashtag_cache_service.dart';
import 'package:openvine/services/blossom_upload_service.dart';
import 'package:openvine/services/stream_upload_service.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/services/upload_manager.dart';
import 'package:openvine/services/user_profile_service.dart';
import 'package:openvine/services/video_event_publisher.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/video_sharing_service.dart';
import 'package:openvine/services/video_visibility_manager.dart';
import 'package:openvine/services/web_auth_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'app_providers.g.dart';

// =============================================================================
// FOUNDATIONAL SERVICES (No dependencies)
// =============================================================================

/// Connection status service for monitoring network connectivity
@riverpod
ConnectionStatusService connectionStatusService(Ref ref) {
  return ConnectionStatusService();
}

/// Video visibility manager for controlling video playback based on visibility
@riverpod
VideoVisibilityManager videoVisibilityManager(Ref ref) {
  return VideoVisibilityManager();
}

/// Analytics service with opt-out support
@Riverpod(keepAlive: true) // Keep alive to maintain singleton behavior
AnalyticsService analyticsService(Ref ref) {
  final service = AnalyticsService();

  // Ensure cleanup on disposal
  ref.onDispose(() {
    service.dispose();
  });

  // Initialize asynchronously but don't block the provider
  // Use a microtask to avoid blocking the provider creation
  Future.microtask(() => service.initialize());

  return service;
}

/// Age verification service for content creation restrictions
@riverpod
AgeVerificationService ageVerificationService(Ref ref) {
  final service = AgeVerificationService();
  service.initialize(); // Initialize asynchronously
  return service;
}

/// Secure key storage service (foundational service)
@Riverpod(keepAlive: true)
SecureKeyStorageService secureKeyStorageService(Ref ref) {
  return SecureKeyStorageService();
}

/// Web authentication service (for web platform only)
@riverpod
WebAuthService webAuthService(Ref ref) {
  return WebAuthService();
}

/// Nostr key manager for cryptographic operations
@Riverpod(keepAlive: true)
NostrKeyManager nostrKeyManager(Ref ref) {
  return NostrKeyManager();
}

/// Profile cache service for persistent profile storage
@riverpod
ProfileCacheService profileCacheService(Ref ref) {
  final service = ProfileCacheService();
  // Initialize asynchronously to avoid blocking UI
  service.initialize().catchError((e) {
    Log.error('Failed to initialize ProfileCacheService',
        name: 'AppProviders', error: e);
  });
  return service;
}

/// Hashtag cache service for persistent hashtag storage
@riverpod
HashtagCacheService hashtagCacheService(Ref ref) {
  final service = HashtagCacheService();
  // Initialize asynchronously to avoid blocking UI
  service.initialize().catchError((e) {
    Log.error('Failed to initialize HashtagCacheService',
        name: 'AppProviders', error: e);
  });
  return service;
}

/// Personal event cache service for ALL user's own events
@riverpod
PersonalEventCacheService personalEventCacheService(Ref ref) {
  final authService = ref.watch(authServiceProvider);
  final service = PersonalEventCacheService();

  // Initialize with current user's pubkey when authenticated
  if (authService.isAuthenticated && authService.currentPublicKeyHex != null) {
    service.initialize(authService.currentPublicKeyHex!).catchError((e) {
      Log.error('Failed to initialize PersonalEventCacheService',
          name: 'AppProviders', error: e);
    });
  }

  return service;
}

/// Seen videos service for tracking viewed content
@riverpod
SeenVideosService seenVideosService(Ref ref) {
  return SeenVideosService();
}

/// Content blocklist service for filtering unwanted content from feeds
@riverpod
ContentBlocklistService contentBlocklistService(Ref ref) {
  return ContentBlocklistService();
}

/// NIP-05 service for username registration and verification
@riverpod
Nip05Service nip05Service(Ref ref) {
  return Nip05Service();
}

// (Removed duplicate legacy provider for StreamUploadService)

// =============================================================================
// DEPENDENT SERVICES (With dependencies)
// =============================================================================

/// Authentication service depends on secure key storage
@Riverpod(keepAlive: true)
AuthService authService(Ref ref) {
  final keyStorage = ref.watch(secureKeyStorageServiceProvider);
  return AuthService(keyStorage: keyStorage);
}

/// Core Nostr service with platform-aware embedded relay functionality and P2P capabilities
@Riverpod(keepAlive: true)
INostrService nostrService(Ref ref) {
  final keyManager = ref.watch(nostrKeyManagerProvider);

  // Use factory to create platform-appropriate service
  final service = NostrServiceFactory.create(keyManager);

  // Initialize the service with appropriate parameters
  NostrServiceFactory.initialize(service);

  // Cleanup on disposal
  ref.onDispose(() {
    service.dispose();
  });

  return service;
}

/// Subscription manager for centralized subscription management
@Riverpod(keepAlive: true)
SubscriptionManager subscriptionManager(Ref ref) {
  final nostrService = ref.watch(nostrServiceProvider);
  return SubscriptionManager(nostrService);
}

/// Video event service depends on Nostr, SeenVideos, Blocklist, and SubscriptionManager services
@Riverpod(keepAlive: true)
VideoEventService videoEventService(Ref ref) {
  final nostrService = ref.watch(nostrServiceProvider);
  final subscriptionManager = ref.watch(subscriptionManagerProvider);
  final blocklistService = ref.watch(contentBlocklistServiceProvider);
  final userProfileService = ref.watch(userProfileServiceProvider);

  final service = VideoEventService(
    nostrService,
    subscriptionManager: subscriptionManager,
    userProfileService: userProfileService,
  );
  service.setBlocklistService(blocklistService);
  return service;
}

/// Hashtag service depends on Video event service and cache service
@riverpod
HashtagService hashtagService(Ref ref) {
  final videoEventService = ref.watch(videoEventServiceProvider);
  final cacheService = ref.watch(hashtagCacheServiceProvider);
  return HashtagService(videoEventService, cacheService);
}

/// User profile service depends on Nostr service, SubscriptionManager, and ProfileCacheService
@Riverpod(keepAlive: true)
UserProfileService userProfileService(Ref ref) {
  final nostrService = ref.watch(nostrServiceProvider);
  final subscriptionManager = ref.watch(subscriptionManagerProvider);
  final profileCache = ref.watch(profileCacheServiceProvider);

  final service = UserProfileService(
    nostrService,
    subscriptionManager: subscriptionManager,
  );
  service.setPersistentCache(profileCache);
  return service;
}

/// Social service depends on Nostr service, Auth service, and SubscriptionManager
@Riverpod(keepAlive: true)
SocialService socialService(Ref ref) {
  final nostrService = ref.watch(nostrServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final subscriptionManager = ref.watch(subscriptionManagerProvider);
  final personalEventCache = ref.watch(personalEventCacheServiceProvider);

  return SocialService(
    nostrService,
    authService,
    subscriptionManager: subscriptionManager,
    personalEventCache: personalEventCache,
  );
}

// ProfileStatsProvider is now handled by profile_stats_provider.dart with pure Riverpod

// ProfileVideosProvider is now handled by profile_videos_provider.dart with pure Riverpod

/// Enhanced notification service with Nostr integration (lazy loaded)
@riverpod
NotificationServiceEnhanced notificationServiceEnhanced(Ref ref) {
  final service = NotificationServiceEnhanced();

  // Delay initialization until after critical path is loaded
  if (!kIsWeb) {
    // Initialize immediately on mobile
    final nostrService = ref.watch(nostrServiceProvider);
    final profileService = ref.watch(userProfileServiceProvider);
    final videoService = ref.watch(videoEventServiceProvider);

    Future.microtask(() async {
      try {
        await service.initialize(
          nostrService: nostrService,
          profileService: profileService,
          videoService: videoService,
        );
      } catch (e) {
        Log.error('Failed to initialize enhanced notification service: $e',
            name: 'AppProviders', category: LogCategory.system);
      }
    });
  } else {
    // On web, delay initialization by 3 seconds to allow main UI to load first
    Timer(const Duration(seconds: 3), () async {
      try {
        final nostrService = ref.read(nostrServiceProvider);
        final profileService = ref.read(userProfileServiceProvider);
        final videoService = ref.read(videoEventServiceProvider);

        await service.initialize(
          nostrService: nostrService,
          profileService: profileService,
          videoService: videoService,
        );
      } catch (e) {
        Log.error('Failed to initialize enhanced notification service: $e',
            name: 'AppProviders', category: LogCategory.system);
      }
    });
  }

  return service;
}

// VideoManagerService removed - using pure Riverpod VideoManager provider instead

/// NIP-98 authentication service
@riverpod
Nip98AuthService nip98AuthService(Ref ref) {
  final authService = ref.watch(authServiceProvider);
  return Nip98AuthService(authService: authService);
}

/// Direct upload service with auth
@riverpod
DirectUploadService directUploadService(Ref ref) {
  final authService = ref.watch(nip98AuthServiceProvider);
  return DirectUploadService(authService: authService);
}

/// Stream upload service (uses Cloudflare Stream)
@riverpod
StreamUploadService streamUploadService(Ref ref) {
  final authService = ref.watch(nip98AuthServiceProvider);
  return StreamUploadService(authService: authService);
}

/// Blossom upload service (uses user-configured Blossom server)
@riverpod
BlossomUploadService blossomUploadService(Ref ref) {
  final authService = ref.watch(authServiceProvider);
  final nostrService = ref.watch(nostrServiceProvider);
  return BlossomUploadService(authService: authService, nostrService: nostrService);
}

/// Upload manager depends on direct upload service and optionally blossom service
@Riverpod(keepAlive: true)
UploadManager uploadManager(Ref ref) {
  final directService = ref.watch(directUploadServiceProvider);
  final blossomService = ref.watch(blossomUploadServiceProvider);
  return UploadManager(
    uploadService: directService,
    blossomService: blossomService,
  );
}

/// API service depends on auth service
@riverpod
ApiService apiService(Ref ref) {
  final authService = ref.watch(nip98AuthServiceProvider);
  return ApiService(authService: authService);
}

/// Video event publisher depends on multiple services
@Riverpod(keepAlive: true)
VideoEventPublisher videoEventPublisher(Ref ref) {
  final uploadManager = ref.watch(uploadManagerProvider);
  final nostrService = ref.watch(nostrServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final personalEventCache = ref.watch(personalEventCacheServiceProvider);

  return VideoEventPublisher(
    uploadManager: uploadManager,
    nostrService: nostrService,
    authService: authService,
    personalEventCache: personalEventCache,
  );
}

/// Curation Service - manages NIP-51 video curation sets
@Riverpod(keepAlive: true)
CurationService curationService(Ref ref) {
  final nostrService = ref.watch(nostrServiceProvider);
  final videoEventService = ref.watch(videoEventServiceProvider);
  final socialService = ref.watch(socialServiceProvider);

  return CurationService(
    nostrService: nostrService,
    videoEventService: videoEventService,
    socialService: socialService,
  );
}

/// ExploreVideoManager - bridges CurationService with Riverpod VideoManager
/// FIXED: Removed VideoManager dependency to break circular dependency
@Riverpod(keepAlive: true)
ExploreVideoManager exploreVideoManager(Ref ref) {
  final curationService = ref.watch(curationServiceProvider);

  // Create ExploreVideoManager without VideoManager to avoid circular dependency
  // The VideoManager integration is now handled at the call site where needed
  final manager = ExploreVideoManager(
    curationService: curationService,
  );

  return manager;
}

/// Content reporting service for NIP-56 compliance
@riverpod
Future<ContentReportingService> contentReportingService(Ref ref) async {
  final nostrService = ref.watch(nostrServiceProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return ContentReportingService(
    nostrService: nostrService,
    prefs: prefs,
  );
}

/// Curated list service for NIP-51 lists
@riverpod
Future<CuratedListService> curatedListService(Ref ref) async {
  final nostrService = ref.watch(nostrServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);

  return CuratedListService(
    nostrService: nostrService,
    authService: authService,
    prefs: prefs,
  );
}

/// Bookmark service for NIP-51 bookmarks
@riverpod
Future<BookmarkService> bookmarkService(Ref ref) async {
  final nostrService = ref.watch(nostrServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);

  return BookmarkService(
    nostrService: nostrService,
    authService: authService,
    prefs: prefs,
  );
}

/// Mute service for NIP-51 mute lists
@riverpod
Future<MuteService> muteService(Ref ref) async {
  final nostrService = ref.watch(nostrServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);

  return MuteService(
    nostrService: nostrService,
    authService: authService,
    prefs: prefs,
  );
}

/// Video sharing service
@riverpod
VideoSharingService videoSharingService(Ref ref) {
  final nostrService = ref.watch(nostrServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final userProfileService = ref.watch(userProfileServiceProvider);

  return VideoSharingService(
    nostrService: nostrService,
    authService: authService,
    userProfileService: userProfileService,
  );
}

/// Content deletion service for NIP-09 delete events
@riverpod
Future<ContentDeletionService> contentDeletionService(Ref ref) async {
  final nostrService = ref.watch(nostrServiceProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return ContentDeletionService(
    nostrService: nostrService,
    prefs: prefs,
  );
}
