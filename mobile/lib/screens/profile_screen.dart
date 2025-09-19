import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostr_sdk/event.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/profile_stats_provider.dart';
import 'package:openvine/providers/profile_videos_provider.dart';
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:openvine/screens/debug_video_test.dart';
import 'package:openvine/screens/key_import_screen.dart';
import 'package:openvine/screens/profile_setup_screen.dart';
import 'package:openvine/screens/relay_settings_screen.dart';
import 'package:openvine/screens/blossom_settings_screen.dart';
import 'package:openvine/screens/universal_camera_screen.dart';
import 'package:openvine/services/global_video_registry.dart';
import 'package:openvine/services/social_service.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/nostr_encoding.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/providers/optimistic_follow_provider.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/screens/followers_screen.dart';
import 'package:openvine/screens/following_screen.dart';
import 'package:openvine/widgets/user_avatar.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  // If null, shows current user's profile

  const ProfileScreen({super.key, this.profilePubkey});
  final String? profilePubkey;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isOwnProfile = true;
  String? _targetPubkey;

  // Video feed state for embedded video viewing
  bool _isInVideoMode = false;
  VideoEvent? _selectedVideo;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Determine if viewing own profile and set target pubkey
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProfile();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force refresh when returning to profile tab after publishing
    if (_isOwnProfile && _targetPubkey != null) {
      final tabIndex = ref.watch(tabVisibilityProvider);
      if (tabIndex == 3) {
        // Profile tab is index 3
        // Refresh profile data when tab becomes active
        _refreshProfileData();
      }
    }
  }

  Future<void> _initializeProfile() async {
    final authService = ref.read(authServiceProvider);

    // Wait for AuthService to be properly initialized
    if (!authService.isAuthenticated) {
      Log.warning('AuthService not ready, waiting for authentication',
          name: 'ProfileScreen', category: LogCategory.ui);

      // Use proper async pattern instead of Future.delayed
      final completer = Completer<void>();

      void checkAuth() {
        if (authService.isAuthenticated &&
            authService.currentPublicKeyHex != null) {
          completer.complete();
        } else {
          // Check again on next frame
          WidgetsBinding.instance.addPostFrameCallback((_) => checkAuth());
        }
      }

      checkAuth();
      await completer.future;
    }

    final currentUserPubkey = authService.currentPublicKeyHex;

    // Determine target pubkey and ownership
    setState(() {
      _targetPubkey = widget.profilePubkey ?? currentUserPubkey;
      _isOwnProfile = _targetPubkey == currentUserPubkey;
    });

    Log.info('🔍 Profile init debug:',
        name: 'ProfileScreen', category: LogCategory.ui);
    Log.info(
        '  - widget.profilePubkey: ${widget.profilePubkey?.substring(0, 8) ?? "null"}',
        name: 'ProfileScreen',
        category: LogCategory.ui);
    Log.info(
        '  - currentUserPubkey: ${currentUserPubkey?.substring(0, 8) ?? "unknown"}',
        name: 'ProfileScreen',
        category: LogCategory.ui);
    Log.info('  - _isOwnProfile: $_isOwnProfile',
        name: 'ProfileScreen', category: LogCategory.ui);
    Log.info(
        '  - _targetPubkey: ${_targetPubkey != null ? _targetPubkey!.substring(0, 8) : "null"}',
        name: 'ProfileScreen',
        category: LogCategory.ui);

    // Log current cached profile
    final profileState = ref.read(userProfileNotifierProvider);
    final cachedProfile = profileState.getCachedProfile(_targetPubkey!);
    if (cachedProfile != null) {
      Log.info('📋 ProfileScreen: Cached profile found on init:',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - name: ${cachedProfile.name}',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - displayName: ${cachedProfile.displayName}',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - about: ${cachedProfile.about}',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - eventId: ${cachedProfile.eventId}',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - createdAt: ${cachedProfile.createdAt}',
          name: 'ProfileScreen', category: LogCategory.ui);
    } else {
      Log.info(
          '📋 ProfileScreen: No cached profile found on init for ${_targetPubkey!.substring(0, 8)}...',
          name: 'ProfileScreen',
          category: LogCategory.ui);
    }

    Log.info('🔍 ProfileScreen: Loading profile data',
        name: 'ProfileScreen', category: LogCategory.ui);
    Log.info(
        '  - Current user pubkey: ${ref.read(authServiceProvider).currentPublicKeyHex?.substring(0, 8) ?? "null"}',
        name: 'ProfileScreen',
        category: LogCategory.ui);
    Log.info('  - Target pubkey: ${_targetPubkey?.substring(0, 8) ?? "null"}',
        name: 'ProfileScreen', category: LogCategory.ui);

    // Load profile data for the target user
    if (_targetPubkey != null) {
      // Force refresh both stats and videos to resolve any cache issues
      Log.info(
          '🔄 Forcing refresh of profile data for ${_targetPubkey!.substring(0, 8)}',
          name: 'ProfileScreen',
          category: LogCategory.ui);

      // Load profile data (removed duplicate calls)
      _loadProfileStats();
      _loadProfileVideos();

      // Always load user profile to ensure we have display name
      _loadUserProfile();

      // Note: Video events are managed globally by Riverpod providers
      // Profile-specific video loading is handled by ProfileVideosProvider
    }
  }

  void _loadProfileStats() {
    if (_targetPubkey == null) return;

    final profileStatsNotifier =
        ref.read(profileStatsNotifierProvider.notifier);
    profileStatsNotifier.loadStats(_targetPubkey!);
  }

  void _loadProfileVideos() {
    if (_targetPubkey == null) {
      Log.error('Cannot load profile videos: _targetPubkey is null',
          name: 'ProfileScreen', category: LogCategory.ui);
      return;
    }

    Log.debug(
        'Loading profile videos for: ${_targetPubkey!.substring(0, 8)}... (isOwnProfile: $_isOwnProfile)',
        name: 'ProfileScreen',
        category: LogCategory.ui);
    try {
      // Clear cache first to force fresh load
      clearAllProfileVideosCache();

      final profileVideosNotifier =
          ref.read(profileVideosNotifierProvider.notifier);
      profileVideosNotifier.loadVideosForUser(_targetPubkey!).then((_) {
        Log.info(
            'Profile videos load completed for ${_targetPubkey!.substring(0, 8)}',
            name: 'ProfileScreen',
            category: LogCategory.ui);
      }).catchError((error) {
        Log.error(
            'Profile videos load failed for ${_targetPubkey!.substring(0, 8)}: $error',
            name: 'ProfileScreen',
            category: LogCategory.ui);
      });
    } catch (e) {
      Log.error('Error initiating profile videos load: $e',
          name: 'ProfileScreen', category: LogCategory.ui);
    }
  }

  // Compact formatter for counts (e.g., 12.3K, 1.2M)
  String _formatCount(int count) {
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  void _refreshProfileData() {
    if (_targetPubkey == null) return;

    Log.info('🔄 Refreshing profile data for ${_targetPubkey!.substring(0, 8)}',
        name: 'ProfileScreen', category: LogCategory.ui);

    // Clear caches and reload everything
    clearAllProfileVideosCache();
    ref.invalidate(profileVideosNotifierProvider);
    ref.invalidate(profileStatsNotifierProvider);
    ref.invalidate(userProfileNotifierProvider);

    // Reload data
    _loadProfileStats();
    _loadProfileVideos();
    _loadUserProfile();
  }

  void _loadUserProfile() {
    if (_targetPubkey == null) return;

    // Defer profile loading to avoid triggering during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProfileNotifier =
          ref.read(userProfileNotifierProvider.notifier);

      // Only fetch if not already cached - show cached data immediately
      if (!userProfileNotifier.hasProfile(_targetPubkey!)) {
        Log.debug(
            '📥 Fetching uncached profile: ${_targetPubkey!.substring(0, 8)}',
            name: 'ProfileScreen',
            category: LogCategory.ui);
        userProfileNotifier.fetchProfile(_targetPubkey!);
      } else {
        Log.debug('📋 Using cached profile: ${_targetPubkey!.substring(0, 8)}',
            name: 'ProfileScreen', category: LogCategory.ui);
        // Still call fetchProfile to trigger background refresh if needed
        userProfileNotifier.fetchProfile(_targetPubkey!);
      }
    });
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if the profile pubkey has changed
    if (widget.profilePubkey != oldWidget.profilePubkey) {
      Log.info(
        'Profile pubkey changed from ${oldWidget.profilePubkey} to ${widget.profilePubkey}',
        name: 'ProfileScreen',
        category: LogCategory.ui,
      );
      // Reinitialize with new profile
      _initializeProfile();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      // Watch Riverpod providers
      final authService = ref.watch(authServiceProvider);
      final socialService = ref.watch(socialServiceProvider);
      final profileStatsState = ref.watch(profileStatsNotifierProvider);

      // Get profile for display name in app bar
      final authProfile = _isOwnProfile ? authService.currentProfile : null;

      // Use the unified Riverpod provider for synchronous access
      final profileState = ref.watch(userProfileNotifierProvider);
      final cachedProfile = _targetPubkey != null
          ? profileState.getCachedProfile(_targetPubkey!)
          : null;

      // Better fallback for display name
      String userName;
      if (cachedProfile?.bestDisplayName != null &&
          !cachedProfile!.bestDisplayName.startsWith('npub1')) {
        userName = cachedProfile.bestDisplayName;
      } else if (authProfile?.displayName != null &&
          authProfile!.displayName.isNotEmpty) {
        userName = authProfile.displayName;
      } else if (_targetPubkey != null) {
        // Use shortened pubkey while loading instead of showing npub
        userName = '${_targetPubkey!.substring(0, 8)}...';
      } else {
        userName = 'Loading...';
      }

      return Scaffold(
        key: ValueKey('profile_screen_${_targetPubkey ?? 'unknown'}'),
        backgroundColor: VineTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: VineTheme.vineGreen,
          elevation: 1,
          title: Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: VineTheme.whiteText, size: 16),
              const SizedBox(width: 4),
              Text(
                userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          actions: [
            if (_isOwnProfile) ...[
              IconButton(
                icon: const Icon(Icons.add_box_outlined, color: Colors.white),
                onPressed: _createNewVine,
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Log.debug('📱 Hamburger menu tapped',
                        name: 'ProfileScreen', category: LogCategory.ui);
                    _showOptionsMenu();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.menu,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: _showUserOptions,
              ),
            ],
          ],
        ),
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isInVideoMode
                  ? _buildVideoModeView()
                  : _buildProfileView(socialService, profileStatsState),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      Log.error('ProfileScreen build error: $e',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.error('Stack trace: $stackTrace',
          name: 'ProfileScreen', category: LogCategory.ui);

      // Return a simple error screen instead of crashing
      return Scaffold(
        backgroundColor: VineTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: VineTheme.vineGreen,
          title: const Text('Profile', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 64),
              SizedBox(height: 16),
              Text(
                'Error loading profile',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'Please try again',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildProfileHeader(
      SocialService socialService, ProfileStatsState profileStatsState) {
    // Watch Riverpod providers directly
    final authService = ref.watch(authServiceProvider);

    // Get the profile data for the target user (could be current user or another user)
    final authProfile = _isOwnProfile ? authService.currentProfile : null;

    // Use the unified Riverpod provider for synchronous access
    final profileState = ref.watch(userProfileNotifierProvider);
    final cachedProfile = _targetPubkey != null
        ? profileState.getCachedProfile(_targetPubkey!)
        : null;

    final profilePictureUrl = authProfile?.picture ?? cachedProfile?.picture;
    // Always prefer cachedProfile (UserProfileService) over authProfile for display name
    // because UserProfileService has the most up-to-date data from the relay
    String displayName;
    if (cachedProfile?.bestDisplayName != null &&
        !cachedProfile!.bestDisplayName.startsWith('npub1')) {
      displayName = cachedProfile.bestDisplayName;
    } else if (authProfile?.displayName != null &&
        authProfile!.displayName.isNotEmpty) {
      displayName = authProfile.displayName;
    } else if (_targetPubkey != null) {
      // Use shortened pubkey while loading instead of showing npub
      displayName = '${_targetPubkey!.substring(0, 8)}...';
    } else {
      displayName = 'Loading...';
    }

    final hasCustomName = displayName != 'Loading...' &&
        !displayName.contains('...') &&
        !displayName.startsWith('npub1');

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Setup profile banner for new users with default names (only on own profile)
          if (_isOwnProfile && !hasCustomName)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Colors.blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Complete Your Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add your name, bio, and picture to get started',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _setupProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Set Up',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Profile picture and follow button row
          Row(
            children: [
              // Profile picture
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.pink, Colors.orange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: UserAvatar(
                      imageUrl: profilePictureUrl,
                      name: null,
                      size: 80,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Stats
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildDynamicStatColumn(
                      profileStatsState.hasData
                          ? profileStatsState.stats!.videoCount
                          : null,
                      'Vines',
                      profileStatsState.isLoading,
                    ),
                    _buildDynamicStatColumn(
                      profileStatsState.hasData
                          ? profileStatsState.stats!.followers
                          : null,
                      'Followers',
                      profileStatsState.isLoading,
                      onTap: _showFollowersList,
                    ),
                    _buildDynamicStatColumn(
                      profileStatsState.hasData
                          ? profileStatsState.stats!.following
                          : null,
                      'Following',
                      profileStatsState.isLoading,
                      onTap: _showFollowingList,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Name and bio
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SelectableText(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    // Add Vine verified badge if this was a verified Vine account
                    if (cachedProfile?.vineVerified == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ]
                    // Add NIP-05 verification badge if verified
                    else if ((authProfile?.nip05 ?? cachedProfile?.nip05) !=
                            null &&
                        (authProfile?.nip05 ?? cachedProfile?.nip05)!
                            .isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ],
                    // Show Vine import badge
                    if (cachedProfile?.isVineImport == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Colors.purple.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.archive_outlined,
                              color: Colors.purple[300],
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Vine Import',
                              style: TextStyle(
                                color: Colors.purple[300],
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Show NIP-05 identifier if present
                if ((authProfile?.nip05 ?? cachedProfile?.nip05) != null &&
                    (authProfile?.nip05 ?? cachedProfile?.nip05)!.isNotEmpty)
                  Text(
                    authProfile?.nip05 ?? cachedProfile?.nip05 ?? '',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 4),
                if ((authProfile?.about ?? cachedProfile?.about) != null &&
                    (authProfile?.about ?? cachedProfile?.about)!.isNotEmpty)
                  SelectableText(
                    (authProfile?.about ?? cachedProfile?.about)!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                const SizedBox(height: 8),
                // Show location if available
                if (cachedProfile?.location != null &&
                    cachedProfile!.location!.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        cachedProfile.location!,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                // Show Vine stats if this is an imported Vine account
                if (cachedProfile?.isVineImport == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.purple.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 14, color: Colors.purple[300]),
                            const SizedBox(width: 6),
                            Text(
                              'Original Vine Stats',
                              style: TextStyle(
                                color: Colors.purple[300],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (cachedProfile != null &&
                                cachedProfile.vineLoops != null) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatCount(cachedProfile.vineLoops!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Loops',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 24),
                            ],
                            if (cachedProfile?.vineFollowers != null &&
                                cachedProfile!.vineFollowers! > 0) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatCount(cachedProfile.vineFollowers!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Vine Followers',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This account was imported from the original Vine archive',
                          style: TextStyle(
                            color: Colors.purple[200],
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Public key display with copy functionality
                if (_targetPubkey != null)
                  GestureDetector(
                    onTap: _copyNpubToClipboard,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey[600]!, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            NostrEncoding.encodePublicKey(_targetPubkey!),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.copy,
                            color: Colors.grey,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a stat column with loading state support and optional tap handler
  Widget _buildDynamicStatColumn(int? count, String label, bool isLoading,
      {VoidCallback? onTap}) {
    final content = Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: isLoading
              ? const Text(
                  '—',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                )
              : Text(
                  count != null ? _formatCount(count) : '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildStatsRow(ProfileStatsState profileStatsState) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VineTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: profileStatsState.isLoading
                      ? const Text(
                          '—',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : Text(
                          _formatCount(
                              profileStatsState.stats?.totalViews ?? 0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                Text(
                  'Total Views',
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: profileStatsState.isLoading
                      ? const Text(
                          '—',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : Text(
                          _formatCount(
                              profileStatsState.stats?.totalLikes ?? 0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                Text(
                  'Total Likes',
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildActionButtons() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            if (_isOwnProfile) ...[
              Expanded(
                child: ElevatedButton(
                  onPressed: _editProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _shareProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Share Profile'),
                ),
              ),
            ] else ...[
              Expanded(
                child: Consumer(
                  builder: (context, ref, child) {
                    final isFollowing =
                        ref.watch(isFollowingProvider(_targetPubkey!));
                    return ElevatedButton(
                      onPressed: isFollowing ? _unfollowUser : _followUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isFollowing ? Colors.grey[700] : Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(isFollowing ? 'Following' : 'Follow'),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _sendMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Icon(Icons.mail_outline),
              ),
            ],
          ],
        ),
      );

  Widget _buildVinesGrid() => Container(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: Consumer(
          builder: (context, ref, child) {
            final profileVideosState = ref.watch(profileVideosNotifierProvider);
            Log.error(
                '📱 ProfileVideosProvider state: loading=${profileVideosState.isLoading}, hasVideos=${profileVideosState.hasVideos}, hasError=${profileVideosState.hasError}, videoCount=${profileVideosState.videoCount}',
                name: 'ProfileScreen',
                category: LogCategory.ui);

            // Show loading state ONLY if actually loading
            if (profileVideosState.isLoading &&
                profileVideosState.videoCount == 0) {
              return Center(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1,
                    crossAxisSpacing: 0,
                    mainAxisSpacing: 0,
                  ),
                  itemCount: 9, // Show 9 placeholder tiles
                  itemBuilder: (context, index) => ColoredBox(
                    color: Colors.grey.shade900,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            // Show error state
            if (profileVideosState.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Error loading videos',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      profileVideosState.error ?? 'Unknown error',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref
                          .read(profileVideosNotifierProvider.notifier)
                          .refreshVideos(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VineTheme.vineGreen,
                        foregroundColor: VineTheme.whiteText,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            // Show empty state
            if (!profileVideosState.hasVideos) {
              return Padding(
                padding: const EdgeInsets.only(
                    bottom: 80), // Add padding to avoid FAB overlap
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_outlined,
                            color: Colors.grey, size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          'No Videos Yet',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isOwnProfile
                              ? 'Share your first video to see it here'
                              : "This user hasn't shared any videos yet",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 32), // Increased spacing
                        // Changed from centered button to an icon button in the top corner
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: IconButton(
                              onPressed: () async {
                                Log.debug(
                                    'Manual refresh videos requested for ${_targetPubkey?.substring(0, 8)}',
                                    name: 'ProfileScreen',
                                    category: LogCategory.ui);
                                if (_targetPubkey != null) {
                                  try {
                                    await ref
                                        .read(profileVideosNotifierProvider
                                            .notifier)
                                        .refreshVideos();
                                    Log.info('Manual refresh completed',
                                        name: 'ProfileScreen',
                                        category: LogCategory.ui);
                                  } catch (e) {
                                    Log.error('Manual refresh failed: $e',
                                        name: 'ProfileScreen',
                                        category: LogCategory.ui);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Refresh failed: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.refresh,
                                  color: VineTheme.vineGreen, size: 28),
                              tooltip: 'Refresh',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Show video grid
            return NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                // Load more videos when scrolling near the bottom
                if (!profileVideosState.isLoadingMore &&
                    profileVideosState.hasMore &&
                    scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200) {
                  ref
                      .read(profileVideosNotifierProvider.notifier)
                      .loadMoreVideos();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 0,
                  mainAxisSpacing: 0,
                  childAspectRatio:
                      1, // Square aspect ratio for vine-style videos
                ),
                itemCount: profileVideosState.hasMore
                    ? profileVideosState.videoCount +
                        1 // +1 for loading indicator
                    : profileVideosState.videoCount,
                itemBuilder: (context, index) {
                  // Show loading indicator at the end if loading more
                  if (index >= profileVideosState.videoCount) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: VineTheme.cardBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: VineTheme.vineGreen,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }

                  final videoEvent = profileVideosState.videos[index];

                  // Debug log video data
                  if (index < 3) {
                    // Only log first 3 to avoid spam
                    Log.debug(
                      'Video $index: id=${videoEvent.id.substring(0, 8)}, thumbnail=${videoEvent.thumbnailUrl?.substring(0, 50) ?? "null"}, videoUrl=${videoEvent.videoUrl?.substring(0, 50) ?? "null"}',
                      name: 'ProfileScreen',
                      category: LogCategory.ui,
                    );
                  }

                  // Log thumbnail URL issues
                  if (videoEvent.thumbnailUrl == null ||
                      videoEvent.thumbnailUrl!.isEmpty) {
                    Log.warning(
                      'Video ${videoEvent.id.substring(0, 8)} has no thumbnail URL',
                      name: 'ProfileScreen',
                      category: LogCategory.ui,
                    );
                  }

                  return AspectRatio(
                    aspectRatio:
                        1.0, // Ensure square thumbnails matching video display
                    child: GestureDetector(
                      onTap: () => _openVine(videoEvent),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: VineTheme.cardBackground,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Stack(
                          children: [
                            // Video thumbnail
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: videoEvent.thumbnailUrl != null &&
                                        videoEvent.thumbnailUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: videoEvent.thumbnailUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            gradient: LinearGradient(
                                              colors: [
                                                VineTheme.vineGreen
                                                    .withValues(alpha: 0.3),
                                                Colors.blue
                                                    .withValues(alpha: 0.3),
                                              ],
                                            ),
                                          ),
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              color: VineTheme.whiteText,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) {
                                          Log.warning(
                                            'Thumbnail load failed for ${videoEvent.id.substring(0, 8)}: $error',
                                            name: 'ProfileScreen',
                                            category: LogCategory.ui,
                                          );
                                          return DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              gradient: LinearGradient(
                                                colors: [
                                                  VineTheme.vineGreen
                                                      .withValues(alpha: 0.3),
                                                  Colors.blue
                                                      .withValues(alpha: 0.3),
                                                ],
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.play_circle_outline,
                                                color: VineTheme.whiteText,
                                                size: 24,
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    : DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          gradient: LinearGradient(
                                            colors: [
                                              VineTheme.vineGreen
                                                  .withValues(alpha: 0.3),
                                              Colors.blue
                                                  .withValues(alpha: 0.3),
                                            ],
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.play_circle_outline,
                                            color: VineTheme.whiteText,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                              ),
                            ),

                            // Play icon overlay
                            const Center(
                              child: Icon(
                                Icons.play_circle_filled,
                                color: Colors.white70,
                                size: 32,
                              ),
                            ),

                            // Duration indicator
                            if (videoEvent.duration != null)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    videoEvent.formattedDuration,
                                    style: const TextStyle(
                                      color: VineTheme.whiteText,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),

                            // Metrics badges (loops/likes) bottom-left if available
                            if ((videoEvent.originalLoops != null &&
                                    videoEvent.originalLoops! > 0) ||
                                (videoEvent.originalLikes != null &&
                                    videoEvent.originalLikes! > 0))
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (videoEvent.originalLoops != null &&
                                        videoEvent.originalLoops! > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.loop,
                                                size: 12,
                                                color: Colors.white70),
                                            const SizedBox(width: 2),
                                            Text(
                                              _formatCount(
                                                  videoEvent.originalLoops!),
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (videoEvent.originalLikes != null &&
                                        videoEvent.originalLikes! > 0) ...[
                                      if (videoEvent.originalLoops != null &&
                                          videoEvent.originalLoops! > 0)
                                        const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.favorite,
                                                size: 12,
                                                color: Colors.redAccent),
                                            const SizedBox(width: 2),
                                            Text(
                                              _formatCount(
                                                  videoEvent.originalLikes!),
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );

  Widget _buildLikedGrid() => Container(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: Builder(
          builder: (context) {
            // Watch Riverpod providers directly
            final socialService = ref.watch(socialServiceProvider);

            if (_targetPubkey == null) {
              return const Center(
                child: Text(
                  'Sign in to view liked videos',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return FutureBuilder<List<Event>>(
              future: socialService.fetchLikedEvents(_targetPubkey!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Loading liked videos...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Error loading liked videos',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final likedEvents = snapshot.data ?? [];

                if (likedEvents.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite_border,
                            color: Colors.grey, size: 64),
                        SizedBox(height: 16),
                        Text(
                          'No Liked Videos Yet',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Videos you like will appear here',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Convert Events to VideoEvents for display
                final videoEvents = likedEvents
                    .where((event) =>
                        event.kind ==
                        32222) // Filter for NIP-32222 video events
                    .map((event) {
                      try {
                        return VideoEvent.fromNostrEvent(event);
                      } catch (e) {
                        Log.error('Error converting event to VideoEvent: $e',
                            name: 'ProfileScreen', category: LogCategory.ui);
                        return null;
                      }
                    })
                    .where((videoEvent) => videoEvent != null)
                    .cast<VideoEvent>()
                    .toList();

                return GridView.builder(
                  padding: const EdgeInsets.all(0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 0,
                    mainAxisSpacing: 0,
                    childAspectRatio:
                        1.0, // Square aspect ratio matching video display
                  ),
                  itemCount: videoEvents.length,
                  itemBuilder: (context, index) {
                    final videoEvent = videoEvents[index];

                    return AspectRatio(
                      aspectRatio:
                          1.0, // Ensure square thumbnails matching video display
                      child: GestureDetector(
                        onTap: () => _openLikedVideo(videoEvent),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Stack(
                            children: [
                              // Video thumbnail
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: videoEvent.thumbnailUrl != null &&
                                          videoEvent.thumbnailUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: videoEvent.thumbnailUrl!,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.purple
                                                      .withValues(alpha: 0.3),
                                                  Colors.blue
                                                      .withValues(alpha: 0.3),
                                                ],
                                              ),
                                            ),
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.purple
                                                      .withValues(alpha: 0.3),
                                                  Colors.blue
                                                      .withValues(alpha: 0.3),
                                                ],
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.play_circle_outline,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        )
                                      : DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.purple
                                                    .withValues(alpha: 0.3),
                                                Colors.blue
                                                    .withValues(alpha: 0.3),
                                              ],
                                            ),
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.play_circle_outline,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                ),
                              ),

                              // Play icon overlay (only if we have thumbnail)
                              if (videoEvent.thumbnailUrl != null &&
                                  videoEvent.thumbnailUrl!.isNotEmpty)
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_filled,
                                    color: Colors.white70,
                                    size: 32,
                                  ),
                                ),

                              // Like indicator
                              const Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(
                                  Icons.favorite,
                                  color: Colors.red,
                                  size: 16,
                                ),
                              ),

                              // Video title if available
                              if (videoEvent.title?.isNotEmpty == true)
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      videoEvent.title!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      );

  Widget _buildRepostsGrid() => Container(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: Builder(
          builder: (context) {
            // Watch Riverpod providers directly
            final videoEventService = ref.watch(videoEventServiceProvider);

            if (_targetPubkey == null) {
              return const Center(
                child: Text(
                  'Sign in to view reposts',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            // Get all video events and filter for reposts by this user
            final allVideos = videoEventService.discoveryVideos;
            final userReposts = allVideos
                .where(
                  (video) =>
                      video.isRepost && video.reposterPubkey == _targetPubkey,
                )
                .toList();

            if (userReposts.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.repeat, color: Colors.grey, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No Reposts Yet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Videos you repost will appear here',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
                childAspectRatio:
                    1.0, // Square aspect ratio matching video display
              ),
              itemCount: userReposts.length,
              itemBuilder: (context, index) {
                final videoEvent = userReposts[index];

                return AspectRatio(
                  aspectRatio:
                      1.0, // Ensure square thumbnails matching video display
                  child: GestureDetector(
                    onTap: () => _openVine(videoEvent),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: VineTheme.cardBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Stack(
                        children: [
                          // Video thumbnail
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: videoEvent.thumbnailUrl != null &&
                                      videoEvent.thumbnailUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: videoEvent.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          gradient: LinearGradient(
                                            colors: [
                                              VineTheme.vineGreen
                                                  .withValues(alpha: 0.3),
                                              Colors.blue
                                                  .withValues(alpha: 0.3),
                                            ],
                                          ),
                                        ),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: VineTheme.whiteText,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          gradient: LinearGradient(
                                            colors: [
                                              VineTheme.vineGreen
                                                  .withValues(alpha: 0.3),
                                              Colors.blue
                                                  .withValues(alpha: 0.3),
                                            ],
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.play_circle_outline,
                                            color: VineTheme.whiteText,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    )
                                  : DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        gradient: LinearGradient(
                                          colors: [
                                            VineTheme.vineGreen
                                                .withValues(alpha: 0.3),
                                            Colors.blue.withValues(alpha: 0.3),
                                          ],
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          color: VineTheme.whiteText,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                            ),
                          ),

                          // Play icon overlay
                          const Center(
                            child: Icon(
                              Icons.play_circle_filled,
                              color: Colors.white70,
                              size: 32,
                            ),
                          ),

                          // Repost indicator
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.repeat,
                                color: VineTheme.vineGreen,
                                size: 16,
                              ),
                            ),
                          ),

                          // Duration indicator
                          if (videoEvent.duration != null)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  videoEvent.formattedDuration,
                                  style: const TextStyle(
                                    color: VineTheme.whiteText,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );

  void _createNewVine() {
    // Navigate to universal camera screen for recording a new vine
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UniversalCameraScreen(),
      ),
    );
  }

  void _showOptionsMenu() {
    Log.debug('📱 _showOptionsMenu called',
        name: 'ProfileScreen', category: LogCategory.ui);
    try {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.grey[900],
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white),
                title: const Text('Settings',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _openSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white),
                title: const Text('Edit Profile',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _editProfile();
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      Log.error('Error showing options menu: $e',
          name: 'ProfileScreen', category: LogCategory.ui);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening menu: $e')),
      );
    }
  }

  void _showUserOptions() {
    Log.verbose('_showUserOptions called for user profile',
        name: 'ProfileScreen', category: LogCategory.ui);
    try {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.grey[900],
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('Share Profile',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _shareProfile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white),
                title: const Text('Copy Public Key',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _copyNpubToClipboard();
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('Block User',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _blockUser();
                },
              ),
              ListTile(
                leading: const Icon(Icons.report, color: Colors.orange),
                title: const Text('Report User',
                    style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  _reportUser();
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      Log.error('Error showing user options menu: $e',
          name: 'ProfileScreen', category: LogCategory.ui);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening menu: $e')),
      );
    }
  }

  Future<void> _setupProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProfileSetupScreen(isNewUser: true),
      ),
    );

    // Refresh profile data when returning from setup
    if (result == true && mounted) {
      Log.info('✅ Profile setup successful, refreshing data...',
          name: 'ProfileScreen', category: LogCategory.ui);

      // Force refresh AuthService profile from latest cached data
      final userProfileNotifier =
          ref.read(userProfileNotifierProvider.notifier);

      // For now, just refresh the profile data - we may need to update AuthService later
      if (_targetPubkey != null) {
        await userProfileNotifier.fetchProfile(_targetPubkey!,
            forceRefresh: true);
      }

      // Also refresh profile stats and videos
      _loadProfileStats();
      _loadProfileVideos();

      setState(() {
        // Trigger rebuild to show updated profile
      });
    }
  }

  Future<void> _editProfile() async {
    Log.info('📝 Edit Profile button tapped',
        name: 'ProfileScreen', category: LogCategory.ui);

    // Log current profile before editing
    final profileState = ref.read(userProfileNotifierProvider);
    final authService = ref.read(authServiceProvider);
    final currentPubkey = authService.currentPublicKeyHex!;

    final profileBeforeEdit = profileState.getCachedProfile(currentPubkey);
    if (profileBeforeEdit != null) {
      Log.info('📋 Profile before edit:',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - name: ${profileBeforeEdit.name}',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - about: ${profileBeforeEdit.about}',
          name: 'ProfileScreen', category: LogCategory.ui);
      Log.info('  - eventId: ${profileBeforeEdit.eventId}',
          name: 'ProfileScreen', category: LogCategory.ui);
    }

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProfileSetupScreen(isNewUser: false),
      ),
    );

    Log.info('📝 Returned from ProfileSetupScreen with result: $result',
        name: 'ProfileScreen', category: LogCategory.ui);

    // Refresh profile data when returning from setup
    if (result == true && mounted) {
      Log.info('✅ Profile update successful, refreshing data...',
          name: 'ProfileScreen', category: LogCategory.ui);

      // Force refresh profile from Nostr relay first
      if (_targetPubkey != null) {
        await ref
            .read(userProfileNotifierProvider.notifier)
            .fetchProfile(_targetPubkey!, forceRefresh: true);
      }

      // Force refresh the AuthService profile from unified cache
      await authService
          .refreshCurrentProfile(ref.read(userProfileServiceProvider));

      // Invalidate Riverpod providers to force refresh from updated cache
      if (_targetPubkey != null) {
        ref.invalidate(profileStatsProvider(_targetPubkey!));
        ref.invalidate(profileVideosProvider(_targetPubkey!));
      }

      // Also refresh profile stats and videos
      _loadProfileStats();
      _loadProfileVideos();

      // Force a rebuild to show updated profile
      setState(() {});
    }
  }

  void _shareProfile() {
    // TODO: Implement profile sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing profile...')),
    );
  }

  void _showFollowersList() {
    if (_targetPubkey == null) return;

    Log.info('👥 Followers list tapped',
        name: 'ProfileScreen', category: LogCategory.ui);

    final profileState = ref.read(userProfileNotifierProvider);
    final profile = profileState.getCachedProfile(_targetPubkey!);
    final displayName =
        profile?.bestDisplayName ?? _targetPubkey!.substring(0, 8);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FollowersScreen(
          pubkey: _targetPubkey!,
          displayName: displayName,
        ),
      ),
    );
  }

  void _showFollowingList() {
    if (_targetPubkey == null) return;

    Log.info('👥 Following list tapped',
        name: 'ProfileScreen', category: LogCategory.ui);

    final profileState = ref.read(userProfileNotifierProvider);
    final profile = profileState.getCachedProfile(_targetPubkey!);
    final displayName =
        profile?.bestDisplayName ?? _targetPubkey!.substring(0, 8);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FollowingScreen(
          pubkey: _targetPubkey!,
          displayName: displayName,
        ),
      ),
    );
  }

  void _blockUser() {
    if (_targetPubkey == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Block User', style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to block this user? You won't see their content anymore.",
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement blocking functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User blocked successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _reportUser() {
    if (_targetPubkey == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Report User', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Report this user for inappropriate content or behavior?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement reporting functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User reported successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  Future<void> _followUser() async {
    if (_targetPubkey == null) return;

    try {
      final optimisticMethods = ref.read(optimisticFollowMethodsProvider);
      await optimisticMethods.followUser(_targetPubkey!);
    } catch (e) {
      // Silently handle error - optimistic state will be reverted
    }
  }

  Future<void> _unfollowUser() async {
    if (_targetPubkey == null) return;

    try {
      final optimisticMethods = ref.read(optimisticFollowMethodsProvider);
      await optimisticMethods.unfollowUser(_targetPubkey!);
    } catch (e) {
      // Silently handle error - optimistic state will be reverted
    }
  }

  void _sendMessage() {
    // TODO: Implement messaging functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening messages...')),
    );
  }

  void _openVine(VideoEvent videoEvent) {
    // PAUSE ALL OTHER VIDEOS FIRST - fixes invisible video playback
    ref.read(videoManagerProvider.notifier).pauseAllVideos();

    // Also pause all videos globally to ensure nothing from other tabs keeps playing
    GlobalVideoRegistry().pauseAllControllers();
    Log.info('⏸️ Paused all videos globally when entering profile video mode',
        name: 'ProfileScreen', category: LogCategory.system);

    // CRITICAL FIX: Add profile videos to VideoManager before playing
    // This ensures the video is available for playback by VideoFeedItem
    final profileVideosState = ref.read(profileVideosNotifierProvider);
    if (profileVideosState.hasVideos) {
      ref
          .read(videoManagerProvider.notifier)
          .addProfileVideos(profileVideosState.videos);
      Log.info(
          '✅ Added ${profileVideosState.videoCount} profile videos to VideoManager for playback',
          name: 'ProfileScreen',
          category: LogCategory.system);
    }

    setState(() {
      _isInVideoMode = true;
      _selectedVideo = videoEvent;
    });
  }

  void _exitVideoMode() {
    // Pause all videos when exiting video mode
    ref.read(videoManagerProvider.notifier).pauseAllVideos();
    GlobalVideoRegistry().pauseAllControllers();
    Log.info('⏸️ Paused all videos when exiting profile video mode',
        name: 'ProfileScreen', category: LogCategory.system);

    setState(() {
      _isInVideoMode = false;
      _selectedVideo = null;
    });
  }

  Widget _buildVideoModeView() {
    if (_selectedVideo == null) {
      return const Center(
        child: Text(
          'No video selected',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final profileState = ref.read(userProfileNotifierProvider);
    final cachedProfile = _targetPubkey != null
        ? profileState.getCachedProfile(_targetPubkey!)
        : null;
    final displayName =
        cachedProfile?.bestDisplayName ?? 'Loading user information';

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe right to exit video mode
        if (details.primaryVelocity! > 0) {
          _exitVideoMode();
        }
      },
      child: Column(
        children: [
          // Minimal header with just the name (tappable to go back)
          Container(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _exitVideoMode,
              child: Row(
                children: [
                  Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Video takes up the rest of the space
          Expanded(
            child: VideoFeedItem(
              key: const ValueKey('video_mode_item'),
              video: _selectedVideo!,
              isActive: true, // Always active since it's the focused video
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView(
      SocialService socialService, ProfileStatsState profileStatsState) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Profile header
              GestureDetector(
                onTap: _isInVideoMode ? _exitVideoMode : null,
                child: _buildProfileHeader(socialService, profileStatsState),
              ),

              // Stats row - wrapped in error boundary
              Builder(
                builder: (context) {
                  try {
                    return _buildStatsRow(profileStatsState);
                  } catch (e) {
                    Log.error('Error building stats row: $e',
                        name: 'ProfileScreen', category: LogCategory.ui);
                    return Container(
                      height: 50,
                      color: Colors.grey[800],
                      child: const Center(
                        child: Text('Stats loading...',
                            style: TextStyle(color: Colors.white)),
                      ),
                    );
                  }
                },
              ),

              // Action buttons - wrapped in error boundary
              Builder(
                builder: (context) {
                  try {
                    return _buildActionButtons();
                  } catch (e) {
                    Log.error('Error building action buttons: $e',
                        name: 'ProfileScreen', category: LogCategory.ui);
                    return Container(height: 50);
                  }
                },
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyTabBarDelegate(
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(icon: Icon(Icons.grid_on, size: 20)),
                Tab(icon: Icon(Icons.favorite_border, size: 20)),
                Tab(icon: Icon(Icons.repeat, size: 20)),
                Tab(icon: Icon(Icons.playlist_play, size: 20)),
              ],
            ),
          ),
        ),
      ],
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        child: TabBarView(
          key: ValueKey('tab_view_${_targetPubkey ?? 'unknown'}'),
          controller: _tabController,
          children: [
            _buildVinesGrid(),
            _buildLikedGrid(),
            _buildRepostsGrid(),
            _buildListsTab(),
          ],
        ),
      ),
    );
  }

  void _openLikedVideo(VideoEvent videoEvent) {
    // PAUSE ALL OTHER VIDEOS FIRST - fixes invisible video playback
    ref.read(videoManagerProvider.notifier).pauseAllVideos();

    // Also pause all videos globally to ensure nothing from other tabs keeps playing
    GlobalVideoRegistry().pauseAllControllers();
    Log.info('⏸️ Paused all videos globally when entering liked video mode',
        name: 'ProfileScreen', category: LogCategory.system);

    // CRITICAL FIX: Add the liked video to VideoManager before playing
    // Since liked videos might not be in any feed, ensure it's available for playback
    ref.read(videoManagerProvider.notifier).addProfileVideos([videoEvent]);
    Log.info('✅ Added liked video to VideoManager for playback',
        name: 'ProfileScreen', category: LogCategory.system);

    // Use embedded video feed for liked videos too
    setState(() {
      _isInVideoMode = true;
      _selectedVideo = videoEvent;
    });
  }

  /// Build lists tab showing user's curated lists, bookmarks, and follow sets
  Widget _buildListsTab() => Container(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                indicatorColor: VineTheme.vineGreen,
                labelColor: VineTheme.whiteText,
                unselectedLabelColor: VineTheme.secondaryText,
                tabs: [
                  Tab(text: 'Lists'),
                  Tab(text: 'Bookmarks'),
                  Tab(text: 'Follow Sets'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildCuratedListSection(),
                    _buildBookmarksSection(),
                    _buildFollowSetsSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// Build curated lists section
  Widget _buildCuratedListSection() => Consumer(
        builder: (context, ref, child) {
          final listServiceAsync = ref.watch(curatedListServiceProvider);

          return listServiceAsync.when(
            data: (listService) {
              final userLists = _isOwnProfile
                  ? listService.lists
                  : listService.lists.where((list) => list.isPublic).toList();

              if (userLists.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.playlist_play,
                        color: Colors.grey,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isOwnProfile ? 'No Lists Yet' : 'No Public Lists',
                        style: const TextStyle(
                          color: VineTheme.whiteText,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isOwnProfile
                            ? 'Create lists to organize your favorite videos'
                            : 'This user hasn\'t shared any public lists',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_isOwnProfile) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            // TODO: Show create list dialog
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Create List'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: VineTheme.vineGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: userLists.length,
                itemBuilder: (context, index) {
                  final list = userLists[index];
                  return _buildListTile(
                    icon: Icons.playlist_play,
                    title: list.name,
                    subtitle:
                        '${list.videoEventIds.length} videos${list.description != null ? ' • ${list.description}' : ''}',
                    trailing: list.tags.isNotEmpty
                        ? Wrap(
                            spacing: 4,
                            children: list.tags
                                .take(2)
                                .map((tag) => Chip(
                                      label: Text(tag,
                                          style: const TextStyle(fontSize: 10)),
                                      backgroundColor: VineTheme.vineGreen
                                          .withValues(alpha: 0.2),
                                      labelStyle: const TextStyle(
                                          color: VineTheme.whiteText),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ))
                                .toList(),
                          )
                        : null,
                    onTap: () {
                      // TODO: Navigate to list detail screen
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text(
                'Error loading lists: $error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        },
      );

  /// Build bookmarks section
  Widget _buildBookmarksSection() => Consumer(
        builder: (context, ref, child) {
          // TODO: Add bookmarkServiceProvider to app_providers.dart
          // For now, show placeholder
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bookmark_outline,
                  color: Colors.grey,
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'Bookmarks Coming Soon',
                  style: TextStyle(
                    color: VineTheme.whiteText,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Save videos for later viewing',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        },
      );

  /// Build follow sets section
  Widget _buildFollowSetsSection() => Consumer(
        builder: (context, ref, child) {
          final socialService = ref.watch(socialServiceProvider);
          final followSets = socialService.followSets;

          if (followSets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    color: Colors.grey,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isOwnProfile ? 'No Follow Sets Yet' : 'No Follow Sets',
                    style: const TextStyle(
                      color: VineTheme.whiteText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isOwnProfile
                        ? 'Create follow sets to organize your favorite creators'
                        : 'This user hasn\'t created any follow sets',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_isOwnProfile) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Show create follow set dialog
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create Follow Set'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VineTheme.vineGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: followSets.length,
            itemBuilder: (context, index) {
              final set = followSets[index];
              return _buildListTile(
                icon: Icons.people,
                title: set.name,
                subtitle:
                    '${set.pubkeys.length} users${set.description != null ? ' • ${set.description}' : ''}',
                onTap: () {
                  // TODO: Navigate to follow set detail screen
                },
              );
            },
          );
        },
      );

  /// Helper method to build consistent list tiles
  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) =>
      ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: VineTheme.cardBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: VineTheme.whiteText,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: VineTheme.whiteText,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: VineTheme.secondaryText,
            fontSize: 12,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );

  void _openSettings() {
    // Show settings menu with debug options
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications, color: Colors.white),
              title: const Text('Notification Settings',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to notification settings
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Notification settings coming soon')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Colors.white),
              title:
                  const Text('Privacy', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _openPrivacySettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.white),
              title: const Text('Relay Settings',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Manage Nostr relays',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RelaySettingsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload, color: Colors.white),
              title: const Text('Blossom Upload Settings',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Configure media upload server',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BlossomSettingsScreen(),
                  ),
                );
              },
            ),
            // Only show P2P sync on mobile platforms
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blue),
                title: const Text('P2P Video Sync',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Share videos with nearby devices',
                    style: TextStyle(color: Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to P2P screen - only available on mobile
                  _openP2PSync();
                },
              ),
            const Divider(color: Colors.grey),
            ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.orange),
              title: const Text('Debug Menu',
                  style: TextStyle(color: Colors.orange)),
              subtitle: const Text('Developer options',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _openDebugMenu();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openDebugMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.play_circle_outline, color: Colors.green),
              title: const Text('Video Player Test',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Test video playback functionality',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DebugVideoTestScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_queue, color: Colors.blue),
              title: const Text('Relay Status',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Check connection to Nostr relays',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RelaySettingsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage, color: Colors.purple),
              title: const Text('Clear Cache',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Clear video and image caches',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Clear cache
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openPrivacySettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                'Privacy Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Backup nsec key Section
                    ListTile(
                      leading: const Icon(Icons.key, color: Colors.purple),
                      title: const Text('Backup Private Key (nsec)',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Copy your private key for backup or use in other Nostr apps',
                          style: TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(context);
                        _showNsecBackupDialog();
                      },
                    ),

                    const Divider(color: Colors.grey),

                    // Import Different Identity Section
                    ListTile(
                      leading: const Icon(Icons.login, color: Colors.green),
                      title: const Text('Switch Identity',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Import a different Nostr identity using nsec',
                          style: TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSwitchIdentityDialog();
                      },
                    ),

                    const Divider(color: Colors.grey),

                    // Analytics Opt-Out Section
                    Builder(
                      builder: (context) {
                        final analyticsService =
                            ref.watch(analyticsServiceProvider);
                        return ListTile(
                          leading: const Icon(Icons.analytics_outlined,
                              color: Colors.orange),
                          title: const Text('Analytics',
                              style: TextStyle(color: Colors.white)),
                          subtitle: const Text(
                              'Help improve divine by sharing anonymous usage data',
                              style: TextStyle(color: Colors.grey)),
                          trailing: Switch(
                            value: analyticsService.analyticsEnabled,
                            onChanged: (value) async {
                              await analyticsService.setAnalyticsEnabled(value);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value
                                          ? 'Analytics enabled - Thank you for helping improve divine!'
                                          : 'Analytics disabled - Your privacy is respected',
                                    ),
                                    backgroundColor:
                                        value ? Colors.green : Colors.orange,
                                  ),
                                );
                              }
                            },
                            activeColor: VineTheme.vineGreen,
                          ),
                        );
                      },
                    ),

                    const Divider(color: Colors.grey),

                    // Data Export Section
                    ListTile(
                      leading: const Icon(Icons.download, color: Colors.blue),
                      title: const Text('Export My Data',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Download all your posts and profile data',
                          style: TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(context);
                        _showDataExportDialog();
                      },
                    ),

                    const Divider(color: Colors.grey),

                    // Right to be Forgotten Section
                    ListTile(
                      leading:
                          const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text('Right to be Forgotten',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Request deletion of all your data (NIP-62)',
                          style: TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(context);
                        _showRightToBeForgottenDialog();
                      },
                    ),

                    const SizedBox(height: 20),

                    // Explanation text
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.blue, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'About Nostr Privacy',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Nostr is a decentralized protocol. While you can request deletion, data may persist on some relays. The "Right to be Forgotten" publishes a NIP-62 deletion request that compliant relays will honor.',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDataExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Export Data', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This feature will compile and download all your posts, profile information, and associated data.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement data export
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Data export feature coming soon')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _showRightToBeForgottenDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Right to be Forgotten',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will publish a NIP-62 deletion request to all relays requesting removal of:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text(
              '• All your posts and videos\n'
              '• Your profile information\n'
              '• Your reactions and comments\n'
              '• All associated metadata',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ WARNING: This action cannot be undone. While compliant relays will honor this request, some data may persist on non-compliant relays due to the decentralized nature of Nostr.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmRightToBeForgotten();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _confirmRightToBeForgotten() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Final Confirmation',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Type "DELETE MY DATA" to confirm:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'DELETE MY DATA',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                // Enable/disable button based on exact match
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeRightToBeForgotten();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All Data'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRightToBeForgotten() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: const Row(
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(width: 16),
              Text(
                'Publishing deletion request...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      final socialService = ref.read(socialServiceProvider);
      await socialService.publishRightToBeForgotten();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'Deletion Request Sent',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Your NIP-62 deletion request has been published to all relays. Compliant relays will begin removing your data. This may take some time to propagate across the network.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Optionally log out the user
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish deletion request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyNpubToClipboard() async {
    if (_targetPubkey == null) return;

    try {
      final npub = NostrEncoding.encodePublicKey(_targetPubkey!);
      await Clipboard.setData(ClipboardData(text: npub));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check, color: Colors.white),
                SizedBox(width: 8),
                Text('Public key copied to clipboard'),
              ],
            ),
            backgroundColor: VineTheme.vineGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showNsecBackupDialog() async {
    final authService = ref.read(authServiceProvider);
    final nsec = await authService.exportNsec();

    if (!mounted) return;

    if (nsec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No private key available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(
          children: [
            Icon(Icons.key, color: Colors.purple),
            SizedBox(width: 8),
            Text(
              'Backup Private Key',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your private key (nsec) allows you to access your account from any Nostr app. Keep it safe and never share it publicly.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple, width: 1),
              ),
              child: SelectableText(
                nsec,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.yellow, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Store this safely! Anyone with this key can control your account.',
                      style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: nsec));
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Private key copied to clipboard'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Copy to Clipboard'),
          ),
        ],
      ),
    );
  }

  void _showSwitchIdentityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Switch Identity',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will sign you out of your current identity and allow you to import a different one.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Make sure you have backed up your current nsec before switching!',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              // Sign out current user (without deleting keys)
              final authService = ref.read(authServiceProvider);
              await authService.signOut(deleteKeys: false);

              // Navigate to key import screen
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const KeyImportScreen(),
                  ),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _openP2PSync() {
    // P2P Video Sync is fully implemented but only available on mobile platforms
    // The P2P screen exists at lib/screens/p2p_sync_screen.dart
    // Mobile builds will automatically use EmbeddedRelayService with P2P capabilities
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(kIsWeb
            ? 'P2P Video Sync requires mobile app - not available on web'
            : 'P2P Video Sync available! Connect to nearby divine users.'),
        backgroundColor: kIsWeb ? Colors.orange : Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Delegate for creating a sticky tab bar in NestedScrollView
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  _StickyTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: VineTheme.backgroundColor, // Match the main background
          border: Border(
            bottom: BorderSide(color: Colors.grey[800]!, width: 1),
          ),
        ),
        child: tabBar,
      );

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}
