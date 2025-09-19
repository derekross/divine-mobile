// ABOUTME: Simple test to verify all service providers are available through Riverpod
// ABOUTME: Focuses on provider availability without triggering complex dependencies

import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';

void main() {
  group('Service Provider Availability', () {
    test('All required service providers should be accessible', () {
      // Test that the provider functions exist (compile-time check)
      expect(videoManagerProvider, isNotNull);
      expect(contentDeletionServiceProvider, isNotNull);
      expect(contentReportingServiceProvider, isNotNull);
      expect(curatedListServiceProvider, isNotNull);
      expect(videoSharingServiceProvider, isNotNull);
      expect(videoVisibilityManagerProvider, isNotNull);
    });

    test('Provider functions should have expected signatures', () {
      // Verify provider types at compile time
      expect(videoManagerProvider.runtimeType.toString(), contains('Provider'));
      expect(contentDeletionServiceProvider.runtimeType.toString(),
          contains('Provider'));
      expect(contentReportingServiceProvider.runtimeType.toString(),
          contains('Provider'));
      expect(curatedListServiceProvider.runtimeType.toString(),
          contains('Provider'));
      expect(videoSharingServiceProvider.runtimeType.toString(),
          contains('Provider'));
      expect(videoVisibilityManagerProvider.runtimeType.toString(),
          contains('Provider'));
    });
  });
}
