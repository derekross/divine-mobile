// ABOUTME: Test for service integration reliability using proper async patterns
// ABOUTME: Validates that services can be created and disposed without timing issues

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../helpers/service_integration_test_helper.dart';

class FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(FakeFile());
  });

  group('Service Integration Reliability', () {
    tearDown(() async {
      await ServiceIntegrationTestHelper.cleanupServices();
    });

    test('NostrService can be created and initialized reliably', () async {
      final service = await ServiceIntegrationTestHelper.createNostrService();

      // Wait for initialization using proper async coordination
      await ServiceIntegrationTestHelper.waitForCompletion(
        () => service.isInitialized,
        timeout:
            const Duration(seconds: 15), // Give more time for embedded relay
      );

      expect(service.isInitialized, isTrue);
      expect(service.connectedRelays.isNotEmpty, isTrue);
    });

    test('UploadManager can be created and initialized reliably', () async {
      final manager = await ServiceIntegrationTestHelper.createUploadManager();

      // Manager should be initialized after creation
      expect(manager.pendingUploads, isEmpty);

      // Should handle mock operations without errors
      expect(
          () => manager.getUploadByFilePath('/test/path.mp4'), returnsNormally);
    });

    test('VideoEventService can be created and used reliably', () async {
      final service =
          await ServiceIntegrationTestHelper.createVideoEventService();

      // Service should be in a clean state
      expect(service.isLoading, isFalse);
      expect(service.error, isNull);

      // hasEvents is a function that takes SubscriptionType
      expect(() => service.hasEvents, returnsNormally);
    });

    test('Multiple services can coexist without conflicts', () async {
      final nostrService =
          await ServiceIntegrationTestHelper.createNostrService();
      final uploadManager =
          await ServiceIntegrationTestHelper.createUploadManager();
      final videoService =
          await ServiceIntegrationTestHelper.createVideoEventService();

      // Wait for Nostr service to be ready
      await ServiceIntegrationTestHelper.waitForCompletion(
        () => nostrService.isInitialized,
        timeout: const Duration(seconds: 10),
      );

      // All services should be operational
      expect(nostrService.isInitialized, isTrue);
      expect(uploadManager.pendingUploads, isEmpty);
      expect(videoService.error, isNull);
    });

    test('Service cleanup happens without errors', () async {
      final service1 = await ServiceIntegrationTestHelper.createNostrService();
      final service2 = await ServiceIntegrationTestHelper.createUploadManager();

      // Services should be created
      expect(service1, isNotNull);
      expect(service2, isNotNull);

      // Cleanup should complete without throwing
      await expectLater(
        ServiceIntegrationTestHelper.cleanupServices(),
        completes,
      );
    });
  });
}
