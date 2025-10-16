// ABOUTME: Navigation extension helpers for clean GoRouter call-sites
// ABOUTME: Provides goHome/goExplore/goNotifications/goProfile/pushCamera/pushSettings (hashtag available via goHashtag)

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:openvine/utils/nostr_encoding.dart';
import 'route_utils.dart';

extension NavX on BuildContext {
  // Tab bases
  void goHome([int index = 0]) => go(buildRoute(
        RouteContext(type: RouteType.home, videoIndex: index),
      ));

  void goExplore([int index = 0]) => go(buildRoute(
        RouteContext(type: RouteType.explore, videoIndex: index),
      ));

  void goNotifications([int index = 0]) => go(buildRoute(
        RouteContext(type: RouteType.notifications, videoIndex: index),
      ));

  void goHashtag(String tag, [int index = 0]) => go(buildRoute(
        RouteContext(
          type: RouteType.hashtag,
          hashtag: tag,
          videoIndex: index,
        ),
      ));

  void goProfile(String npubOrHex, [int index = 0]) {
    final npub = npubOrHex.startsWith('npub')
        ? npubOrHex
        : NostrEncoding.encodePublicKey(npubOrHex); // hex -> npub
    go(buildRoute(
      RouteContext(
        type: RouteType.profile,
        npub: npub,
        videoIndex: index,
      ),
    ));
  }

  void pushProfile(String npubOrHex, [int index = 0]) {
    final npub = npubOrHex.startsWith('npub')
        ? npubOrHex
        : NostrEncoding.encodePublicKey(npubOrHex);
    push(buildRoute(
      RouteContext(
        type: RouteType.profile,
        npub: npub,
        videoIndex: index,
      ),
    ));
  }

  // Optional pushes (non-tab routes)
  Future<void> pushCamera() => push('/camera');
  Future<void> pushSettings() => push('/settings');
}
