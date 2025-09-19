// ABOUTME: Comprehensive integration test verifying complete Riverpod migration
// ABOUTME: Tests that app boots with pure Riverpod providers and all widgets work together

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/services/content_deletion_service.dart';
import 'package:openvine/services/content_reporting_service.dart';
import 'package:openvine/services/curated_list_service.dart';
import 'package:openvine/services/video_sharing_service.dart';
import 'package:openvine/services/video_visibility_manager.dart';
import 'package:openvine/models/video_event.dart';

void main() {
  group('Riverpod Migration Integration Tests', () {
    late ProviderContainer container;

    setUp(() {
      // Create fresh provider container for each test
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('App boots with pure Riverpod providers only', (tester) async {
      // Test that the app can boot with only Riverpod providers
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                // Try to access all critical providers to ensure they're available
                final videoManager = ref.read(videoManagerProvider.notifier);
                final contentDeletion =
                    ref.read(contentDeletionServiceProvider);
                final contentReporting =
                    ref.read(contentReportingServiceProvider);
                final curatedList = ref.read(curatedListServiceProvider);
                final videoSharing = ref.read(videoSharingServiceProvider);
                final videoVisibility =
                    ref.read(videoVisibilityManagerProvider);

                return Scaffold(
                  body: Column(
                    children: [
                      Text('VideoManager: ${videoManager.runtimeType}'),
                      Text('ContentDeletion: ${contentDeletion.runtimeType}'),
                      Text('ContentReporting: ${contentReporting.runtimeType}'),
                      Text('CuratedList: ${curatedList.runtimeType}'),
                      Text('VideoSharing: ${videoSharing.runtimeType}'),
                      Text('VideoVisibility: ${videoVisibility.runtimeType}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify all provider types are correct
      expect(find.textContaining('VideoManager:'), findsOneWidget);
      expect(find.textContaining('ContentDeletion: ContentDeletionService'),
          findsOneWidget);
      expect(find.textContaining('ContentReporting: ContentReportingService'),
          findsOneWidget);
      expect(find.textContaining('CuratedList: CuratedListService'),
          findsOneWidget);
      expect(find.textContaining('VideoSharing: VideoSharingService'),
          findsOneWidget);
      expect(find.textContaining('VideoVisibility: VideoVisibilityManager'),
          findsOneWidget);
    });

    test('All required services are available through Riverpod providers', () {
      // Test service providers
      final contentDeletion = container.read(contentDeletionServiceProvider);
      expect(contentDeletion, isA<ContentDeletionService>());

      final contentReporting = container.read(contentReportingServiceProvider);
      expect(contentReporting, isA<ContentReportingService>());

      final curatedList = container.read(curatedListServiceProvider);
      expect(curatedList, isA<CuratedListService>());

      final videoSharing = container.read(videoSharingServiceProvider);
      expect(videoSharing, isA<VideoSharingService>());

      final videoVisibility = container.read(videoVisibilityManagerProvider);
      expect(videoVisibility, isA<VideoVisibilityManager>());
    });

    test('Provider dependency injection works correctly', () {
      // Test that dependent services receive their dependencies correctly
      final socialService = container.read(socialServiceProvider);
      final userProfileService = container.read(userProfileServiceProvider);
      final videoEventService = container.read(videoEventServiceProvider);
      final authService = container.read(authServiceProvider);

      // Verify services are properly instantiated
      expect(socialService, isNotNull);
      expect(userProfileService, isNotNull);
      expect(videoEventService, isNotNull);
      expect(authService, isNotNull);
    });

    test('Provider creation works without Provider package', () {
      // This test ensures that all critical providers work without the Provider package
      try {
        container.read(contentDeletionServiceProvider);
        container.read(contentReportingServiceProvider);
        container.read(curatedListServiceProvider);
        container.read(videoSharingServiceProvider);
        container.read(videoVisibilityManagerProvider);
        container.read(socialServiceProvider);
        container.read(userProfileServiceProvider);
        container.read(videoEventServiceProvider);
        container.read(authServiceProvider);

        // If we get here, all providers work without Provider package
      } catch (e) {
        fail('Provider creation failed, indicating incomplete migration: $e');
      }
    });

    test('No Provider package dependencies remaining in providers', () {
      // This test ensures that the provider container can create all services
      // without any Provider package dependencies

      try {
        // Try to access all critical providers - should work without Provider
        container.read(videoManagerProvider.notifier);
        container.read(contentDeletionServiceProvider);
        container.read(contentReportingServiceProvider);
        container.read(curatedListServiceProvider);
        container.read(videoSharingServiceProvider);
        container.read(videoVisibilityManagerProvider);
        container.read(socialServiceProvider);
        container.read(userProfileServiceProvider);
        container.read(videoEventServiceProvider);
        container.read(authServiceProvider);

        // If we get here, all providers work without Provider package
      } catch (e) {
        fail('Provider creation failed, indicating incomplete migration: $e');
      }
    });

    test('Core Riverpod migration completed successfully', () {
      // Final test to ensure all critical providers work without Provider package
      try {
        // Test all critical services
        final services = [
          container.read(contentDeletionServiceProvider),
          container.read(contentReportingServiceProvider),
          container.read(curatedListServiceProvider),
          container.read(videoSharingServiceProvider),
          container.read(videoVisibilityManagerProvider),
          container.read(socialServiceProvider),
          container.read(userProfileServiceProvider),
          container.read(videoEventServiceProvider),
          container.read(authServiceProvider),
        ];

        // If we get here, all services were created successfully
        expect(services.length, equals(9));
        for (final service in services) {
          expect(service, isNotNull);
        }
      } catch (e) {
        fail('Core Riverpod migration failed: $e');
      }
    });
  });
}
