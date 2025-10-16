// ABOUTME: Screen displaying list of users followed by the profile being viewed
// ABOUTME: Shows user profiles with follow/unfollow buttons and navigation to their profiles

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostr_sdk/nostr_sdk.dart' as nostr_sdk;
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/router/nav_extensions.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/user_profile_tile.dart';

class FollowingScreen extends ConsumerStatefulWidget {
  const FollowingScreen(
      {super.key, required this.pubkey, required this.displayName});

  final String pubkey;
  final String displayName;

  @override
  ConsumerState<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends ConsumerState<FollowingScreen> {
  List<String> _following = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final socialService = ref.read(socialServiceProvider);

      // If viewing current user's following, use cached data
      final authService = ref.read(authServiceProvider);
      if (widget.pubkey == authService.currentPublicKeyHex) {
        final following = socialService.followingPubkeys;
        if (mounted) {
          setState(() {
            _following = following;
            _isLoading = false;
          });
        }
        return;
      }

      // Otherwise start streaming following list from Nostr - updates will happen in real-time
      await _fetchFollowingFromNostr(widget.pubkey);
    } catch (e) {
      Log.error('Failed to load following: $e',
          name: 'FollowingScreen', category: LogCategory.ui);
      if (mounted) {
        setState(() {
          _error = 'Failed to load following';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchFollowingFromNostr(String pubkey) async {
    final nostrService = ref.read(nostrServiceProvider);

    // Subscribe to the user's kind 3 contact list events
    final subscription = nostrService.subscribeToEvents(
      filters: [
        nostr_sdk.Filter(
          authors: [pubkey],
          kinds: [3], // Contact lists
          limit: 1, // Get most recent only
        ),
      ],
    );

    // Process events immediately as they arrive for real-time updates
    subscription.listen(
      (event) {
        // Extract followed pubkeys from 'p' tags
        final newFollowing = <String>[];
        for (final tag in event.tags) {
          if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
            final followedPubkey = tag[1];
            if (!newFollowing.contains(followedPubkey)) {
              newFollowing.add(followedPubkey);
            }
          }
        }

        // Update UI immediately with the complete following list from this event
        if (mounted) {
          setState(() {
            _following = newFollowing;
            _isLoading =
                false; // Stop loading as soon as we have the contact list
          });
        }
      },
      onError: (error) {
        Log.error('Error in following subscription: $error',
            name: 'FollowingScreen', category: LogCategory.relay);
        if (mounted) {
          setState(() {
            _error = 'Failed to load following';
            _isLoading = false;
          });
        }
      },
    );

    // Complete loading state after a short delay even if no contact list found
    Timer(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VineTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: VineTheme.backgroundColor,
        title: Text(
          '${widget.displayName}\'s Following',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.purple),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFollowing,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_following.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_outlined, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'Not following anyone yet',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _following.length,
      itemBuilder: (context, index) {
        final followingPubkey = _following[index];
        return UserProfileTile(
          pubkey: followingPubkey,
          onTap: () => _navigateToProfile(followingPubkey),
        );
      },
    );
  }

  void _navigateToProfile(String pubkey) {
    context.goProfile(pubkey, 0);
  }
}
