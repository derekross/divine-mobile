// ABOUTME: Comprehensive widget test helper to fix UI validation failures across test suite
// ABOUTME: Provides proper mocking for Riverpod providers, video management, and platform channels


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/models/video_state.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/social_service.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/theme/vine_theme.dart';

/// Mock classes for testing
class MockSocialService extends Mock implements SocialService {}

class MockIVideoManager extends Mock implements IVideoManager {}

class MockNostrService extends Mock implements INostrService {}

class MockVideoEventService extends Mock implements VideoEventService {}

/// Configuration for widget test setup
class WidgetTestConfig {
  final bool mockVideoManager;
  final bool mockSocialService;
  final bool mockNostrService;
  final bool mockPlatformChannels;
  final List<VideoEvent> preloadedVideos;

  const WidgetTestConfig({
    this.mockVideoManager = true,
    this.mockSocialService = true,
    this.mockNostrService = true,
    this.mockPlatformChannels = true,
    this.preloadedVideos = const [],
  });
}

/// Comprehensive widget test helper that addresses common failure patterns
class WidgetTestHelper {
  static MockSocialService? _mockSocialService;
  static MockIVideoManager? _mockVideoManager;
  static MockNostrService? _mockNostrService;
  static MockVideoEventService? _mockVideoEventService;

  /// Initialize platform channel mocking to prevent UnimplementedError
  static void initializePlatformChannels() {
    // Mock video_player channel to prevent initialization errors
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.io/videoPlayer'),
            (call) async {
      switch (call.method) {
        case 'init':
          return null;
        case 'create':
          return {'textureId': 1};
        case 'setLooping':
          return null;
        case 'setVolume':
          return null;
        case 'setPlaybackSpeed':
          return null;
        case 'play':
          return null;
        case 'pause':
          return null;
        case 'seekTo':
          return null;
        case 'position':
          return {'position': 0};
        case 'dispose':
          return null;
        default:
          return null;
      }
    });

    // Mock camera channel to prevent camera-related errors
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'), (call) async {
      switch (call.method) {
        case 'availableCameras':
          return [];
        case 'initialize':
          return null;
        case 'dispose':
          return null;
        default:
          return null;
      }
    });

    // Mock path_provider for file operations
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      switch (call.method) {
        case 'getTemporaryDirectory':
          return '/tmp';
        case 'getApplicationDocumentsDirectory':
          return '/tmp/docs';
        case 'getApplicationSupportDirectory':
          return '/tmp/support';
        default:
          return null;
      }
    });
  }

  /// Create mock services with proper default behavior
  static void initializeMockServices() {
    // Only create mocks if they don't exist
    if (_mockSocialService != null) {
      reset(_mockSocialService!);
    } else {
      _mockSocialService = MockSocialService();
    }

    if (_mockVideoManager != null) {
      reset(_mockVideoManager!);
    } else {
      _mockVideoManager = MockIVideoManager();
    }

    if (_mockNostrService != null) {
      reset(_mockNostrService!);
    } else {
      _mockNostrService = MockNostrService();
    }

    if (_mockVideoEventService != null) {
      reset(_mockVideoEventService!);
    } else {
      _mockVideoEventService = MockVideoEventService();
    }

    // Configure video manager defaults
    when(_mockVideoManager!.videos).thenReturn([]);
    when(_mockVideoManager!.readyVideos).thenReturn([]);

    // Configure nostr service defaults
    when(_mockNostrService!.isInitialized).thenReturn(true);
    when(_mockNostrService!.initialize()).thenAnswer((_) async {});
  }

  /// Create a test video event with sensible defaults
  static VideoEvent createTestVideoEvent({
    String? id,
    String? pubkey,
    String? videoUrl,
    String? content,
    String? thumbnailUrl,
    List<String>? hashtags,
    int? createdAt,
  }) {
    return VideoEvent(
      id: id ?? 'test_video_${DateTime.now().millisecondsSinceEpoch}',
      pubkey: pubkey ?? 'test_pubkey',
      videoUrl: videoUrl ?? 'https://example.com/video.mp4',
      content: content ?? 'Test video content',
      timestamp: DateTime.now(),
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      thumbnailUrl: thumbnailUrl,
      hashtags: hashtags ?? ['test'],
    );
  }

  /// Create video state for a given video event
  static VideoState createTestVideoState(
    VideoEvent video, {
    VideoLoadingState loadingState = VideoLoadingState.ready,
  }) {
    return VideoState(
      event: video,
      loadingState: loadingState,
    );
  }

  /// Setup video manager to properly handle a specific video
  static void setupVideoManagerForVideo(VideoEvent video) {
    final videoState = createTestVideoState(video);

    // Ensure video manager knows about this video
    when(_mockVideoManager!.getVideoState(video.id)).thenReturn(videoState);
    when(_mockVideoManager!.preloadVideo(video.id)).thenAnswer((_) async {});
    when(_mockVideoManager!.addVideoEvent(video)).thenAnswer((_) async {});

    // Mock the video being available in manager state
    when(_mockVideoManager!.videos).thenReturn([video]);
    when(_mockVideoManager!.readyVideos).thenReturn([video]);
  }

  /// Create provider overrides for widget testing
  static List<Override> createProviderOverrides({
    WidgetTestConfig config = const WidgetTestConfig(),
    List<VideoEvent>? videos,
  }) {
    final overrides = <Override>[];

    if (config.mockSocialService) {
      overrides
          .add(socialServiceProvider.overrideWithValue(_mockSocialService!));
    }

    if (config.mockVideoManager) {
      // For now, we'll skip the video manager provider override
      // The individual mocking should be sufficient
      // TODO: Create proper mock state if needed
    }

    if (config.mockNostrService) {
      overrides.add(nostrServiceProvider.overrideWithValue(_mockNostrService!));
    }

    // Setup preloaded videos if provided
    if (videos != null) {
      for (final video in videos) {
        setupVideoManagerForVideo(video);
      }
    }

    return overrides;
  }

  /// Create a properly configured test widget wrapper
  static Widget createTestApp({
    required Widget child,
    WidgetTestConfig config = const WidgetTestConfig(),
    List<VideoEvent>? preloadedVideos,
  }) {
    final container = ProviderContainer(
      overrides: createProviderOverrides(
        config: config,
        videos: preloadedVideos ?? config.preloadedVideos,
      ),
    );

    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: VineTheme.theme,
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  /// Comprehensive setup for widget tests - call this in setUp()
  static void setup({WidgetTestConfig config = const WidgetTestConfig()}) {
    if (config.mockPlatformChannels) {
      initializePlatformChannels();
    }
    initializeMockServices();
  }

  /// Clean up after tests - call this in tearDown() if needed
  static void tearDown() {
    // Clear method channel handlers
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.io/videoPlayer'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  }

  /// Create a widget test wrapper that handles common test scenarios
  static void testWidget(
    String description,
    Future<void> Function(WidgetTester tester) testFunction, {
    WidgetTestConfig config = const WidgetTestConfig(),
  }) {
    testWidgets(description, (tester) async {
      setup(config: config);
      try {
        await testFunction(tester);
      } finally {
        tearDown();
      }
    });
  }

  /// Pump a widget with proper settling and error handling
  static Future<void> pumpWidget(
    WidgetTester tester,
    Widget widget, {
    WidgetTestConfig config = const WidgetTestConfig(),
    List<VideoEvent>? preloadedVideos,
  }) async {
    final testApp = createTestApp(
      child: widget,
      config: config,
      preloadedVideos: preloadedVideos,
    );

    await tester.pumpWidget(testApp);

    // Allow frames to settle but with timeout to prevent hanging
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  /// Getters for accessing mock services in tests
  static MockSocialService get mockSocialService => _mockSocialService!;
  static MockIVideoManager get mockVideoManager => _mockVideoManager!;
  static MockNostrService get mockNostrService => _mockNostrService!;
  static MockVideoEventService get mockVideoEventService =>
      _mockVideoEventService!;
}
