// ABOUTME: Real integration test for UploadManager initialization fix
// ABOUTME: Tests against actual production services to verify upload functionality

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/nip98_auth_service.dart';
import 'package:openvine/services/secure_key_storage_service.dart';
import 'package:openvine/services/upload_manager.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UploadManager uploadManager;
  late DirectUploadService uploadService;
  late Nip98AuthService nip98AuthService;
  late AuthService authService;
  late SecureKeyStorageService keyStorage;
  late Directory tempDir;
  late File testVideoFile;

  setUpAll(() async {
    // Initialize Hive for testing
    tempDir = await Directory.systemTemp.createTemp('upload_real_test');
    Hive.init(tempDir.path);

    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(UploadStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PendingUploadAdapter());
    }

    // Create a small test video file (just a few bytes to minimize upload time)
    testVideoFile = File(path.join(tempDir.path, 'test_video.mov'));
    // Create a minimal valid MOV file header (simplified)
    final movHeader = [
      0x00, 0x00, 0x00, 0x20, // size
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x71, 0x74, 0x20, 0x20, // 'qt  '
      0x00, 0x00, 0x00, 0x00, // minor version
      0x71, 0x74, 0x20, 0x20, // compatible brands
      0x00, 0x00, 0x00, 0x08, // size
      0x77, 0x69, 0x64, 0x65, // 'wide'
    ];
    await testVideoFile.writeAsBytes(movHeader);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    // Set up services with test key
    keyStorage = SecureKeyStorageService();
    authService = AuthService(keyStorage: keyStorage);

    // Mock the platform channel for secure storage
    const MethodChannel channel =
        MethodChannel('plugins.flutter.io/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return null; // No stored key
        } else if (methodCall.method == 'write') {
          return null; // Pretend write succeeded
        }
        return null;
      },
    );

    await authService.initialize();

    // Create a test account if not authenticated
    if (!authService.isAuthenticated) {
      // Generate a random test key for this test run
      await authService.createNewIdentity();
    }

    nip98AuthService = Nip98AuthService(authService: authService);
    uploadService = DirectUploadService(authService: nip98AuthService);
    uploadManager = UploadManager(uploadService: uploadService);
  });

  tearDown(() async {
    uploadManager.dispose();
    // Clean up any open boxes
    await Hive.deleteBoxFromDisk('pending_uploads');
  });

  group('UploadManager Real Integration Test', () {
    test(
        'should auto-initialize and create upload record without prior initialization',
        () async {
      // Skip if no auth (CI environment)
      if (!authService.isAuthenticated) {
        print('Skipping test - no authentication available');
        return;
      }

      // Arrange
      expect(uploadManager.isInitialized, false,
          reason: 'Manager should not be initialized at start');

      // Act - call startUpload without calling initialize first
      final upload = await uploadManager.startUpload(
        videoFile: testVideoFile,
        nostrPubkey: authService.currentPublicKeyHex!,
        title: 'Integration Test Video',
        description: 'Testing auto-initialization fix',
        hashtags: ['test', 'openvine'],
      );

      // Assert
      expect(upload, isNotNull, reason: 'Upload should be created');
      expect(upload.id, isNotEmpty, reason: 'Upload should have an ID');
      expect(upload.localVideoPath, testVideoFile.path,
          reason: 'Upload should reference the correct file');
      expect(upload.nostrPubkey, authService.currentPublicKeyHex,
          reason: 'Upload should have the correct pubkey');
      expect(upload.title, 'Integration Test Video');
      expect(upload.hashtags, containsAll(['test', 'openvine']));
      expect(upload.status, equals(UploadStatus.pending),
          reason: 'Upload should start in pending status');

      // Verify manager is now initialized
      expect(uploadManager.isInitialized, true,
          reason: 'Manager should be auto-initialized after startUpload');

      // Verify upload was persisted
      final retrievedUpload = uploadManager.getUpload(upload.id);
      expect(retrievedUpload, isNotNull,
          reason: 'Upload should be retrievable from storage');
      expect(retrievedUpload?.id, upload.id);
      expect(retrievedUpload?.title, upload.title);

      // Verify we can get uploads by status
      final pendingUploads =
          uploadManager.getUploadsByStatus(UploadStatus.pending);
      expect(pendingUploads, isNotEmpty,
          reason: 'Should have at least one pending upload');
      expect(pendingUploads.any((u) => u.id == upload.id), true,
          reason: 'Our upload should be in the pending list');

      // Clean up - cancel the upload to prevent actual upload
      await uploadManager.cancelUpload(upload.id);
    });

    test('should handle multiple consecutive uploads after auto-initialization',
        () async {
      // Skip if no auth (CI environment)
      if (!authService.isAuthenticated) {
        print('Skipping test - no authentication available');
        return;
      }

      // Create multiple test files
      final file1 = File(path.join(tempDir.path, 'video1.mov'));
      final file2 = File(path.join(tempDir.path, 'video2.mov'));
      await file1.writeAsBytes([1, 2, 3, 4, 5]);
      await file2.writeAsBytes([6, 7, 8, 9, 10]);

      // Act - upload first video without initialization
      final upload1 = await uploadManager.startUpload(
        videoFile: file1,
        nostrPubkey: authService.currentPublicKeyHex!,
        title: 'First Video',
      );

      // Upload second video (should use already initialized manager)
      final upload2 = await uploadManager.startUpload(
        videoFile: file2,
        nostrPubkey: authService.currentPublicKeyHex!,
        title: 'Second Video',
      );

      // Assert
      expect(upload1, isNotNull);
      expect(upload2, isNotNull);
      expect(upload1.id, isNot(equals(upload2.id)),
          reason: 'Each upload should have a unique ID');

      // Verify both uploads are saved
      expect(uploadManager.pendingUploads.length, greaterThanOrEqualTo(2),
          reason: 'Should have at least 2 uploads');
      expect(uploadManager.getUpload(upload1.id), isNotNull);
      expect(uploadManager.getUpload(upload2.id), isNotNull);
      expect(uploadManager.getUpload(upload1.id)?.title, 'First Video');
      expect(uploadManager.getUpload(upload2.id)?.title, 'Second Video');

      // Clean up
      await uploadManager.cancelUpload(upload1.id);
      await uploadManager.cancelUpload(upload2.id);
    });

    test('should persist uploads across manager recreation', () async {
      // Skip if no auth (CI environment)
      if (!authService.isAuthenticated) {
        print('Skipping test - no authentication available');
        return;
      }

      // Create and save an upload
      final upload = await uploadManager.startUpload(
        videoFile: testVideoFile,
        nostrPubkey: authService.currentPublicKeyHex!,
        title: 'Persistent Test Video',
      );

      final uploadId = upload.id;
      expect(uploadManager.getUpload(uploadId), isNotNull);

      // Dispose the manager
      uploadManager.dispose();

      // Create a new manager instance
      final newManager = UploadManager(uploadService: uploadService);

      // Initialize it
      await newManager.initialize();

      // Verify the upload persisted
      final retrievedUpload = newManager.getUpload(uploadId);
      expect(retrievedUpload, isNotNull,
          reason: 'Upload should persist across manager instances');
      expect(retrievedUpload?.title, 'Persistent Test Video');
      expect(retrievedUpload?.nostrPubkey, authService.currentPublicKeyHex);

      // Clean up
      await newManager.deleteUpload(uploadId);
      newManager.dispose();
    });
  });
}
