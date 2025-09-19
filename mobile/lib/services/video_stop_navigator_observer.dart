// ABOUTME: NavigatorObserver that stops all videos on any route change
// ABOUTME: Ensures videos stop when navigating away to prevent background playback

import 'package:flutter/material.dart';
import 'package:openvine/services/global_video_registry.dart';
import 'package:openvine/utils/unified_logger.dart';

class VideoStopNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stopAllVideos('didPush', route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _stopAllVideos('didPop', route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _stopAllVideos('didReplace', newRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _stopAllVideos('didRemove', route.settings.name);
  }

  void _stopAllVideos(String action, String? routeName) {
    try {
      GlobalVideoRegistry().pauseAllControllers();
      Log.info(
          '⏸️ Stopped all videos on navigation $action to route: ${routeName ?? 'unnamed'}',
          name: 'VideoStopNavigatorObserver',
          category: LogCategory.system);
    } catch (e) {
      Log.error('Failed to stop videos on navigation: $e',
          name: 'VideoStopNavigatorObserver', category: LogCategory.system);
    }
  }
}
