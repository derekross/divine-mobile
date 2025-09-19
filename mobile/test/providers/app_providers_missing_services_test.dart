// ABOUTME: Tests for missing service providers to ensure all services used by legacy Provider widgets are available through Riverpod
// ABOUTME: TDD approach - these tests should FAIL initially, then pass after implementing the missing providers

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/services/content_deletion_service.dart';
import 'package:openvine/services/content_reporting_service.dart';
import 'package:openvine/services/curated_list_service.dart';
import 'package:openvine/services/video_sharing_service.dart';
import 'package:openvine/services/video_visibility_manager.dart';

void main() {
  group('Missing Service Providers Tests (TDD)', () {
    late ProviderContainer container;

    setUpAll(() async {
      // Initialize Hive for tests
      await Hive.initFlutter('test');
    });

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('VideoManager provider should exist and return correct instance', () {
      // VideoManager provider exists in video_manager_providers.dart
      final videoManager = container.read(videoManagerProvider.notifier);
      expect(videoManager, isNotNull);
      // Note: VideoManager doesn't implement IVideoManager interface directly,
      // but provides the same functionality through Riverpod notifier pattern
    });

    test('ContentDeletionService provider should exist', () {
      // ContentDeletionService provider exists in app_providers.dart
      final service = container.read(contentDeletionServiceProvider);
      expect(service, isA<ContentDeletionService>());
    });

    test('ContentReportingService provider should exist', () {
      // ContentReportingService provider exists in app_providers.dart
      final service = container.read(contentReportingServiceProvider);
      expect(service, isA<ContentReportingService>());
    });

    test('CuratedListService provider should exist', () {
      // CuratedListService provider exists in app_providers.dart
      final service = container.read(curatedListServiceProvider);
      expect(service, isA<CuratedListService>());
    });

    test('VideoSharingService provider should exist', () {
      // VideoSharingService provider exists in app_providers.dart
      final service = container.read(videoSharingServiceProvider);
      expect(service, isA<VideoSharingService>());
    });

    test('VideoVisibilityManager provider should exist (should already pass)',
        () {
      // This should PASS - videoVisibilityManagerProvider already exists
      final service = container.read(videoVisibilityManagerProvider);
      expect(service, isA<VideoVisibilityManager>());
    });

    test('All provider dependency injection should work correctly', () {
      // All providers should be available and working
      expect(() {
        container.read(videoManagerProvider.notifier);
        container.read(contentDeletionServiceProvider);
        container.read(contentReportingServiceProvider);
        container.read(curatedListServiceProvider);
        container.read(videoSharingServiceProvider);
        container.read(videoVisibilityManagerProvider);
      }, returnsNormally);

      // Verify they return expected types
      expect(container.read(videoManagerProvider.notifier), isNotNull);
      expect(container.read(contentDeletionServiceProvider),
          isA<ContentDeletionService>());
      expect(container.read(contentReportingServiceProvider),
          isA<ContentReportingService>());
      expect(container.read(curatedListServiceProvider),
          isA<CuratedListService>());
      expect(container.read(videoSharingServiceProvider),
          isA<VideoSharingService>());
      expect(container.read(videoVisibilityManagerProvider),
          isA<VideoVisibilityManager>());
    });
  });
}
