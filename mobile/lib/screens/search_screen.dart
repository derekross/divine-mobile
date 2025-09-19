// ABOUTME: Search screen for finding videos, users, and hashtags in the divine network
// ABOUTME: Provides real-time search functionality with filters and categories

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostr_sdk/filter.dart';
import 'package:nostr_sdk/nip19/nip19.dart';
import 'package:openvine/main.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late TabController _tabController;

  List<VideoEvent> _videoResults = [];
  List<String> _userResults = [];
  List<String> _hashtagResults = [];

  bool _isSearching = false;
  String _currentQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_onSearchChanged);

    // Request focus after a short delay to avoid Chrome keyboard issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _currentQuery) {
      _currentQuery = query;

      // Cancel any existing timer
      _debounceTimer?.cancel();

      if (query.isNotEmpty) {
        // Debounce search to avoid rapid queries
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted && _currentQuery == query) {
            _performSearch(query);
          }
        });
      } else {
        _clearResults();
      }
    }
  }

  void _performSearch(String query) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final videoEventService = ref.read(videoEventServiceProvider);
      final nostrService = ref.read(nostrServiceProvider);

      // Check if query is an npub identifier
      String? searchPubkey;
      if (query.startsWith('npub') && query.length > 50) {
        try {
          // Convert npub to hex pubkey
          searchPubkey = Nip19.decode(query);
          Log.debug('📱 Decoded npub to pubkey: $searchPubkey',
              name: 'SearchScreen', category: LogCategory.ui);
        } catch (e) {
          Log.error('Failed to decode npub: $e',
              name: 'SearchScreen', category: LogCategory.ui);
        }
      }

      // Perform proper Nostr search through the embedded relay
      final searchResults = <VideoEvent>[];
      final processedEventIds = <String>{};

      // If searching for a specific user, filter by author
      final searchStream = nostrService.searchVideos(
        query,
        authors: searchPubkey != null ? [searchPubkey] : null,
        limit: 200,
      );

      // Collect search results from the relay
      await for (final event in searchStream) {
        if (!processedEventIds.contains(event.id)) {
          processedEventIds.add(event.id);
          try {
            final videoEvent = VideoEvent.fromNostrEvent(event);
            searchResults.add(videoEvent);
          } catch (e) {
            Log.error('Failed to parse video event: $e',
                name: 'SearchScreen', category: LogCategory.ui);
          }
        }
      }

      // Also search through locally cached videos for immediate results
      final allCachedVideos = <VideoEvent>[];
      allCachedVideos.addAll(videoEventService.discoveryVideos);
      allCachedVideos.addAll(videoEventService.homeFeedVideos);
      if (videoEventService.profileVideos.isNotEmpty) {
        allCachedVideos.addAll(videoEventService.profileVideos);
      }
      if (videoEventService.editorialVideos.isNotEmpty) {
        allCachedVideos.addAll(videoEventService.editorialVideos);
      }

      // Add cached videos that match but weren't in relay results
      for (final video in allCachedVideos) {
        if (!processedEventIds.contains(video.id)) {
          bool matches = false;

          // If we have a decoded npub, search by author
          if (searchPubkey != null) {
            matches = video.pubkey == searchPubkey;
          } else {
            // Otherwise search by content
            final titleMatch =
                video.title?.toLowerCase().contains(query.toLowerCase()) ??
                    false;
            final contentMatch =
                video.content.toLowerCase().contains(query.toLowerCase());
            final hashtagMatch = video.hashtags
                .any((tag) => tag.toLowerCase().contains(query.toLowerCase()));
            matches = titleMatch || contentMatch || hashtagMatch;
          }

          if (matches) {
            searchResults.add(video);
            processedEventIds.add(video.id);
          }
        }
      }

      // Sort results by timestamp (newest first)
      searchResults.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Search for user profiles that match the query
      final userResults = <String>{};

      // If we decoded an npub, add that user to results
      if (searchPubkey != null) {
        userResults.add(searchPubkey);
      } else {
        // Search for user profiles by name/about content
        try {
          // Query for Kind 0 (profile) events that contain the search query
          final profileFilter = Filter(
            kinds: [0], // Profile metadata events
            limit: 50,
          );

          final profileEvents = await nostrService.getEvents(
            filters: [profileFilter],
            limit: 50,
          );

          // Filter profiles that match the search query
          for (final event in profileEvents) {
            try {
              // Parse profile metadata
              final metadata =
                  jsonDecode(event.content) as Map<String, dynamic>;
              final name = metadata['name']?.toString() ?? '';
              final displayName = metadata['display_name']?.toString() ?? '';
              final about = metadata['about']?.toString() ?? '';
              final nip05 = metadata['nip05']?.toString() ?? '';

              // Check if any profile field matches the query
              if (name.toLowerCase().contains(query.toLowerCase()) ||
                  displayName.toLowerCase().contains(query.toLowerCase()) ||
                  about.toLowerCase().contains(query.toLowerCase()) ||
                  nip05.toLowerCase().contains(query.toLowerCase())) {
                userResults.add(event.pubkey);
              }
            } catch (e) {
              // Skip invalid profile metadata
            }
          }
        } catch (e) {
          Log.error('Failed to search user profiles: $e',
              name: 'SearchScreen', category: LogCategory.ui);
        }
      }

      // Also add authors from video results
      userResults.addAll(searchResults.map((video) => video.pubkey));

      // Search for hashtags across all videos in the network
      final hashtagResults = <String>{};

      // Get hashtags from search results
      for (final video in searchResults) {
        for (final tag in video.hashtags) {
          if (tag.toLowerCase().contains(query.toLowerCase())) {
            hashtagResults.add(tag);
          }
        }
      }

      // Also include hashtags from cached videos
      final allCachedHashtags = videoEventService.getAllHashtags();
      for (final tag in allCachedHashtags) {
        if (tag.toLowerCase().contains(query.toLowerCase())) {
          hashtagResults.add(tag);
        }
      }

      final sortedHashtags = hashtagResults.toList()..sort();

      // Apply loops-first sorting to video results
      searchResults.sort(VideoEvent.compareByLoopsThenTime);
      setState(() {
        _videoResults = searchResults;
        _hashtagResults = sortedHashtags;
        _userResults = userResults.toList();
        _isSearching = false;
      });

      Log.debug(
          'Search results for "$query": ${searchResults.length} videos (${searchResults.length - allCachedVideos.length} from relay), ${userResults.length} users, ${hashtagResults.length} hashtags',
          name: 'SearchScreen',
          category: LogCategory.ui);
    } catch (e) {
      Log.error('Search error: $e',
          name: 'SearchScreen', category: LogCategory.ui);
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _clearResults() {
    setState(() {
      _videoResults.clear();
      _userResults.clear();
      _hashtagResults.clear();
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: VineTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: VineTheme.vineGreen,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: VineTheme.whiteText),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: false, // Disable autofocus to prevent Chrome issues
            enableInteractiveSelection: true,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: VineTheme.whiteText),
            decoration: InputDecoration(
              hintText: 'Search videos, users, npub, hashtags...',
              hintStyle: const TextStyle(color: VineTheme.whiteText),
              border: InputBorder.none,
              suffixIcon: _currentQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: VineTheme.whiteText),
                      onPressed: () {
                        _searchController.clear();
                        _clearResults();
                      },
                    )
                  : const Icon(Icons.search, color: VineTheme.whiteText),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                _performSearch(value.trim());
              }
            },
          ),
          bottom: _currentQuery.isNotEmpty
              ? TabBar(
                  controller: _tabController,
                  indicatorColor: VineTheme.whiteText,
                  indicatorWeight: 2,
                  labelColor: VineTheme.whiteText,
                  unselectedLabelColor:
                      VineTheme.whiteText.withValues(alpha: 0.7),
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: 'Videos (${_videoResults.length})'),
                    Tab(text: 'Users (${_userResults.length})'),
                    Tab(text: 'Hashtags (${_hashtagResults.length})'),
                  ],
                )
              : null,
        ),
        body: _currentQuery.isEmpty
            ? _buildEmptyState()
            : _isSearching
                ? _buildLoadingState()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildVideoResults(),
                      _buildUserResults(),
                      _buildHashtagResults(),
                    ],
                  ),
      );

  Widget _buildEmptyState() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: VineTheme.secondaryText,
            ),
            SizedBox(height: 16),
            Text(
              'Search divine',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Find videos, users, and hashtags\nacross the decentralized network.',
              style: TextStyle(
                color: VineTheme.secondaryText,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _buildLoadingState() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: VineTheme.vineGreen),
            SizedBox(height: 16),
            Text(
              'Searching...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );

  Widget _buildVideoResults() {
    if (_videoResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 48,
              color: VineTheme.secondaryText,
            ),
            SizedBox(height: 16),
            Text(
              'No videos found',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
              ),
            ),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: VineTheme.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _videoResults.length,
      itemBuilder: (context, index) {
        final video = _videoResults[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: _VideoSearchResultCard(
            video: video,
            onTap: () => _openVideoInFeed(video, index),
          ),
        );
      },
    );
  }

  Widget _buildUserResults() {
    if (_userResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: VineTheme.secondaryText,
            ),
            SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
              ),
            ),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: VineTheme.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final userProfileService = ref.watch(userProfileServiceProvider);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _userResults.length,
      itemBuilder: (context, index) {
        final pubkey = _userResults[index];
        final profile = userProfileService.getCachedProfile(pubkey);
        return _UserSearchResultCard(
          pubkey: pubkey,
          profile: profile,
          onTap: () => _openUserProfile(pubkey),
        );
      },
    );
  }

  Widget _buildHashtagResults() {
    if (_hashtagResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tag,
              size: 48,
              color: VineTheme.secondaryText,
            ),
            SizedBox(height: 16),
            Text(
              'No hashtags found',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
              ),
            ),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: VineTheme.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _hashtagResults.length,
      itemBuilder: (context, index) {
        final hashtag = _hashtagResults[index];
        return _HashtagSearchResultCard(
          hashtag: hashtag,
          onTap: () => _searchHashtag(hashtag),
        );
      },
    );
  }

  void _openUserProfile(String pubkey) {
    // Use main navigation to switch to profile tab
    mainNavigationKey.currentState?.navigateToProfile(pubkey);
  }

  void _searchHashtag(String hashtag) {
    _searchController.text = '#$hashtag';
    _tabController.animateTo(0); // Switch to videos tab
  }

  void _openVideoInFeed(VideoEvent video, int index) {
    // Close search screen first
    Navigator.of(context).pop();

    // Get video manager to add all search result videos for seamless playback
    final videoManager = ref.read(videoManagerProvider.notifier);

    // Add all video results to VideoManager for the search results feed
    for (final searchVideo in _videoResults) {
      try {
        videoManager.addVideoEvent(searchVideo);
      } catch (e) {
        // Video might already exist, that's ok
      }
    }

    // Create a feed from search results starting at the tapped video
    mainNavigationKey.currentState?.playSpecificVideo(_videoResults, index);
  }
}

class _VideoSearchResultCard extends StatelessWidget {
  const _VideoSearchResultCard({required this.video, this.onTap});
  final VideoEvent video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.grey[900],
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Video thumbnail placeholder
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: VineTheme.vineGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (video.title?.isNotEmpty == true) ...[
                            SelectableText(
                              video.title!,
                              style: const TextStyle(
                                color: VineTheme.whiteText,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (video.content.isNotEmpty) ...[
                            SelectableText(
                              video.content,
                              style: const TextStyle(
                                color: VineTheme.secondaryText,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 4),
                          ],
                          SelectableText(
                            'by ${video.displayPubkey} • ${video.relativeTime}',
                            style: const TextStyle(
                              color: VineTheme.secondaryText,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (video.hashtags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: video.hashtags
                        .take(3)
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: VineTheme.vineGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '#$tag',
                              style: const TextStyle(
                                color: VineTheme.vineGreen,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _UserSearchResultCard extends StatelessWidget {
  const _UserSearchResultCard({
    required this.pubkey,
    required this.profile,
    required this.onTap,
  });
  final String pubkey;
  final dynamic profile; // UserProfile type would be defined elsewhere
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.grey[900],
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: VineTheme.vineGreen,
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
          title: SelectableText(
            profile?.displayName ?? 'Anonymous',
            style: const TextStyle(
              color: VineTheme.whiteText,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${pubkey.substring(0, 16)}...',
            style: const TextStyle(
              color: VineTheme.secondaryText,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios,
            color: VineTheme.secondaryText,
            size: 16,
          ),
          onTap: onTap,
        ),
      );
}

class _HashtagSearchResultCard extends ConsumerStatefulWidget {
  const _HashtagSearchResultCard({
    required this.hashtag,
    required this.onTap,
  });
  final String hashtag;
  final VoidCallback onTap;

  @override
  ConsumerState<_HashtagSearchResultCard> createState() =>
      _HashtagSearchResultCardState();
}

class _HashtagSearchResultCardState
    extends ConsumerState<_HashtagSearchResultCard> {
  int _videoCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHashtagCount();
  }

  Future<void> _loadHashtagCount() async {
    try {
      final nostrService = ref.read(nostrServiceProvider);

      // Query for videos with this hashtag
      // Note: Nostr SDK Filter doesn't have a direct 'tags' parameter
      // We need to get all videos and filter client-side
      final filter = Filter(
        kinds: [32222], // Video events
        limit: 1000,
      );

      final events = await nostrService.getEvents(
        filters: [filter],
        limit: 1000,
      );

      // Filter events that have this hashtag
      final eventsWithHashtag = events.where((event) {
        // Check if event has 't' tags with this hashtag
        for (final tag in event.tags) {
          if (tag.length >= 2 &&
              tag[0] == 't' &&
              tag[1].toLowerCase() == widget.hashtag.toLowerCase()) {
            return true;
          }
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _videoCount = eventsWithHashtag.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Fall back to cached count
      final videoEventService = ref.read(videoEventServiceProvider);
      final allVideos = <VideoEvent>[];
      allVideos.addAll(videoEventService.discoveryVideos);
      allVideos.addAll(videoEventService.homeFeedVideos);

      final uniqueVideos = <String>{};
      for (final video in allVideos) {
        if (video.hashtags
            .any((tag) => tag.toLowerCase() == widget.hashtag.toLowerCase())) {
          uniqueVideos.add(video.id);
        }
      }

      if (mounted) {
        setState(() {
          _videoCount = uniqueVideos.length;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: VineTheme.vineGreen.withValues(alpha: 0.2),
            border: Border.all(color: VineTheme.vineGreen, width: 1),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: VineTheme.vineGreen,
                  ),
                )
              : const Icon(
                  Icons.tag,
                  color: VineTheme.vineGreen,
                  size: 20,
                ),
        ),
        title: Text(
          '#${widget.hashtag}',
          style: const TextStyle(
            color: VineTheme.whiteText,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          _isLoading
              ? 'Loading...'
              : _videoCount > 0
                  ? '$_videoCount ${_videoCount == 1 ? 'video' : 'videos'} with this hashtag'
                  : 'Tap to search videos with this hashtag',
          style: const TextStyle(
            color: VineTheme.secondaryText,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.search,
          color: VineTheme.secondaryText,
          size: 16,
        ),
        onTap: widget.onTap,
      ),
    );
  }
}
