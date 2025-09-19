// ABOUTME: App lifecycle handler that pauses all videos when app goes to background
// ABOUTME: Ensures videos never play when app is not visible and manages background battery usage

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/background_activity_manager.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Handles app lifecycle events for video playback
class AppLifecycleHandler extends ConsumerStatefulWidget {
  const AppLifecycleHandler({
    required this.child,
    super.key,
  });
  final Widget child;

  @override
  ConsumerState<AppLifecycleHandler> createState() =>
      _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends ConsumerState<AppLifecycleHandler>
    with WidgetsBindingObserver {
  late final BackgroundActivityManager _backgroundManager;
  bool _tickersEnabled = true;

  @override
  void initState() {
    super.initState();
    _backgroundManager = BackgroundActivityManager();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final visibilityManager = ref.read(videoVisibilityManagerProvider);

    // Notify background activity manager first
    _backgroundManager.onAppLifecycleStateChanged(state);

    switch (state) {
      case AppLifecycleState.resumed:
        Log.info(
          '📱 App resumed - enabling visibility-based playback',
          name: 'AppLifecycleHandler',
          category: LogCategory.system,
        );
        if (!_tickersEnabled) {
          setState(() => _tickersEnabled = true);
        }
        visibilityManager.resumeVisibilityBasedPlayback();

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        Log.info(
          '📱 App backgrounded - pausing all videos and suspending background activities',
          name: 'AppLifecycleHandler',
          category: LogCategory.system,
        );
        if (_tickersEnabled) {
          setState(() => _tickersEnabled = false);
        }
        // Execute async to prevent blocking scene update
        Future.microtask(() => visibilityManager.pauseAllVideos());

      case AppLifecycleState.detached:
        // App is being terminated
        break;
    }
  }

  @override
  Widget build(BuildContext context) => TickerMode(
        enabled: _tickersEnabled,
        child: widget.child,
      );
}
