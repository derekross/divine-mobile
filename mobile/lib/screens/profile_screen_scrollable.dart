// ABOUTME: Instagram-style scrollable profile screen implementation
// ABOUTME: Uses CustomScrollView with slivers for smooth scrolling experience

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/widgets/user_avatar.dart';
import 'package:openvine/providers/profile_stats_provider.dart';
import 'package:openvine/providers/profile_videos_provider.dart';
import 'package:openvine/screens/pure/universal_camera_screen_pure.dart';
import 'package:openvine/screens/settings_screen.dart';
import 'package:openvine/screens/vine_drafts_screen.dart';
import 'package:openvine/screens/profile_setup_screen.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/social_service.dart';
import 'package:openvine/services/user_profile_service.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/nostr_encoding.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/utils/string_utils.dart';
import 'package:openvine/screens/pure/explore_video_screen_pure.dart';
import 'package:openvine/helpers/follow_actions_helper.dart';
import 'package:share_plus/share_plus.dart';

class ProfileScreenScrollable extends ConsumerStatefulWidget {
  const ProfileScreenScrollable({super.key, this.profilePubkey});
  final String? profilePubkey;

  @override
  ConsumerState<ProfileScreenScrollable> createState() =>
      _ProfileScreenScrollableState();
}

class _ProfileScreenScrollableState
    extends ConsumerState<ProfileScreenScrollable>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isOwnProfile = true;
  String? _targetPubkey;
  bool _isInitializing = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProfile();
    });
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

    setState(() {
      _targetPubkey = widget.profilePubkey ?? currentUserPubkey;
      _isOwnProfile = _targetPubkey == currentUserPubkey;
      _isInitializing = false;
    });

    if (_targetPubkey != null) {
      _loadProfileStats();
      _loadProfileVideos();

      if (!_isOwnProfile) {
        _loadUserProfile();
      }
    }
  }

  void _loadProfileStats() {
    if (_targetPubkey == null) return;
    ref.read(profileStatsProvider.notifier).loadStats(_targetPubkey!);
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
      ref
          .read(profileVideosProvider.notifier)
          .loadVideosForUser(_targetPubkey!)
          .then((_) {
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

  void _loadUserProfile() {
    if (_targetPubkey == null) return;
    final userProfileService = ref.read(userProfileServiceProvider);

    // Only fetch if not already cached - show cached data immediately
    if (!userProfileService.hasProfile(_targetPubkey!)) {
      Log.debug(
          '📥 Fetching uncached profile: ${_targetPubkey!.substring(0, 8)}',
          name: 'ProfileScreenScrollable',
          category: LogCategory.ui);
      userProfileService.fetchProfile(_targetPubkey!);
    } else {
      Log.debug('📋 Using cached profile: ${_targetPubkey!.substring(0, 8)}',
          name: 'ProfileScreenScrollable', category: LogCategory.ui);
      // Still call fetchProfile to trigger background refresh if needed
      userProfileService.fetchProfile(_targetPubkey!);
    }
  }

  @override
  void didUpdateWidget(ProfileScreenScrollable oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if the profilePubkey parameter has changed
    if (widget.profilePubkey != oldWidget.profilePubkey) {
      Log.debug(
          'Profile parameter changed from ${oldWidget.profilePubkey?.substring(0, 8) ?? 'own'} to ${widget.profilePubkey?.substring(0, 8) ?? 'own'}',
          name: 'ProfileScreenScrollable',
          category: LogCategory.ui);

      // Set initializing state and reinitialize profile with new pubkey
      _isInitializing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeProfile();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen during initialization
    if (_isInitializing || _targetPubkey == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: VineTheme.vineGreen),
            SizedBox(height: 16),
            Text(
              'Loading Profile...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final authService = ref.watch(authServiceProvider);
    final userProfileService = ref.watch(userProfileServiceProvider);
    final socialService = ref.watch(socialServiceProvider);

    // Get the current user's pubkey for stats/videos
    final targetPubkey = _targetPubkey ?? authService.currentPublicKeyHex ?? '';
    final profileStatsAsync = ref.watch(fetchProfileStatsProvider(targetPubkey));
    final profileVideosAsync = ref.watch(fetchProfileVideosProvider(targetPubkey));

    final authProfile = _isOwnProfile ? authService.currentProfile : null;
    final cachedProfile = !_isOwnProfile
        ? userProfileService.getCachedProfile(_targetPubkey!)
        : null;
    final userName = authProfile?.displayName ??
        cachedProfile?.displayName ??
        'Loading user information';

    return Stack(
      children: [
        DefaultTabController(
          length: 3,
          child: NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              // Profile-specific header (no AppBar since we have a global one)
              SliverToBoxAdapter(
                child: Container(
                  color: VineTheme.vineGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
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
                      const Spacer(),
                      if (_isOwnProfile) ...[
                        IconButton(
                          icon: const Icon(Icons.add_box_outlined,
                              color: Colors.white),
                          onPressed: _createNewVine,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.menu,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: () {
                            Log.debug('📱 Hamburger menu tapped',
                                name: 'ProfileScreen',
                                category: LogCategory.ui);
                            _showOptionsMenu();
                          },
                        ),
                      ] else ...[
                        IconButton(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onPressed: _showUserOptions,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

                // Profile Header
                SliverToBoxAdapter(
                  child: _buildScrollableProfileHeader(
                      authService, userProfileService, profileStatsAsync),
                ),

                // Stats Row
                SliverToBoxAdapter(
                  child: _buildStatsRow(profileStatsAsync),
                ),

                // Action Buttons
                SliverToBoxAdapter(
                  child: _buildActionButtons(socialService),
                ),

                // Sticky Tab Bar
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
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
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildSliverVinesGrid(profileVideosAsync),
                  _buildSliverLikedGrid(socialService),
                  _buildSliverRepostsGrid(),
                ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollableProfileHeader(
    AuthService authService,
    UserProfileService userProfileService,
    AsyncValue<ProfileStats> profileStatsAsync,
  ) {
    final authProfile = _isOwnProfile ? authService.currentProfile : null;
    final cachedProfile = !_isOwnProfile
        ? userProfileService.getCachedProfile(_targetPubkey!)
        : null;

    final profilePictureUrl = authProfile?.picture ?? cachedProfile?.picture;
    final displayName = authProfile?.displayName ?? cachedProfile?.displayName;
    final hasCustomName = displayName != null &&
        !displayName.startsWith('npub1') &&
        displayName != 'Loading user information';

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

          // Profile picture and stats row
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
                      profileStatsAsync.hasValue
                          ? profileStatsAsync.value!.videoCount
                          : null,
                      'Vines',
                      profileStatsAsync.isLoading,
                    ),
                    _buildDynamicStatColumn(
                      profileStatsAsync.hasValue
                          ? profileStatsAsync.value!.followers
                          : null,
                      'Followers',
                      profileStatsAsync.isLoading,
                    ),
                    _buildDynamicStatColumn(
                      profileStatsAsync.hasValue
                          ? profileStatsAsync.value!.following
                          : null,
                      'Following',
                      profileStatsAsync.isLoading,
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
                      displayName ?? 'Loading user information',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    // Add NIP-05 verification badge if verified
                    if ((authProfile?.nip05 ?? cachedProfile?.nip05) != null &&
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

  Widget _buildSliverVinesGrid(
      AsyncValue<List<VideoEvent>> profileVideosAsync) {
    if (profileVideosAsync.isLoading &&
        (profileVideosAsync.value?.isEmpty ?? true)) {
      return const Center(
        child: CircularProgressIndicator(color: VineTheme.vineGreen),
      );
    }

    if (profileVideosAsync.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Error loading videos',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              profileVideosAsync.error?.toString() ?? 'Unknown error',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref
                  .read(profileVideosProvider.notifier)
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

    if (profileVideosAsync.value?.isEmpty ?? true) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_outlined, color: Colors.grey, size: 64),
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
            const SizedBox(height: 32),
            IconButton(
              onPressed: () async {
                Log.debug(
                    'Manual refresh videos requested for ${_targetPubkey?.substring(0, 8)}',
                    name: 'ProfileScreen',
                    category: LogCategory.ui);
                if (_targetPubkey != null) {
                  try {
                    await ref
                        .read(profileVideosProvider.notifier)
                        .refreshVideos();
                    Log.info('Manual refresh completed',
                        name: 'ProfileScreen', category: LogCategory.ui);
                  } catch (e) {
                    Log.error('Manual refresh failed: $e',
                        name: 'ProfileScreen', category: LogCategory.ui);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Refresh failed: $e')),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.refresh,
                  color: VineTheme.vineGreen, size: 28),
              tooltip: 'Refresh',
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= (profileVideosAsync.value?.length ?? 0)) {
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

                final videoEvent = profileVideosAsync.value?[index];
                if (videoEvent == null) {
                  // Show loading placeholder instead of empty Container
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
                return GestureDetector(
                  onTap: () {
                    final videos = profileVideosAsync.value ?? const <VideoEvent>[];

                    // Get profile information for context (reconstruct profile data)
                    final authSvc = ref.read(authServiceProvider);
                    final userProfileSvc = ref.read(userProfileServiceProvider);
                    final authProfile = _isOwnProfile ? authSvc.currentProfile : null;
                    final cachedProfile = !_isOwnProfile
                        ? userProfileSvc.getCachedProfile(_targetPubkey!)
                        : null;
                    final displayName = authProfile?.displayName ?? cachedProfile?.displayName ?? 'User';
                    final profileTitle = _isOwnProfile ? 'Your Videos' : '$displayName\'s Videos';

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(
                            backgroundColor: Colors.black,
                            leading: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            title: Text(
                              profileTitle,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                            actions: [
                              // Show profile icon to indicate we're viewing someone's profile
                              IconButton(
                                icon: const Icon(Icons.person, color: Colors.white),
                                onPressed: () {
                                  // Pop back to profile screen
                                  Navigator.of(context).pop();
                                },
                                tooltip: 'Back to Profile',
                              ),
                            ],
                          ),
                          body: ExploreVideoScreenPure(
                            startingVideo: videoEvent,
                            videoList: videos,
                            contextTitle: profileTitle,
                            startingIndex: index,
                          ),
                        ),
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: VineTheme.cardBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: videoEvent.thumbnailUrl != null &&
                                    videoEvent.thumbnailUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: videoEvent.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        gradient: LinearGradient(
                                          colors: [
                                            VineTheme.vineGreen.withValues(alpha: 0.3),
                                            Colors.blue.withValues(alpha: 0.3),
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
                                    errorWidget: (context, url, error) => DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        gradient: LinearGradient(
                                          colors: [
                                            VineTheme.vineGreen.withValues(alpha: 0.3),
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
                                  )
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      gradient: LinearGradient(
                                        colors: [
                                          VineTheme.vineGreen.withValues(alpha: 0.3),
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
                        const Center(
                          child: Icon(
                            Icons.play_circle_filled,
                            color: Colors.white70,
                            size: 32,
                          ),
                        ),
                        if (videoEvent.duration != null)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                );
                
              },
              childCount: profileVideosAsync.value?.length ?? 0,
            ),
          ),
        ),
        // Load more trigger
        // TODO: Implement load more with new AsyncValue pattern
      ],
    );
  }

  Widget _buildSliverLikedGrid(SocialService socialService) {
    // Placeholder for liked grid - implement similar to vines grid
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.favorite_border, color: Colors.grey, size: 64),
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
          ),
        ),
      ],
    );
  }

  Widget _buildSliverRepostsGrid() {
    // Placeholder for reposts grid - implement similar to vines grid
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
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
          ),
        ),
      ],
    );
  }

  // Helper methods (copied from original)
  Widget _buildDynamicStatColumn(int? count, String label, bool isLoading) =>
      Column(
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

  String _formatCount(int count) {
    return StringUtils.formatCompactNumber(count);
  }

  Widget _buildStatsRow(AsyncValue<ProfileStats> profileStatsAsync) =>
      Container(
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
                  child: profileStatsAsync.isLoading
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
                              profileStatsAsync.value?.totalViews ?? 0),
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
                  child: profileStatsAsync.isLoading
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
                              profileStatsAsync.value?.totalLikes ?? 0),
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

  Widget _buildActionButtons(SocialService socialService) => Padding(
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
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  key: const Key('drafts-button'),
                  onPressed: _openDrafts,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Drafts'),
                ),
              ),
              const SizedBox(width: 8),
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
                child: Builder(
                  builder: (context) {
                    final isFollowing =
                        socialService.isFollowing(_targetPubkey!);
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

  // All the action methods
  void _createNewVine() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UniversalCameraScreenPure(),
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings, color: VineTheme.vineGreen),
              title: const Text(
                'Settings',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: VineTheme.vineGreen),
              title: const Text(
                'Copy Public Key',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _copyNpubToClipboard();
              },
            ),
            if (_isOwnProfile)
              ListTile(
                leading:
                    const Icon(Icons.video_call, color: VineTheme.vineGreen),
                title: const Text(
                  'Record Video',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UniversalCameraScreenPure(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showUserOptions() {
    // Implementation from original file
  }

  Future<void> _setupProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileSetupScreen(isNewUser: true),
      ),
    );

    // Refresh profile after setup
    if (mounted) {
      _initializeProfile();
    }
  }

  Future<void> _editProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileSetupScreen(isNewUser: false),
      ),
    );

    // Refresh profile after editing
    if (mounted) {
      _initializeProfile();
    }
  }

  Future<void> _shareProfile() async {
    try {
      final pubkey = _targetPubkey;
      if (pubkey == null) {
        Log.warning('Cannot share profile: pubkey is null',
            name: 'ProfileScreen', category: LogCategory.ui);
        return;
      }

      // Get profile info for better share text
      final profile = await ref.read(userProfileServiceProvider).fetchProfile(pubkey);
      final displayName = profile?.displayName ?? 'User';

      // Convert hex pubkey to npub format for sharing
      final npub = NostrEncoding.encodePublicKey(pubkey);

      // Create share text with divine.video URL format
      final shareText = 'Check out $displayName on divine!\n\n'
          'https://divine.video/profile/$npub';

      // Use share_plus to show native share sheet
      final result = await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: '$displayName on divine',
        ),
      );

      if (result.status == ShareResultStatus.success) {
        Log.info('Profile shared successfully',
            name: 'ProfileScreen',
            category: LogCategory.ui);
      }
    } catch (e) {
      Log.error('Error sharing profile: $e',
          name: 'ProfileScreen',
          category: LogCategory.ui);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share profile: $e')),
        );
      }
    }
  }

  void _openDrafts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VineDraftsScreen(),
      ),
    );
  }

  Future<void> _followUser() async {
    if (_targetPubkey == null) return;

    await FollowActionsHelper.followUser(
      ref: ref,
      context: context,
      pubkey: _targetPubkey!,
      contextName: 'ProfileScreen',
    );
  }

  Future<void> _unfollowUser() async {
    if (_targetPubkey == null) return;

    await FollowActionsHelper.unfollowUser(
      ref: ref,
      context: context,
      pubkey: _targetPubkey!,
      contextName: 'ProfileScreen',
    );
  }

  void _sendMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening messages...')),
    );
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
}

// Custom delegate for sticky tab bar
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(
        color: VineTheme.backgroundColor,
        child: _tabBar,
      );

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
