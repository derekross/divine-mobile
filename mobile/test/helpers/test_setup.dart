// ABOUTME: Centralized test setup utilities for consistent test environment
// ABOUTME: Provides container creation with common overrides and test implementations

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'test_video_controller.dart';

/// Factory for creating video controllers in tests
typedef VideoControllerFactory = VideoPlayerController Function(String url);

/// Test setup utilities
class TestSetup {
  /// Create a provider container with test-appropriate overrides
  static ProviderContainer createContainer({
    List<Override>? overrides,
    VideoControllerFactory? videoControllerFactory,
  }) {
    return ProviderContainer(
      overrides: [
        // Add video controller factory override if needed
        // This would override the actual video player creation
        ...?overrides,
      ],
    );
  }

  /// Initialize Flutter test environment
  static void initializeTests() {
    TestWidgetsFlutterBinding.ensureInitialized();
  }

  /// Create a test video controller
  static VideoPlayerController createTestVideoController(String url) {
    return TestVideoPlayerController(url);
  }
}
