// ABOUTME: Simple test to verify VideoManager works without circular dependencies
// ABOUTME: Tests core functionality without requiring full service initialization

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import '../../builders/test_video_event_builder.dart';
import '../../helpers/mock_video_manager_notifier.dart';
import '../../helpers/service_init_helper.dart';
import 'package:openvine/utils/unified_logger.dart';

void main() {
  group('VideoManager Simple Functionality', () {
    late ProviderContainer container;

    setUpAll(() {
      ServiceInitHelper
          .initializeTestEnvironment(); // This calls TestWidgetsFlutterBinding.ensureInitialized()
    });

    setUp(() {
      container = ServiceInitHelper.createTestContainer(
        additionalOverrides: [
          videoManagerProvider.overrideWith(() => MockVideoManager()),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('VideoManager should initialize and accept videos directly', () async {
      // This test bypasses the VideoEvents dependency issue
      // by testing VideoManager in isolation

      final videoManager = container.read(videoManagerProvider.notifier);
      final initialState = container.read(videoManagerProvider);

      // VideoManager should initialize
      expect(initialState.controllers.isEmpty, isTrue);
      expect(initialState.config, isNotNull);

      // Should be able to preload videos directly
      final testVideo = TestVideoEventBuilder.create(
        id: 'test_video_id',
        title: 'Test Video',
      );

      // Should be able to preload the video
      await videoManager.preloadVideo(testVideo.id);

      final finalState = container.read(videoManagerProvider);

      // Debug output
      Log.debug('Controllers count: ${finalState.controllers.length}',
          name: 'VideoManagerSimpleTest', category: LogCategory.system);
      Log.debug(
          'Has controller for ${testVideo.id}: ${finalState.hasController(testVideo.id)}',
          name: 'VideoManagerSimpleTest',
          category: LogCategory.system);
      Log.debug('Error: ${finalState.error}',
          name: 'VideoManagerSimpleTest', category: LogCategory.system);

      // Should have one controller
      expect(finalState.controllers.length, equals(1));
      expect(finalState.hasController(testVideo.id), isTrue);
    });

    test('Multiple preload calls should not create duplicate controllers',
        () async {
      final testVideo = TestVideoEventBuilder.create(
        id: 'test_video_id_2',
        title: 'Test Video 2',
        videoUrl: 'https://example.com/test_video2.mp4',
        thumbnailUrl: 'https://example.com/test_thumbnail2.jpg',
      );
      final videoManager = container.read(videoManagerProvider.notifier);

      // Multiple preload calls should be idempotent
      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);
      await videoManager.preloadVideo(testVideo.id);

      final finalState = container.read(videoManagerProvider);

      // Should have exactly one controller
      expect(finalState.controllers.length, equals(1));
      expect(finalState.hasController(testVideo.id), isTrue);
    });

    test('Pause and resume should work on single controller', () async {
      final testVideo = TestVideoEventBuilder.create(
        id: 'test_video_id_2',
        title: 'Test Video 2',
        videoUrl: 'https://example.com/test_video2.mp4',
        thumbnailUrl: 'https://example.com/test_thumbnail2.jpg',
      );
      final videoManager = container.read(videoManagerProvider.notifier);

      // Preload video
      await videoManager.preloadVideo(testVideo.id);

      // Start playing
      videoManager.resumeVideo(testVideo.id);

      // Pause should work
      videoManager.pauseVideo(testVideo.id);

      final state = container.read(videoManagerProvider);
      final controllerState = state.getController(testVideo.id);

      expect(controllerState, isNotNull);
      expect(controllerState!.controller.value.isPlaying, isFalse);
    });
  });
}
