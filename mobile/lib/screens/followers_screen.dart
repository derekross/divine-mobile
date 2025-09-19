// ABOUTME: Screen displaying list of users who follow the profile being viewed
// ABOUTME: Shows user profiles with follow/unfollow buttons and navigation to their profiles

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostr_sdk/nostr_sdk.dart' as nostr_sdk;
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/screens/profile_screen.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/user_profile_tile.dart';

class FollowersScreen extends ConsumerStatefulWidget {
  const FollowersScreen(
      {super.key, required this.pubkey, required this.displayName});

  final String pubkey;
  final String displayName;

  @override
  ConsumerState<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends ConsumerState<FollowersScreen> {
  final List<String> _followers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  Future<void> _loadFollowers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Start streaming followers from Nostr - updates will happen in real-time
      await _fetchFollowersFromNostr(widget.pubkey);
    } catch (e) {
      Log.error('Failed to load followers: $e',
          name: 'FollowersScreen', category: LogCategory.ui);
      if (mounted) {
        setState(() {
          _error = 'Failed to load followers';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchFollowersFromNostr(String pubkey) async {
    final nostrService = ref.read(nostrServiceProvider);

    // Subscribe to kind 3 events that mention this pubkey in p tags
    final subscription = nostrService.subscribeToEvents(
      filters: [
        nostr_sdk.Filter(
          kinds: [3], // Contact lists
          p: [pubkey], // Events that mention this pubkey
        ),
      ],
    );

    // Process events immediately as they arrive for real-time updates
    subscription.listen(
      (event) {
        // Each author who has this pubkey in their contact list is a follower
        if (!_followers.contains(event.pubkey)) {
          if (mounted) {
            setState(() {
              _followers.add(event.pubkey);
              _isLoading =
                  false; // Stop loading as soon as we have first follower
            });
          }
        }
      },
      onError: (error) {
        Log.error('Error in followers subscription: $error',
            name: 'FollowersScreen', category: LogCategory.relay);
        if (mounted) {
          setState(() {
            _error = 'Failed to load followers';
            _isLoading = false;
          });
        }
      },
    );

    // Complete loading state after a short delay even if no followers found
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
          '${widget.displayName}\'s Followers',
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
              onPressed: _loadFollowers,
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

    if (_followers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'No followers yet',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _followers.length,
      itemBuilder: (context, index) {
        final followerPubkey = _followers[index];
        return UserProfileTile(
          pubkey: followerPubkey,
          onTap: () => _navigateToProfile(followerPubkey),
        );
      },
    );
  }

  void _navigateToProfile(String pubkey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(profilePubkey: pubkey),
      ),
    );
  }
}
