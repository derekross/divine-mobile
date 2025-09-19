// ABOUTME: Helper for reliable service integration tests with proper dependency injection
// ABOUTME: Provides preconfigured service instances with consistent async patterns

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/nostr_service.dart';
import 'package:openvine/services/upload_manager.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/subscription_manager.dart';

/// Service Integration Test Helper
///
/// Provides consistently configured service instances for integration tests
/// with proper async coordination and reliable cleanup patterns.
class ServiceIntegrationTestHelper {
  static bool _isInitialized = false;
  static final List<dynamic> _createdServices = [];

  /// Initialize test environment once for all service integration tests
  static Future<void> initializeTestEnvironment() async {
    if (_isInitialized) return;

    TestWidgetsFlutterBinding.ensureInitialized();

    // Setup platform channel mocks
    _setupPlatformChannelMocks();

    // Initialize Hive once
    await Hive.initFlutter();

    _isInitialized = true;
  }

  /// Create a properly configured NostrService for testing
  static Future<NostrService> createNostrService() async {
    await initializeTestEnvironment();

    final keyManager = NostrKeyManager();
    await keyManager.initialize();

    if (!keyManager.hasKeys) {
      await keyManager.generateKeys();
    }

    final service = NostrService(keyManager);
    _createdServices.add(service);

    return service;
  }

  /// Create a properly configured UploadManager for testing
  static Future<UploadManager> createUploadManager({
    DirectUploadService? uploadService,
  }) async {
    await initializeTestEnvironment();

    final service = uploadService ?? _createMockDirectUploadService();
    final manager = UploadManager(uploadService: service);

    await manager.initialize();
    _createdServices.add(manager);

    return manager;
  }

  /// Create a VideoEventService with subscription manager
  static Future<VideoEventService> createVideoEventService() async {
    await initializeTestEnvironment();

    final nostrService = await createNostrService();
    final subscriptionManager = SubscriptionManager(nostrService);

    final service = VideoEventService(
      nostrService,
      subscriptionManager: subscriptionManager,
    );

    _createdServices.add(service);
    return service;
  }

  /// Clean up all created services
  static Future<void> cleanupServices() async {
    // Dispose all services in reverse order
    for (final service in _createdServices.reversed) {
      try {
        if (service is NostrService) {
          service.dispose();
        } else if (service is UploadManager) {
          service.dispose();
        } else if (service is VideoEventService) {
          service.dispose();
        }
      } catch (e) {
        // Ignore disposal errors
      }
    }

    _createdServices.clear();

    // Clean up Hive boxes
    await _cleanupHiveBoxes();
  }

  /// Wait for service operation to complete using proper async patterns
  static Future<void> waitForCompletion(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
    Duration checkInterval = const Duration(milliseconds: 100),
  }) async {
    final completer = Completer<void>();
    final stopwatch = Stopwatch()..start();

    Timer.periodic(checkInterval, (timer) {
      if (condition()) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      } else if (stopwatch.elapsed > timeout) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException(
            'Condition not met within timeout',
            timeout,
          ));
        }
      }
    });

    return completer.future;
  }

  // Private helper methods

  static void _setupPlatformChannelMocks() {
    // Mock SharedPreferences
    const MethodChannel prefsChannel =
        MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      prefsChannel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'getAll':
            return <String, dynamic>{};
          case 'setString':
          case 'setStringList':
          case 'setBool':
          case 'setInt':
          case 'setDouble':
          case 'remove':
          case 'clear':
            return true;
          default:
            return null;
        }
      },
    );

    // Mock connectivity
    const MethodChannel connectivityChannel =
        MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      connectivityChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return ['wifi'];
        }
        return null;
      },
    );

    // Mock secure storage
    const MethodChannel secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'write':
          case 'delete':
            return null;
          case 'read':
            return null;
          case 'readAll':
            return <String, String>{};
          case 'deleteAll':
            return null;
          default:
            return null;
        }
      },
    );

    // Mock path_provider
    const MethodChannel pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'getApplicationDocumentsDirectory':
            return '/tmp/test_documents';
          case 'getTemporaryDirectory':
            return '/tmp';
          case 'getApplicationSupportDirectory':
            return '/tmp/test_support';
          default:
            return null;
        }
      },
    );
  }

  static DirectUploadService _createMockDirectUploadService() {
    final mock = MockDirectUploadService();

    // Setup basic mock behavior
    when(() => mock.uploadVideo(
          videoFile: any(named: 'videoFile'),
          nostrPubkey: any(named: 'nostrPubkey'),
          title: any(named: 'title'),
          description: any(named: 'description'),
          hashtags: any(named: 'hashtags'),
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => DirectUploadResult(
          success: true,
          videoId: 'test-video-id',
          cdnUrl: 'https://test.com/video.mp4',
          thumbnailUrl: 'https://test.com/thumb.jpg',
        ));

    when(() => mock.activeUploads).thenReturn([]);
    when(() => mock.isUploading(any())).thenReturn(false);
    when(() => mock.getProgressStream(any())).thenReturn(null);
    when(() => mock.cancelUpload(any())).thenAnswer((_) async {});
    when(() => mock.dispose()).thenReturn(null);

    return mock;
  }

  static Future<void> _cleanupHiveBoxes() async {
    // Clean up common Hive boxes used in tests
    final boxNames = ['pending_uploads', 'video_cache', 'user_profiles'];

    for (final boxName in boxNames) {
      try {
        if (Hive.isBoxOpen(boxName)) {
          final box = Hive.box(boxName);
          await box.clear();
          await box.close();
        }
        await Hive.deleteBoxFromDisk(boxName);
      } catch (e) {
        // Box might not exist or already be deleted
      }
    }
  }
}

/// Mock DirectUploadService for testing
class MockDirectUploadService extends Mock implements DirectUploadService {}
