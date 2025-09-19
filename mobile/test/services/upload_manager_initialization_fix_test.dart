// ABOUTME: Test to verify UploadManager initialization fix for null _uploadsBox issue
// ABOUTME: Ensures auto-initialization works when startUpload is called before initialize

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/upload_manager.dart';
import 'package:path/path.dart' as path;

import 'upload_manager_initialization_fix_test.mocks.dart';

@GenerateMocks([DirectUploadService])
void main() {
  late UploadManager uploadManager;
  late MockDirectUploadService mockUploadService;
  late Directory tempDir;

  setUpAll(() async {
    // Initialize Hive for testing
    tempDir = await Directory.systemTemp.createTemp('upload_test');
    Hive.init(tempDir.path);

    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(UploadStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PendingUploadAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() {
    mockUploadService = MockDirectUploadService();
    uploadManager = UploadManager(uploadService: mockUploadService);
  });

  tearDown(() async {
    uploadManager.dispose();
    // Clean up any open boxes
    await Hive.deleteBoxFromDisk('pending_uploads');
  });

  group('UploadManager Initialization Fix', () {
    test(
        'should auto-initialize when startUpload is called without prior initialization',
        () async {
      // Arrange
      final tempVideoFile = File(path.join(tempDir.path, 'test_video.mov'));
      await tempVideoFile.writeAsBytes([1, 2, 3, 4, 5]); // Create dummy file

      // Verify manager is not initialized
      expect(uploadManager.isInitialized, false);

      // Act - call startUpload without calling initialize first
      final upload = await uploadManager.startUpload(
        videoFile: tempVideoFile,
        nostrPubkey: 'test_pubkey_12345678',
        title: 'Test Video',
        hashtags: ['test'],
      );

      // Assert
      expect(upload, isNotNull);
      expect(upload.id, isNotEmpty);
      expect(upload.localVideoPath, tempVideoFile.path);
      expect(upload.nostrPubkey, 'test_pubkey_12345678');
      expect(upload.title, 'Test Video');
      expect(upload.hashtags, ['test']);
      expect(upload.status, UploadStatus.pending);

      // Verify manager is now initialized
      expect(uploadManager.isInitialized, true);

      // Verify upload was saved
      final retrievedUpload = uploadManager.getUpload(upload.id);
      expect(retrievedUpload, isNotNull);
      expect(retrievedUpload?.id, upload.id);
    });

    test('should handle multiple uploads after auto-initialization', () async {
      // Arrange
      final tempVideoFile1 = File(path.join(tempDir.path, 'video1.mov'));
      final tempVideoFile2 = File(path.join(tempDir.path, 'video2.mov'));
      await tempVideoFile1.writeAsBytes([1, 2, 3]);
      await tempVideoFile2.writeAsBytes([4, 5, 6]);

      // Act - upload first video without initialization
      final upload1 = await uploadManager.startUpload(
        videoFile: tempVideoFile1,
        nostrPubkey: 'pubkey1',
        title: 'Video 1',
      );

      // Upload second video (should use already initialized manager)
      final upload2 = await uploadManager.startUpload(
        videoFile: tempVideoFile2,
        nostrPubkey: 'pubkey2',
        title: 'Video 2',
      );

      // Assert
      expect(upload1, isNotNull);
      expect(upload2, isNotNull);
      expect(upload1.id, isNot(equals(upload2.id)));

      // Verify both uploads are saved
      expect(uploadManager.pendingUploads.length, 2);
      expect(uploadManager.getUpload(upload1.id), isNotNull);
      expect(uploadManager.getUpload(upload2.id), isNotNull);
    });

    test('should work normally when initialize is called first', () async {
      // Arrange
      final tempVideoFile = File(path.join(tempDir.path, 'test_video.mov'));
      await tempVideoFile.writeAsBytes([1, 2, 3, 4, 5]);

      // Initialize first (traditional flow)
      await uploadManager.initialize();
      expect(uploadManager.isInitialized, true);

      // Act
      final upload = await uploadManager.startUpload(
        videoFile: tempVideoFile,
        nostrPubkey: 'test_pubkey',
        title: 'Test Video',
      );

      // Assert
      expect(upload, isNotNull);
      expect(uploadManager.getUpload(upload.id), isNotNull);
    });

    test('should handle initialization errors gracefully', () async {
      // Arrange
      final tempVideoFile = File(path.join(tempDir.path, 'test_video.mov'));
      await tempVideoFile.writeAsBytes([1, 2, 3]);

      // Close Hive to simulate initialization failure
      await Hive.close();

      // Act & Assert
      expect(
        () async => await uploadManager.startUpload(
          videoFile: tempVideoFile,
          nostrPubkey: 'test_pubkey',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('UploadManager initialization failed'),
        )),
      );

      // Re-initialize Hive for cleanup
      Hive.init(tempDir.path);
    });

    test('should not re-initialize if already initialized', () async {
      // Arrange
      final tempVideoFile = File(path.join(tempDir.path, 'test_video.mov'));
      await tempVideoFile.writeAsBytes([1, 2, 3]);

      // Initialize once
      await uploadManager.initialize();
      final firstInitState = uploadManager.isInitialized;

      // Act - call startUpload which should skip re-initialization
      await uploadManager.startUpload(
        videoFile: tempVideoFile,
        nostrPubkey: 'test_pubkey',
        title: 'Test Video',
      );

      // Initialize again explicitly
      await uploadManager.initialize();

      // Assert - should still be initialized and work properly
      expect(firstInitState, true);
      expect(uploadManager.isInitialized, true);
      expect(uploadManager.pendingUploads.length, 1);
    });
  });
}
