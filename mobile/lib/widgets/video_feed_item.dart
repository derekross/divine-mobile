// ABOUTME: TDD-driven video feed item widget with all loading states and error handling
// ABOUTME: Supports GIF and video playback with memory-efficient lifecycle management

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostr_sdk/event.dart';
import 'package:openvine/main.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/models/video_state.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/services/curated_list_service.dart';
import 'package:openvine/providers/social_providers.dart' as social_providers;
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/screens/comments_screen.dart';
import 'package:openvine/services/global_video_registry.dart';
import 'package:openvine/screens/hashtag_feed_screen.dart';
import 'package:openvine/screens/profile_screen.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/clickable_hashtag_text.dart';
import 'package:openvine/widgets/share_video_menu.dart';
import 'package:openvine/widgets/video_metrics_tracker.dart';
import 'package:video_player/video_player.dart';
import 'package:openvine/providers/optimistic_follow_provider.dart';

/// Context enum to specify which tab the VideoFeedItem belongs to
enum TabContext { feed, explore }

/// Individual video item widget implementing TDD specifications
///
/// Key features:
/// - All loading states (loading, ready, error, disposed)
/// - GIF vs video handling
/// - Controller lifecycle management
/// - Error display and retry functionality
/// - Accessibility features
/// - Performance optimizations
class VideoFeedItem extends ConsumerStatefulWidget {
  const VideoFeedItem({
    required this.video,
    required this.isActive,
    super.key,
    this.onVideoError,
    this.tabContext = TabContext.feed,
    this.forceInfoBelow = false,
  });
  final VideoEvent video;
  final bool isActive;
  final Function(String)? onVideoError;
  final TabContext tabContext;
  final bool forceInfoBelow;

  @override
  ConsumerState<VideoFeedItem> createState() => _VideoFeedItemState();
}

class _VideoFeedItemState extends ConsumerState<VideoFeedItem>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _showPlayPauseIcon = false;
  bool _userPaused = false; // Track if user manually paused the video
  late AnimationController _iconAnimationController;

  // Loading state management
  Timer? _readinessCheckTimer;
  bool _isCheckingReadiness = false;
  bool _hasScheduledPostFrameCallback = false;

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _initializeVideoManager();
    _loadUserProfile();
    // DISABLED: Per-video reaction checks create too many relay subscriptions
    // _checkVideoReactions();

    // Handle initial activation state
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleActivationChange();
      });
    }
  }

  @override
  void didUpdateWidget(VideoFeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reset comment state when video changes
    if (widget.video.id != oldWidget.video.id) {
      Log.info(
          '🔄 Video changed from ${oldWidget.video.id.substring(0, 8)}... to ${widget.video.id.substring(0, 8)}... - resetting comment state',
          name: 'VideoFeedItem',
          category: LogCategory.ui);
      // DISABLED: Per-video reaction checks create too many relay subscriptions
      // Check reactions for the new video
      // _checkVideoReactions();
    }

    // Handle activation state changes OR video changes
    if (widget.isActive != oldWidget.isActive ||
        widget.video.id != oldWidget.video.id) {
      Log.info(
          '📱 Widget updated: isActive changed: ${widget.isActive != oldWidget.isActive}, video changed: ${widget.video.id != oldWidget.video.id}',
          name: 'VideoFeedItem',
          category: LogCategory.ui);
      _handleActivationChange();
    }
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _readinessCheckTimer?.cancel();

    // Don't dispose controller here - VideoManager handles lifecycle
    super.dispose();
  }

  void _initializeVideoManager() {
    // Trigger preload if video is active
    // Delay to avoid modifying provider during widget build phase
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          ref.read(videoManagerProvider.notifier).preloadVideo(widget.video.id);
        } catch (e) {
          Log.info(
              'VideoFeedItem: Video not ready for preload yet: ${widget.video.id}',
              name: 'VideoFeedItem',
              category: LogCategory.ui);
        }
      });
    }

    // Schedule controller update after current frame to ensure proper initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateController();
    });
  }

  void _loadUserProfile() {
    // Profile loading is now handled at the feed level with batch fetching
    // This method is kept for compatibility but no longer fetches individually
    Log.verbose(
      'Profile loading handled at feed level for ${widget.video.pubkey.substring(0, 8)}...',
      name: 'VideoFeedItem',
      category: LogCategory.ui,
    );
  }

  void _handleActivationChange() {
    Log.info(
      '🎯 _handleActivationChange called for ${widget.video.id.substring(0, 8)}... isActive: ${widget.isActive}',
      name: 'VideoFeedItem',
      category: LogCategory.ui,
    );

    // Only use isActive prop from parent (PageView index-based control)
    if (widget.isActive) {
      _userPaused = false; // Reset user pause flag when video becomes active
      // Preload video - Consumer<IVideoManager> will trigger _updateController via stream when ready
      // Delay to avoid modifying provider during widget build phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return; // Prevent operations on disposed widgets
        try {
          Log.info(
              '📥 Starting preload for ${widget.video.id.substring(0, 8)}...',
              name: 'VideoFeedItem',
              category: LogCategory.ui);
          ref.read(videoManagerProvider.notifier).preloadVideo(widget.video.id);
        } catch (e) {
          Log.info(
              'VideoFeedItem: Video not ready for preload yet: ${widget.video.id}',
              name: 'VideoFeedItem',
              category: LogCategory.ui);
        }
      });

      // IMPORTANT: Also check immediately after preload starts
      // The controller might already be ready from previous loads
      _updateController();

      // Auto-play if controller is already ready
      Log.info('🎮 Checking existing controller: ${_controller != null}',
          name: 'VideoFeedItem', category: LogCategory.ui);
      if (_controller != null) {
        Log.info(
            '🎮 Controller exists, isInitialized: ${_controller!.value.isInitialized}',
            name: 'VideoFeedItem',
            category: LogCategory.ui);
        if (_controller!.value.isInitialized) {
          Log.info('▶️ Controller ready, calling _playVideo immediately',
              name: 'VideoFeedItem', category: LogCategory.ui);
          _playVideo();
        } else {
          Log.info('⏳ Controller not initialized, adding listener',
              name: 'VideoFeedItem', category: LogCategory.ui);
          // Add listener to play when initialized - REFACTORED

          // REFACTORED: Service no longer extends ChangeNotifier - use Riverpod ref.watch instead
        }
      } else {
        Log.info(
            '❌ No controller available yet, starting periodic readiness check',
            name: 'VideoFeedItem',
            category: LogCategory.ui);
        _startReadinessCheck();
      }
    } else {
      // Video became inactive - pause and disable looping
      _pauseVideo();
      if (_controller != null) {
        _controller!.setLooping(false);
      }
      // Don't null the controller to prevent flashing in Chrome
      // Just keep it paused
      _stopReadinessCheck();
    }
  }

  void _startReadinessCheck() {
    // Cancel any existing timer
    _stopReadinessCheck();

    // Start checking every 100ms as user suggested
    _readinessCheckTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !widget.isActive) {
        _stopReadinessCheck();
        return;
      }

      // Check if video is now available in VideoManagerService
      if (!_isCheckingReadiness) {
        _isCheckingReadiness = true;

        try {
          // Try to preload again
          ref.read(videoManagerProvider.notifier).preloadVideo(widget.video.id);

          // Check if controller is now available
          final controller = ref
              .read(videoManagerProvider)
              .getPlayerController(widget.video.id);
          if (controller != null) {
            Log.info(
              '✅ Video ready after periodic check: ${widget.video.id.substring(0, 8)}...',
              name: 'VideoFeedItem',
              category: LogCategory.ui,
            );
            _stopReadinessCheck();
            _updateController();
          }
        } catch (e) {
          // Still not ready, continue checking
          Log.verbose(
            'Video still not ready: ${widget.video.id.substring(0, 8)}...',
            name: 'VideoFeedItem',
            category: LogCategory.ui,
          );
        } finally {
          _isCheckingReadiness = false;
        }
      }
    });
  }

  void _stopReadinessCheck() {
    _readinessCheckTimer?.cancel();
    _readinessCheckTimer = null;
  }

  void _updateController() {
    Log.info(
        '🔄 _updateController called for ${widget.video.id.substring(0, 8)}...',
        name: 'VideoFeedItem',
        category: LogCategory.ui);

    final managerState = ref.read(videoManagerProvider);
    final videoState = managerState.getVideoState(widget.video.id);
    final newController = managerState.getPlayerController(widget.video.id);

    Log.info(
        '📊 Current controller state: ${_controller?.value.isInitialized ?? "null"}',
        name: 'VideoFeedItem',
        category: LogCategory.ui);
    Log.info('📊 Video state: ${videoState?.loadingState}',
        name: 'VideoFeedItem', category: LogCategory.ui);
    Log.info('📊 New controller from VideoManager: ${newController != null}',
        name: 'VideoFeedItem', category: LogCategory.ui);

    // Only update controller if we don't have one or if the new one is better
    if (_controller == null ||
        (newController != null && newController != _controller)) {
      Log.info(
          '🔄 Controller changed! Old: ${_controller != null}, New: ${newController != null}',
          name: 'VideoFeedItem',
          category: LogCategory.ui);
      setState(() {
        // Unregister old controller if it exists
        if (_controller != null) {
          GlobalVideoRegistry().unregisterController(_controller!);
        }

        _controller = newController;

        // Register new controller with global video registry
        if (_controller != null) {
          GlobalVideoRegistry().registerController(_controller!);
        }
      });

      // Auto-play video when controller becomes available and video is active
      if (newController != null && widget.isActive) {
        Log.info('🎬 New controller available and widget is active',
            name: 'VideoFeedItem', category: LogCategory.ui);
        // Check if already initialized
        if (newController.value.isInitialized) {
          Log.info('✅ Controller already initialized, calling _playVideo',
              name: 'VideoFeedItem', category: LogCategory.ui);
          _playVideo();
        } else {
          Log.info('⏳ Controller not yet initialized, adding listener',
              name: 'VideoFeedItem', category: LogCategory.ui);
          // Add listener to play when initialized - REFACTORED

          // REFACTORED: Service no longer extends ChangeNotifier - use Riverpod ref.watch instead
        }
      } else {
        Log.info(
            '⚠️ Controller not available or widget not active. Controller: ${newController != null}, isActive: ${widget.isActive}',
            name: 'VideoFeedItem',
            category: LogCategory.ui);
      }
    } else {
      Log.info('↔️ No controller change detected',
          name: 'VideoFeedItem', category: LogCategory.ui);
    }
  }

  void _handleRetry() {
    setState(() {});

    ref.read(videoManagerProvider.notifier).preloadVideo(widget.video.id);
  }

  /// Check if the current user has reacted to this video

  void _playVideo() {
    // Only play if widget is marked as active by parent
    if (!widget.isActive) {
      Log.warning(
        '⚠️ Attempted to play video ${widget.video.id.substring(0, 8)} but widget is not active!',
        name: 'VideoFeedItem',
        category: LogCategory.ui,
      );

      return;
    }

    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_controller!.value.isPlaying) {
      Log.info(
        '🎬 VideoFeedItem playing video: ${widget.video.id.substring(0, 8)} (isActive: ${widget.isActive})',
        name: 'VideoFeedItem',
        category: LogCategory.ui,
      );

      ref.read(videoManagerProvider.notifier).resumeVideo(widget.video.id);
      // Only loop when the video is active (not in background/comments)
      _controller!.setLooping(widget.isActive);

      // Track video view if analytics is enabled
      _trackVideoView();
    }
  }

  void _trackVideoView() {
    try {
      final analyticsService = ref.read(analyticsServiceProvider);
      final authService = ref.read(authServiceProvider);

      // Track with current user's pubkey for proper unique viewer counting
      analyticsService.trackVideoViewWithUser(
        widget.video,
        userId: authService.currentPublicKeyHex,
      );
    } catch (e) {
      // Analytics is optional - don't crash if service is not available
      Log.warning('Analytics service not available: $e',
          name: 'VideoFeedItem', category: LogCategory.ui);
    }
  }

  void _checkAutoPlay(VideoState videoState) {
    // Check if this video's tab is currently active
    final isTabActive = _getTabActiveStatus();

    // Only auto-play if video is ready, widget is active, tab is active, and user hasn't manually paused
    if (widget.isActive &&
        isTabActive &&
        videoState.loadingState == VideoLoadingState.ready &&
        _controller != null &&
        _controller!.value.isInitialized &&
        !_controller!.value.isPlaying &&
        !_userPaused) {
      // Don't auto-play if user manually paused

      Log.info(
        '🎬 Auto-playing video: ${widget.video.id.substring(0, 8)} (tab active: $isTabActive)',
        name: 'VideoFeedItem',
        category: LogCategory.ui,
      );
      _playVideo();
    } else if (!isTabActive &&
        _controller != null &&
        _controller!.value.isPlaying) {
      // Pause video if tab is no longer active
      Log.info(
        '⏸️ Pausing video due to tab switch: ${widget.video.id.substring(0, 8)} (tab active: $isTabActive)',
        name: 'VideoFeedItem',
        category: LogCategory.ui,
      );
      _pauseVideo();
    }
  }

  void _pauseVideo({bool userInitiated = false}) {
    if (_controller != null && _controller!.value.isPlaying) {
      Log.info(
        '⏸️ VideoFeedItem pausing video: ${widget.video.id.substring(0, 8)} (userInitiated: $userInitiated)',
        name: 'VideoFeedItem',
        category: LogCategory.ui,
      );
      ref.read(videoManagerProvider.notifier).pauseVideo(widget.video.id);

      if (userInitiated) {
        _userPaused = true; // Set flag to prevent auto-play
        Log.info('🛑 User paused video',
            name: 'VideoFeedItem', category: LogCategory.ui);
      }
    }
  }

  void _togglePlayPause() {
    Log.debug(
        '_togglePlayPause called for ${widget.video.id.substring(0, 8)}...',
        name: 'VideoFeedItem',
        category: LogCategory.ui);
    if (_controller != null && _controller!.value.isInitialized) {
      final wasPlaying = _controller!.value.isPlaying;
      Log.debug('Current playing state: $wasPlaying',
          name: 'VideoFeedItem', category: LogCategory.ui);

      if (wasPlaying) {
        Log.debug('Calling _pauseVideo() with userInitiated=true',
            name: 'VideoFeedItem', category: LogCategory.ui);
        _pauseVideo(userInitiated: true);
      } else {
        _userPaused = false; // Reset flag when user manually starts video
        Log.debug('▶️ Calling _playVideo()',
            name: 'VideoFeedItem', category: LogCategory.ui);
        _playVideo();
      }
      Log.debug('📱 Showing play/pause icon',
          name: 'VideoFeedItem', category: LogCategory.ui);
      _showPlayPauseIconBriefly();
    } else {
      Log.error(
          '_togglePlayPause failed - controller: ${_controller != null}, initialized: ${_controller?.value.isInitialized}',
          name: 'VideoFeedItem',
          category: LogCategory.ui);
    }
  }

  void _showPlayPauseIconBriefly() {
    // Only show if video is properly initialized and ready
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.hasError) {
      return;
    }

    setState(() {
      _showPlayPauseIcon = true;
    });

    _iconAnimationController.forward().then((_) {
      _iconAnimationController.reverse();
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showPlayPauseIcon = false;
        });
      }
    });
  }

  void _navigateToHashtagFeed(String hashtag) {
    Log.debug('📍 Navigating to hashtag feed: #$hashtag',
        name: 'VideoFeedItem', category: LogCategory.ui);

    // Pause video before navigating away
    _pauseVideo();

    // Use global navigation key for hashtag navigation
    final mainNavState = mainNavigationKey.currentState;
    if (mainNavState != null) {
      // Navigate through main navigation to maintain footer
      mainNavState.navigateToHashtag(hashtag);
    } else {
      // Fallback to direct navigation if not in main navigation context
      Navigator.of(context, rootNavigator: true)
          .push(
        MaterialPageRoute(
          builder: (context) => HashtagFeedScreen(hashtag: hashtag),
        ),
      )
          .then((_) {
        // Resume video when returning (only if still active)
        if (widget.isActive && _controller != null) {
          _playVideo();
        }
      });
    }
  }

  /// Check if this video's tab is currently active
  bool _getTabActiveStatus() {
    // FIXED: Use specific tab context to prevent cross-tab video continuation
    // CRITICAL: Also check if profile tab is active to prevent background playback
    final isProfileTabActive = ref.watch(isProfileTabActiveProvider);

    // If profile tab is active, no videos should auto-play
    if (isProfileTabActive) {
      return false;
    }

    switch (widget.tabContext) {
      case TabContext.feed:
        return ref.watch(isFeedTabActiveProvider);
      case TabContext.explore:
        return ref.watch(isExploreTabActiveProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch VideoManagerProvider to trigger rebuilds when state changes
    final videoManagerState = ref.watch(videoManagerProvider);
    final videoState = videoManagerState.getVideoState(widget.video.id);

    // Check if this video's tab is currently active
    final isTabActive = _getTabActiveStatus();

    Log.info(
        '🔵 Build triggered for ${widget.video.id.substring(0, 8)}... (tab active: $isTabActive)',
        name: 'VideoFeedItem',
        category: LogCategory.ui);

    if (videoState == null) {
      Log.info('❌ Video state is null for ${widget.video.id.substring(0, 8)}',
          name: 'VideoFeedItem', category: LogCategory.ui);
      return _buildErrorState('Video not found');
    }

    Log.info(
        '🔵 Video state: ${videoState.loadingState} for ${widget.video.id.substring(0, 8)}',
        name: 'VideoFeedItem',
        category: LogCategory.ui);

    // Schedule controller update after build completes (debounced)
    if (!_hasScheduledPostFrameCallback) {
      _hasScheduledPostFrameCallback = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Log.info(
              '🕐 PostFrameCallback triggering _updateController for ${widget.video.id.substring(0, 8)}',
              name: 'VideoFeedItem',
              category: LogCategory.ui);
          _updateController();

          // Check for auto-play after controller update
          _checkAutoPlay(videoState);
        }
        _hasScheduledPostFrameCallback = false;
      });
    }

    // Wrap with VideoMetricsTracker to track engagement
    return VideoMetricsTracker(
      video: widget.video,
      controller: _controller,
      child: _buildVideoContent(videoState),
    );
  }

  /// Estimate the height needed for text content below video
  double _estimateTextHeight() {
    double height = 0;

    // Creator info: ~40px
    height += 40;

    // Repost attribution if present: ~30px
    if (widget.video.isRepost) {
      height += 30;
    }

    // Title if present (max 2 lines): ~50px
    if (widget.video.title?.isNotEmpty == true) {
      height += 50;
    }

    // Content/description (max 3 lines): ~70px
    if (widget.video.content.isNotEmpty) {
      height += 70;
    }

    // Hashtags if present: ~30px
    if (widget.video.hashtags.isNotEmpty) {
      height += 30;
    }

    // Action buttons: ~60px
    height += 60;

    return height;
  }

  /// Build video info content without overlay styling
  Widget _buildVideoInfo() {
    // Check if title and content are the same
    final title = widget.video.title?.trim() ?? '';
    final content = widget.video.content.trim();
    final isDuplicate =
        title.isNotEmpty && content.isNotEmpty && title == content;

    // Check if hashtags are already in the content
    final hashtagsInContent = widget.video.hashtags.isNotEmpty &&
        widget.video.hashtags.every((tag) => content.contains('#$tag'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Username/Creator info
        _buildCreatorInfo(),
        const SizedBox(height: 4), // Reduced from 8

        // Repost attribution (if this is a repost)
        if (widget.video.isRepost) ...[
          _buildRepostAttribution(),
          const SizedBox(height: 4), // Reduced from 8
        ],

        // Video title (skip if duplicate with content)
        if (title.isNotEmpty && !isDuplicate) ...[
          SelectableText(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15, // Reduced from 16
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 4), // Reduced from 8
        ],

        // Video content/description (or use as title if duplicate)
        if (content.isNotEmpty) ...[
          ClickableHashtagText(
            text: content,
            style: TextStyle(
              color: isDuplicate ? Colors.white : Colors.white70,
              fontSize: isDuplicate ? 15 : 14,
              fontWeight: isDuplicate ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: isDuplicate ? 2 : 3,
            onVideoStateChange: _pauseVideo,
          ),
          const SizedBox(height: 4), // Reduced from 8
        ],

        // Hashtags (only show if not already in content)
        if (widget.video.hashtags.isNotEmpty && !hashtagsInContent) ...[
          Wrap(
            spacing: 6, // Reduced from 8
            children: widget.video.hashtags
                .take(3)
                .map(
                  (hashtag) => GestureDetector(
                    onTap: () => _navigateToHashtagFeed(hashtag),
                    child: Text(
                      '#$hashtag',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 13, // Reduced from 14
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6), // Reduced from 8
        ],

        // Metrics (loops/likes) if available
        if (_hasAnyMetrics)
          Padding(
            padding: const EdgeInsets.only(bottom: 4), // Reduced from 8
            child: _buildMetricsRow(),
          ),

        // Social action buttons
        _buildSocialActions(),
      ],
    );
  }

  Widget _buildVideoContent(VideoState videoState) {
    // All videos are now forced to be square (1:1 aspect ratio) for classic vine style
    final isVideoReady = _controller != null &&
        _controller!.value.isInitialized &&
        videoState.loadingState == VideoLoadingState.ready;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        // For portrait-like aspect ratios (height > width), prefer column layout when video is ready
        final isPortraitLayout = availableHeight > availableWidth * 1.2;
        final estimatedTextHeight = _estimateTextHeight();
        final videoHeight = availableWidth; // Square video
        final requiredHeight =
            videoHeight + estimatedTextHeight + 48; // 48px padding
        final hasEnoughSpace = requiredHeight <= availableHeight;

        // Use column layout if forced or for portrait screens with enough space when video is ready
        final useColumnLayout = widget.forceInfoBelow ||
            (isVideoReady && isPortraitLayout && hasEnoughSpace);

        Log.debug(
            'Layout: availableH=$availableHeight, availableW=$availableWidth, '
            'isPortrait=$isPortraitLayout, hasSpace=$hasEnoughSpace, useColumn=$useColumnLayout',
            name: 'VideoFeedItem',
            category: LogCategory.ui);

        if (useColumnLayout) {
          // Use column layout with text below video
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: Column(
              children: [
                // Video takes square space
                SizedBox(
                  width: availableWidth,
                  height:
                      availableWidth, // Use actual container width for square aspect
                  child: Stack(
                    children: [
                      _buildMainContent(videoState),
                      // Play/Pause icon overlay (when tapped and video is ready)
                      if (_showPlayPauseIcon && !videoState.isLoading)
                        _buildPlayPauseIconOverlay(),
                      // Loading indicator
                      if (videoState.isLoading &&
                          videoState.loadingState != VideoLoadingState.loading)
                        _buildLoadingOverlay(),
                    ],
                  ),
                ),
                // Text content below video
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: _buildVideoInfo(),
                  ),
                ),
              ],
            ),
          );
        } else {
          // Fall back to overlay layout when no space below
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: Stack(
              children: [
                // Main video content
                _buildMainContent(videoState),

                // Video overlay information
                _buildVideoOverlay(),

                // Loading indicator (when loading but not showing loading state)
                if (videoState.isLoading &&
                    videoState.loadingState != VideoLoadingState.loading)
                  _buildLoadingOverlay(),

                // Play/Pause icon overlay (when tapped and video is ready)
                if (_showPlayPauseIcon &&
                    !videoState.isLoading &&
                    videoState.loadingState == VideoLoadingState.ready)
                  _buildPlayPauseIconOverlay(),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildMainContent(VideoState videoState) {
    switch (videoState.loadingState) {
      case VideoLoadingState.notLoaded:
        return _buildNotLoadedState();

      case VideoLoadingState.loading:
        return _buildLoadingState();

      case VideoLoadingState.ready:
        if (widget.video.isGif) {
          return _buildGifContent();
        } else {
          return _buildVideoPlayerContent();
        }

      case VideoLoadingState.failed:
        return _buildFailedState(videoState, canRetry: true);

      case VideoLoadingState.permanentlyFailed:
        return _buildFailedState(videoState, canRetry: false);

      case VideoLoadingState.disposed:
        // Auto-retry disposed videos when they come into view
        if (widget.isActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(videoManagerProvider.notifier)
                .preloadVideo(widget.video.id);
          });
        }
        return _buildDisposedState();
    }
  }

  Widget _buildNotLoadedState() => Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[900],
        child: const Center(
          child: Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.white54,
          ),
        ),
      );

  Widget _buildLoadingState() {
    // If we have a thumbnail, show it full screen with loading overlay
    if (widget.video.thumbnailUrl != null &&
        widget.video.thumbnailUrl!.isNotEmpty) {
      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Display thumbnail with proper aspect ratio
            Align(
              alignment: Alignment.topCenter,
              child: _buildThumbnailWithAspectRatio(),
            ),
            // Semi-transparent overlay
            Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
            // Loading indicator
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      );
    }

    // Fallback loading state without thumbnail - full screen
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[900],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGifContent() {
    // For GIFs, we would typically use Image.network with caching
    // For TDD phase, show placeholder
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.gif,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              widget.video.title ?? 'GIF Video',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayerContent() {
    if (_controller == null) {
      return _buildNotLoadedState();
    }

    // Web platform needs special handling for video tap events
    if (kIsWeb) {
      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              Log.debug(
                  'Web video tap detected for ${widget.video.id.substring(0, 8)}...',
                  name: 'VideoFeedItem',
                  category: LogCategory.ui);
              if (_controller != null &&
                  _controller!.value.isInitialized &&
                  !_controller!.value.hasError) {
                Log.info('Web video tap conditions met, toggling play/pause',
                    name: 'VideoFeedItem', category: LogCategory.ui);
                _togglePlayPause();
              } else {
                Log.error(
                    'Web video tap ignored - controller: ${_controller != null}, initialized: ${_controller?.value.isInitialized}, hasError: ${_controller?.value.hasError}',
                    name: 'VideoFeedItem',
                    category: LogCategory.ui);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Show thumbnail as background to prevent flash
                if (widget.video.thumbnailUrl != null &&
                    widget.video.thumbnailUrl!.isNotEmpty)
                  Align(
                    alignment: Alignment.topCenter,
                    child: _buildThumbnailWithAspectRatio(),
                  ),
                // Video fills width and is top-aligned
                if (_controller!.value.isInitialized)
                  Align(
                    alignment: Alignment.topCenter,
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                // Extra transparent layer for web gesture capture
                Positioned.fill(
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Native platform (mobile) - full screen
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: GestureDetector(
        onTap: () {
          Log.debug(
              'Native video tap detected for ${widget.video.id.substring(0, 8)}...',
              name: 'VideoFeedItem',
              category: LogCategory.ui);
          if (_controller != null &&
              _controller!.value.isInitialized &&
              !_controller!.value.hasError) {
            Log.info('Native video tap conditions met, toggling play/pause',
                name: 'VideoFeedItem', category: LogCategory.ui);
            _togglePlayPause();
          } else {
            Log.error(
                'Native video tap ignored - controller: ${_controller != null}, initialized: ${_controller?.value.isInitialized}, hasError: ${_controller?.value.hasError}',
                name: 'VideoFeedItem',
                category: LogCategory.ui);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Show thumbnail as background to prevent flash
            if (widget.video.thumbnailUrl != null &&
                widget.video.thumbnailUrl!.isNotEmpty)
              Align(
                alignment: Alignment.topCenter,
                child: _buildThumbnailWithAspectRatio(),
              ),
            // Video fills width and is top-aligned
            if (_controller!.value.isInitialized)
              Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build thumbnail with proper aspect ratio from video dimensions
  Widget _buildThumbnailWithAspectRatio() {
    // Calculate aspect ratio from video dimensions if available
    double aspectRatio = 16 / 9; // Default aspect ratio
    if (widget.video.width != null && widget.video.height != null) {
      aspectRatio = widget.video.width! / widget.video.height!;
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Image.network(
        widget.video.thumbnailUrl!,
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[900],
        ),
      ),
    );
  }

  Widget _buildFailedState(VideoState videoState, {required bool canRetry}) =>
      Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[900], // Use neutral color instead of red
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off,
                size: 64,
                color: canRetry ? Colors.white54 : Colors.white38,
              ),
              const SizedBox(height: 16),
              Text(
                canRetry ? 'Video unavailable' : 'Video not available',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (videoState.errorMessage != null) ...[
                Text(
                  _getUserFriendlyErrorMessage(videoState.errorMessage!),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              if (canRetry) ...[
                ElevatedButton(
                  onPressed: _handleRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildDisposedState() => Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[700],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.delete_outline,
                size: 64,
                color: Colors.white54,
              ),
              SizedBox(height: 16),
              Text(
                'Video disposed',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildErrorState(String message) => Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[900], // Use neutral color instead of red
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_off,
                size: 64,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              const Text(
                'Video unavailable',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getUserFriendlyErrorMessage(message),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _buildVideoOverlay() {
    // Check if title and content are the same
    final title = widget.video.title?.trim() ?? '';
    final content = widget.video.content.trim();
    final isDuplicate =
        title.isNotEmpty && content.isNotEmpty && title == content;

    // Check if hashtags are already in the content
    final hashtagsInContent = widget.video.hashtags.isNotEmpty &&
        widget.video.hashtags.every((tag) => content.contains('#$tag'));

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        padding: const EdgeInsets.all(12), // Reduced from 16
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Username/Creator info
            _buildCreatorInfo(),
            const SizedBox(height: 4), // Reduced from 8

            // Repost attribution (if this is a repost)
            if (widget.video.isRepost) ...[
              _buildRepostAttribution(),
              const SizedBox(height: 4), // Reduced from 8
            ],

            // Video title (skip if duplicate with content)
            if (title.isNotEmpty && !isDuplicate) ...[
              SelectableText(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15, // Reduced from 16
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 4), // Reduced from 8
            ],

            // Video content/description (or use as title if duplicate)
            if (content.isNotEmpty) ...[
              ClickableHashtagText(
                text: content,
                style: TextStyle(
                  color: isDuplicate ? Colors.white : Colors.white70,
                  fontSize: isDuplicate ? 15 : 14,
                  fontWeight: isDuplicate ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: isDuplicate ? 2 : 3,
                onVideoStateChange: _pauseVideo,
              ),
              const SizedBox(height: 4), // Reduced from 8
            ],

            // Hashtags (only show if not already in content)
            if (widget.video.hashtags.isNotEmpty && !hashtagsInContent) ...[
              Wrap(
                spacing: 6, // Reduced from 8
                children: widget.video.hashtags
                    .take(3)
                    .map(
                      (hashtag) => GestureDetector(
                        onTap: () => _navigateToHashtagFeed(hashtag),
                        child: Text(
                          '#$hashtag',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 13, // Reduced from 14
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 6), // Reduced from 8
            ],

            // Metrics (loops/likes) if available
            if (_hasAnyMetrics) ...[
              _buildMetricsRow(),
              const SizedBox(height: 6), // Reduced from 8
            ],

            // Social action buttons
            _buildSocialActions(),
          ],
        ),
      ),
    );
  }

  bool get _hasAnyMetrics =>
      (widget.video.originalLoops != null && widget.video.originalLoops! > 0) ||
      (widget.video.originalLikes != null && widget.video.originalLikes! > 0);

  Widget _buildMetricsRow() {
    final loops = widget.video.originalLoops;
    final likes = widget.video.originalLikes;
    final items = <Widget>[];

    if (loops != null && loops > 0) {
      items.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.loop, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text('${_formatCount(loops)} loops',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ));
    }
    if (likes != null && likes > 0) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 16));
      items.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite, size: 14, color: Colors.redAccent),
          const SizedBox(width: 4),
          Text('${_formatCount(likes)} likes',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ));
    }

    return Row(children: items);
  }

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

  // Removed unused _buildVideoInfoBelow method

  Widget _buildLoadingOverlay() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        ),
      );

  Widget _buildPlayPauseIconOverlay() {
    final isPlaying = _controller?.value.isPlaying ?? false;

    return AnimatedBuilder(
      animation: _iconAnimationController,
      builder: (context, child) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Transform.scale(
            scale: 0.8 + (_iconAnimationController.value * 0.2),
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.black,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorInfo() => Consumer(
        builder: (context, ref, child) {
          // Watch the Riverpod profile provider for reactive updates
          final profileState = ref.watch(userProfileNotifierProvider);
          final authService = ref.watch(authServiceProvider);
          final profile = profileState.getCachedProfile(widget.video.pubkey);
          final displayName = profile?.displayName ??
              profile?.name ??
              '@${widget.video.pubkey.substring(0, 8)}...';

          // Check if this is the current user's video
          final isOwnVideo =
              authService.currentPublicKeyHex == widget.video.pubkey;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  Log.verbose('Navigating to profile: ${widget.video.pubkey}',
                      name: 'VideoFeedItem', category: LogCategory.ui);
                  // Pause video before navigating
                  _pauseVideo();
                  // Prefer main navigation if available; otherwise push directly
                  final mainNavState = mainNavigationKey.currentState;
                  if (mainNavState != null) {
                    mainNavState.navigateToProfile(widget.video.pubkey);
                  } else {
                    Navigator.of(context, rootNavigator: true)
                        .push(
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(
                          profilePubkey: widget.video.pubkey,
                        ),
                      ),
                    )
                        .then((_) {
                      if (widget.isActive && _controller != null) {
                        _playVideo();
                      }
                    });
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Add NIP-05 verification badge if verified
                    if (profile?.nip05 != null &&
                        profile!.nip05!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• ${_formatTimestamp(_getDisplayTimestamp())}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              // Add follow button if not own video
              if (!isOwnVideo) ...[
                const SizedBox(width: 12),
                Consumer(
                  builder: (context, ref, child) {
                    final isFollowing =
                        ref.watch(isFollowingProvider(widget.video.pubkey));
                    return ElevatedButton(
                      onPressed: () => _handleFollow(context, ref),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isFollowing ? Colors.grey[700] : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        minimumSize: const Size(60, 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isFollowing ? 'Following' : 'Follow',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      );

  // Prefer original published time if provided; fall back to nostr createdAt
  DateTime _getDisplayTimestamp() {
    final published = widget.video.publishedAt;
    if (published != null && published.isNotEmpty) {
      // Try epoch seconds
      final seconds = int.tryParse(published);
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      // Try ISO8601 or other parseable formats
      try {
        return DateTime.parse(published);
      } catch (_) {}
    }
    return widget.video.timestamp;
  }

  Widget _buildRepostAttribution() => Consumer(
        builder: (context, ref, child) {
          // Watch the Riverpod profile provider for reactive updates
          final profileState = ref.watch(userProfileNotifierProvider);
          if (widget.video.reposterPubkey == null) {
            return const SizedBox.shrink();
          }

          final repostProfile =
              profileState.getCachedProfile(widget.video.reposterPubkey!);
          final reposterName = repostProfile?.displayName ??
              repostProfile?.name ??
              '@${widget.video.reposterPubkey!.substring(0, 8)}...';

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.repeat,
                color: VineTheme.vineGreen,
                size: 16,
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  Log.verbose(
                      'Navigating to reposter profile: ${widget.video.reposterPubkey}',
                      name: 'VideoFeedItem',
                      category: LogCategory.ui);
                  // Pause video before navigating
                  _pauseVideo();
                  // Prefer main navigation if available; otherwise push directly
                  final mainNavState = mainNavigationKey.currentState;
                  final repubkey = widget.video.reposterPubkey;
                  if (mainNavState != null) {
                    mainNavState.navigateToProfile(repubkey);
                  } else if (repubkey != null) {
                    Navigator.of(context, rootNavigator: true)
                        .push(
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(
                          profilePubkey: repubkey,
                        ),
                      ),
                    )
                        .then((_) {
                      if (widget.isActive && _controller != null) {
                        _playVideo();
                      }
                    });
                  }
                },
                child: Text(
                  'Reposted by $reposterName',
                  style: const TextStyle(
                    color: VineTheme.vineGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget _buildSocialActions() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Like button with functionality
            Consumer(
              builder: (context, ref, child) {
                final socialState =
                    ref.watch(social_providers.socialNotifierProvider);
                final isLiked = socialState.isLiked(widget.video.id);

                return _buildActionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : Colors.white,
                  onPressed: () => _handleLike(context),
                );
              },
            ),

            // Comment button
            _buildActionButton(
              icon: Icons.comment_outlined,
              onPressed: () => _handleCommentTap(context),
            ),

            // Repost button
            Consumer(
              builder: (context, ref, child) {
                final socialState =
                    ref.watch(social_providers.socialNotifierProvider);
                final hasReposted = socialState.hasReposted(widget.video.id);
                return _buildActionButton(
                  icon: Icons.repeat,
                  color: hasReposted ? VineTheme.vineGreen : Colors.white,
                  onPressed: () => _handleRepost(context),
                );
              },
            ),

            // Share button
            _buildActionButton(
              icon: Icons.share_outlined,
              onPressed: () => _handleShare(context),
            ),
          ],
        ),
      );

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) =>
      IconButton(
        icon: Icon(
          icon,
          color: color ?? Colors.white,
          size: 24,
        ),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
      );

  /// Build event tags from the original video event for reposting - REMOVED (unused duplicate method)

  Future<void> _handleRepost(BuildContext context) async {
    // Show repost options dialog
    _showRepostOptionsDialog(context);
  }

  void _showRepostOptionsDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VineTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _RevineOptionsSheet(video: widget.video),
    );
  }

  void _openComments(BuildContext context) {
    // Pause the video when opening comments
    _pauseVideo();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommentsScreen(videoEvent: widget.video),
      ),
    ).then((_) {
      // Resume video when returning from comments (only if still active)
      if (widget.isActive && _controller != null) {
        _playVideo();
      }
    });
  }

  /// Handle comment icon tap - opens comments screen
  Future<void> _handleCommentTap(BuildContext context) async {
    _openComments(context);
  }

  Future<void> _handleLike(BuildContext context) async {
    // Store context reference to avoid async gap warnings
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(social_providers.socialNotifierProvider.notifier)
          .toggleLike(widget.video.id, widget.video.pubkey);
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to like video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleShare(BuildContext context) {
    // Pause video before showing share menu
    _pauseVideo();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareVideoMenu(
        video: widget.video,
        onDismiss: () => Navigator.of(context).pop(),
      ),
    ).then((_) {
      // Resume video when share menu is dismissed (only if still active)
      if (widget.isActive && _controller != null) {
        _playVideo();
      }
    });
  }

  Future<void> _handleFollow(BuildContext context, WidgetRef ref) async {
    try {
      final authService = ref.read(authServiceProvider);
      if (!authService.isAuthenticated) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in to follow users'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final optimisticMethods = ref.read(optimisticFollowMethodsProvider);
      final isFollowing = ref.read(isFollowingProvider(widget.video.pubkey));

      if (isFollowing) {
        await optimisticMethods.unfollowUser(widget.video.pubkey);
      } else {
        await optimisticMethods.followUser(widget.video.pubkey);
      }
    } catch (e) {
      // Silently handle error - optimistic state will be reverted
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'now';
    }
  }

  /// Convert technical error messages to user-friendly messages
  String _getUserFriendlyErrorMessage(String errorMessage) {
    final lowerError = errorMessage.toLowerCase();

    if (lowerError.contains('404') || lowerError.contains('not found')) {
      return 'Video not found';
    } else if (lowerError.contains('network') ||
        lowerError.contains('connection')) {
      return 'Check your internet connection';
    } else if (lowerError.contains('timeout')) {
      return 'Loading timed out';
    } else if (lowerError.contains('format') || lowerError.contains('codec')) {
      return 'Video format not supported';
    } else if (lowerError.contains('permission') ||
        lowerError.contains('unauthorized')) {
      return 'Access denied';
    } else {
      return 'Unable to play video';
    }
  }
}

/// Accessibility helper for video content
class VideoAccessibilityInfo extends StatelessWidget {
  const VideoAccessibilityInfo({
    required this.video,
    super.key,
    this.videoState,
  });
  final VideoEvent video;
  final VideoState? videoState;

  @override
  Widget build(BuildContext context) {
    var semanticLabel = 'Video';

    if (video.title?.isNotEmpty == true) {
      semanticLabel += ': ${video.title}';
    }

    if (videoState != null) {
      switch (videoState!.loadingState) {
        case VideoLoadingState.loading:
          semanticLabel += ', loading';
        case VideoLoadingState.ready:
          semanticLabel += ', ready to play';
        case VideoLoadingState.failed:
          semanticLabel += ', failed to load';
        case VideoLoadingState.permanentlyFailed:
          semanticLabel += ', permanently failed';
        default:
          break;
      }
    }

    return Semantics(
      label: semanticLabel,
      child: const SizedBox.shrink(),
    );
  }
}

/// Bottom sheet for choosing repost destination
class _RevineOptionsSheet extends ConsumerStatefulWidget {
  const _RevineOptionsSheet({required this.video});

  final VideoEvent video;

  @override
  ConsumerState<_RevineOptionsSheet> createState() =>
      _RevineOptionsSheetState();
}

class _RevineOptionsSheetState extends ConsumerState<_RevineOptionsSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.repeat,
                        color: VineTheme.vineGreen, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Revine',
                        style: TextStyle(
                          color: VineTheme.whiteText,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          color: VineTheme.secondaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Video info preview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VineTheme.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail placeholder
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child:
                            const Icon(Icons.play_arrow, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      // Video details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.video.title?.isNotEmpty == true)
                              Text(
                                widget.video.title!,
                                style: const TextStyle(
                                  color: VineTheme.whiteText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            Text(
                              widget.video.content.isNotEmpty
                                  ? widget.video.content
                                  : 'Video content',
                              style: const TextStyle(
                                color: VineTheme.lightText,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Main Revine Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _repostToHomeFeed(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VineTheme.vineGreen,
                      foregroundColor: VineTheme.whiteText,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.repeat, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Revine',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // List options section
                const Text(
                  'Or add this vine to a list',
                  style: TextStyle(
                    color: VineTheme.lightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),

                // List options
                Consumer(
                  builder: (context, ref, child) {
                    final curatedListServiceAsync =
                        ref.watch(curatedListServiceProvider);

                    return curatedListServiceAsync.when(
                      data: (curatedListService) {
                        final defaultList = curatedListService.getDefaultList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Default "My List" option
                            if (defaultList != null) ...[
                              _buildRepostOption(
                                icon: Icons.playlist_play,
                                title: 'Add to "${defaultList.name}"',
                                subtitle:
                                    'Your main curated list (${defaultList.videoEventIds.length} videos)',
                                onTap: () => _addToDefaultList(),
                                isHighlighted: true,
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Bookmarks option
                            _buildRepostOption(
                              icon: Icons.bookmark_outline,
                              title: 'Add to Bookmarks',
                              subtitle: 'Save for later viewing',
                              onTap: () => _addToBookmarks(),
                            ),
                            const SizedBox(height: 12),

                            // More lists option
                            _buildRepostOption(
                              icon: Icons.playlist_add,
                              title: 'Choose List',
                              subtitle: curatedListService.lists.isEmpty
                                  ? 'Create or select curated lists'
                                  : 'Choose from ${curatedListService.lists.length} lists or create new',
                              onTap: () => _showListSelectionDialog(),
                            ),
                            const SizedBox(height: 12),

                            // Create new list option (bottom)
                            _buildRepostOption(
                              icon: Icons.add,
                              title: 'Create New List',
                              subtitle: 'Make a new curated list for this vine',
                              onTap: () => _showCreateNewListDialog(),
                            ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stack) =>
                          Center(child: Text('Error: $error')),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRepostOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isHighlighted = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isHighlighted ? VineTheme.vineGreen : Colors.grey.shade800,
            width: isHighlighted ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isHighlighted
              ? VineTheme.vineGreen.withValues(alpha: 0.05)
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: VineTheme.vineGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: VineTheme.vineGreen, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: VineTheme.whiteText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: VineTheme.lightText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: VineTheme.lightText, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _repostToHomeFeed() async {
    Navigator.of(context).pop(); // Close the dialog first

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // Create Event object for reposting
      final eventToRepost = Event(
        widget.video.pubkey,
        22, // kind
        _buildEventTags(),
        widget.video.content,
        createdAt: widget.video.createdAt,
      );

      await ref
          .read(social_providers.socialNotifierProvider.notifier)
          .repostEvent(eventToRepost);

      // Show success message
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Video reposted to your home feed!'),
            ],
          ),
          backgroundColor: VineTheme.vineGreen,
        ),
      );
    } catch (e) {
      // Show error message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Failed to repost: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addToDefaultList() async {
    Navigator.of(context).pop(); // Close dialog

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final curatedListService =
          await ref.read(curatedListServiceProvider.future);
      final defaultList = curatedListService.getDefaultList();

      if (defaultList == null) {
        throw Exception('Default list not found');
      }

      // Check if already in list
      if (defaultList.videoEventIds.contains(widget.video.id)) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Video is already in "${defaultList.name}"'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final success = await curatedListService.addVideoToList(
          defaultList.id, widget.video.id);

      if (!success) {
        throw Exception('Failed to add video to list');
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Video added to "${defaultList.name}"!'),
              ),
            ],
          ),
          backgroundColor: VineTheme.vineGreen,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Failed to add to list: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addToBookmarks() async {
    Navigator.of(context).pop(); // Close dialog

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final bookmarkService = await ref.read(bookmarkServiceProvider.future);

      // Check if already bookmarked
      if (bookmarkService.isVideoBookmarkedGlobally(widget.video.id)) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Video is already bookmarked'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final success =
          await bookmarkService.addVideoToGlobalBookmarks(widget.video.id);

      if (!success) {
        throw Exception('Failed to add bookmark');
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Video bookmarked!'),
            ],
          ),
          backgroundColor: VineTheme.vineGreen,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Failed to bookmark: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showListSelectionDialog() {
    Navigator.of(context).pop(); // Close repost dialog

    showDialog(
      context: context,
      builder: (context) => _ListSelectionDialog(video: widget.video),
    );
  }

  void _showCreateNewListDialog() {
    Navigator.of(context).pop(); // Close repost dialog

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: VineTheme.cardBackground,
        title: const Text(
          'Create New List',
          style: TextStyle(
              color: VineTheme.whiteText, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'List Name',
              style: TextStyle(
                  color: VineTheme.whiteText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              style: const TextStyle(color: VineTheme.whiteText),
              decoration: InputDecoration(
                hintText: 'Enter list name...',
                hintStyle: const TextStyle(color: VineTheme.lightText),
                filled: true,
                fillColor: VineTheme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text(
              'Description (Optional)',
              style: TextStyle(
                  color: VineTheme.whiteText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              style: const TextStyle(color: VineTheme.whiteText),
              decoration: InputDecoration(
                hintText: 'Enter description...',
                hintStyle: const TextStyle(color: VineTheme.lightText),
                filled: true,
                fillColor: VineTheme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: VineTheme.lightText)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a list name'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop(); // Close create dialog

              final curatedListService =
                  await ref.read(curatedListServiceProvider.future);
              final newList = await curatedListService.createList(
                name: name,
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                isPublic: true,
              );

              if (newList != null && mounted) {
                // Add video to the newly created list
                final success = await curatedListService.addVideoToList(
                    newList.id, widget.video.id);

                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                'Created "${newList.name}" and added vine!'),
                          ),
                        ],
                      ),
                      backgroundColor: VineTheme.vineGreen,
                    ),
                  );
                }
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.error, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(child: Text('Failed to create list')),
                      ],
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VineTheme.vineGreen,
              foregroundColor: VineTheme.whiteText,
            ),
            child: const Text('Create & Add Vine'),
          ),
        ],
      ),
    );
  }

  List<List<String>> _buildEventTags() {
    // Build tags for the event - simplified version
    final tags = <List<String>>[];

    // Add basic event info tags if available
    if (widget.video.title?.isNotEmpty == true) {
      tags.add(['title', widget.video.title!]);
    }

    // Add hashtags
    for (final hashtag in widget.video.hashtags) {
      tags.add(['t', hashtag]);
    }

    return tags;
  }
}

/// Dialog for selecting which list to add the video to
class _ListSelectionDialog extends ConsumerWidget {
  const _ListSelectionDialog({required this.video});

  final VideoEvent video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final curatedListServiceAsync = ref.watch(curatedListServiceProvider);

    return curatedListServiceAsync.when(
      data: (curatedListService) {
        final lists = curatedListService.lists;

        return AlertDialog(
          backgroundColor: VineTheme.backgroundColor,
          title: const Text(
            'Add to List',
            style: TextStyle(color: VineTheme.whiteText),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Create new list option
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: VineTheme.vineGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.add,
                        color: VineTheme.vineGreen, size: 18),
                  ),
                  title: const Text(
                    'Create New List',
                    style: TextStyle(
                        color: VineTheme.whiteText,
                        fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Make a new curated list for this video',
                    style: TextStyle(color: VineTheme.lightText, fontSize: 12),
                  ),
                  onTap: () => _showCreateListDialog(context, ref),
                ),
                if (lists.isNotEmpty) ...[
                  const Divider(color: VineTheme.lightText),
                  const SizedBox(height: 8),
                  // Existing lists
                  ...lists.asMap().entries.map((entry) {
                    final list = entry.value;
                    final isAlreadyInList =
                        list.videoEventIds.contains(video.id);

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isAlreadyInList
                              ? VineTheme.vineGreen.withValues(alpha: 0.2)
                              : VineTheme.vineGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isAlreadyInList ? Icons.check : Icons.playlist_add,
                          color: isAlreadyInList
                              ? VineTheme.vineGreen
                              : VineTheme.vineGreen,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        list.name,
                        style: const TextStyle(color: VineTheme.whiteText),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (list.description?.isNotEmpty == true)
                            Text(
                              list.description!,
                              style:
                                  const TextStyle(color: VineTheme.lightText),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            '${list.videoEventIds.length} videos',
                            style: const TextStyle(
                                color: VineTheme.lightText, fontSize: 12),
                          ),
                          if (isAlreadyInList)
                            const Text(
                              'Already in this list',
                              style: TextStyle(
                                  color: VineTheme.vineGreen, fontSize: 12),
                            ),
                        ],
                      ),
                      enabled: !isAlreadyInList,
                      onTap: isAlreadyInList
                          ? null
                          : () => _addToListAndRepost(context, ref, list),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: VineTheme.vineGreen),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
    );
  }

  Future<void> _addToListAndRepost(
      BuildContext context, WidgetRef ref, CuratedList list) async {
    Navigator.of(context).pop(); // Close dialog

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // Add video to the selected list
      final curatedListService =
          await ref.read(curatedListServiceProvider.future);
      final success =
          await curatedListService.addVideoToList(list.id, video.id);

      if (!success) {
        throw Exception('Failed to add video to list');
      }

      // Show success message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Video added to "${list.name}"!'),
              ),
            ],
          ),
          backgroundColor: VineTheme.vineGreen,
        ),
      );
    } catch (e) {
      // Show error message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Failed to add to list: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show dialog to create a new curated list
  void _showCreateListDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: VineTheme.cardBackground,
        title: const Text(
          'Create New List',
          style: TextStyle(
              color: VineTheme.whiteText, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'List Name',
              style: TextStyle(
                  color: VineTheme.whiteText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              style: const TextStyle(color: VineTheme.whiteText),
              decoration: InputDecoration(
                hintText: 'Enter list name...',
                hintStyle: const TextStyle(color: VineTheme.lightText),
                filled: true,
                fillColor: VineTheme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text(
              'Description (Optional)',
              style: TextStyle(
                  color: VineTheme.whiteText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              style: const TextStyle(color: VineTheme.whiteText),
              decoration: InputDecoration(
                hintText: 'Enter description...',
                hintStyle: const TextStyle(color: VineTheme.lightText),
                filled: true,
                fillColor: VineTheme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: VineTheme.lightText)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a list name'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop(); // Close create dialog
              Navigator.of(context).pop(); // Close list selection dialog

              final curatedListService =
                  await ref.read(curatedListServiceProvider.future);
              final newList = await curatedListService.createList(
                name: name,
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                isPublic: true,
              );

              if (newList != null) {
                // Add video to the newly created list
                final success = await curatedListService.addVideoToList(
                    newList.id, video.id);

                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                'Created "${newList.name}" and added video!'),
                          ),
                        ],
                      ),
                      backgroundColor: VineTheme.vineGreen,
                    ),
                  );
                }
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.error, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(child: Text('Failed to create list')),
                      ],
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VineTheme.vineGreen,
              foregroundColor: VineTheme.whiteText,
            ),
            child: const Text('Create & Add Video'),
          ),
        ],
      ),
    );
  }
}
