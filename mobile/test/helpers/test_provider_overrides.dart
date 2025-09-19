// ABOUTME: Common provider overrides for tests to inject test implementations
// ABOUTME: Provides consistent test environment setup across all test files

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/state/video_manager_state.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'test_video_controller.dart';

/// Test VideoManager that provides a mock implementation for tests
class TestVideoManager extends VideoManager {
  @override
  VideoManagerState build() {
    final config = VideoManagerConfig.wifi(); // Simple config for tests

    // Set up cleanup on dispose
    ref.onDispose(() {
      // Cleanup without starting any timers or listeners
    });

    // Return a simple test state without setting up real listeners or timers
    // This avoids the Nostr service initialization issues in tests
    return VideoManagerState(
      config: config,
      currentTab: 0, // Default tab
    );
  }

  // Override the methods to prevent actual Nostr connections
  @override
  void addVideoEvent(VideoEvent event) {
    // Do nothing in tests
  }

  @override
  Future<void> preloadVideo(String videoId,
      {PreloadPriority priority = PreloadPriority.nearby}) async {
    // Do nothing in tests
  }

  @override
  void pauseAllVideos() {
    // Do nothing in tests
  }
}

/// Factory for creating test video controllers
VideoPlayerController testVideoControllerFactory(String url) {
  return TestVideoPlayerController(url);
}

/// Common provider overrides for tests
List<Override> getTestProviderOverrides({
  List<Override>? additionalOverrides,
  TestVideoManager? testVideoManager,
  dynamic mockSocialService,
  dynamic mockAuthService,
}) {
  final overrides = <Override>[];

  // Add video manager override - create default if not provided
  final videoManager = testVideoManager ?? TestVideoManager();
  overrides.add(videoManagerProvider.overrideWith(() => videoManager));

  // Add social service override if provided
  if (mockSocialService != null) {
    overrides.add(socialServiceProvider.overrideWithValue(mockSocialService));
  }

  // Add auth service override if provided
  if (mockAuthService != null) {
    overrides.add(authServiceProvider.overrideWithValue(mockAuthService));
  }

  // Add video controller factory override when available
  // overrides.add(videoControllerFactoryProvider.overrideWithValue(testVideoControllerFactory));

  // Add any additional overrides
  if (additionalOverrides != null) {
    overrides.addAll(additionalOverrides);
  }

  return overrides;
}

/// Widget wrapper with common provider setup for tests
Widget createTestWidget({
  required Widget child,
  TestVideoManager? testVideoManager,
  dynamic mockSocialService,
  dynamic mockAuthService,
  List<Override>? additionalOverrides,
}) {
  return ProviderScope(
    overrides: getTestProviderOverrides(
      testVideoManager: testVideoManager,
      mockSocialService: mockSocialService,
      mockAuthService: mockAuthService,
      additionalOverrides: additionalOverrides,
    ),
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

/// Create common fallback values for mocktail
void registerCommonFallbackValues() {
  // Register VideoEvent fallback
  registerFallbackValue(VideoEvent(
    id: 'fallback-id',
    pubkey: 'fallback-pubkey',
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    content: '',
    timestamp: DateTime.now(),
  ));
}
