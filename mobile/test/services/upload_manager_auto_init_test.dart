// ABOUTME: Focused test to verify UploadManager auto-initialization fix
// ABOUTME: Tests that _uploadsBox is properly initialized when startUpload is called

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/upload_manager.dart';
import 'package:path/path.dart' as path;

import 'upload_manager_auto_init_test.mocks.dart';

@GenerateMocks([DirectUploadService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UploadManager uploadManager;
  late MockDirectUploadService mockUploadService;
  late Directory tempDir;
  late File testVideoFile;

  setUpAll(() async {
    // Initialize Hive for testing
    tempDir = await Directory.systemTemp.createTemp('upload_auto_init_test');
    Hive.init(tempDir.path);

    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(UploadStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PendingUploadAdapter());
    }

    // Create test video file
    testVideoFile = File(path.join(tempDir.path, 'test.mov'));
    await testVideoFile.writeAsBytes([1, 2, 3, 4, 5]);
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

    // Setup mock to return success (but it won't be called since we'll cancel)
    when(mockUploadService.uploadVideo(
      videoFile: anyNamed('videoFile'),
      nostrPubkey: anyNamed('nostrPubkey'),
      title: anyNamed('title'),
      description: anyNamed('description'),
      hashtags: anyNamed('hashtags'),
      onProgress: anyNamed('onProgress'),
    )).thenAnswer((_) async => DirectUploadResult.success(
          videoId: 'test_video_id',
          cdnUrl: 'https://test.cdn/video.mp4',
        ));
  });

  tearDown(() async {
    uploadManager.dispose();
    // Clean up the box
    await Hive.deleteBoxFromDisk('pending_uploads');
  });

  test('CRITICAL FIX: startUpload auto-initializes when _uploadsBox is null',
      () async {
    // This is the exact issue from the logs:
    // [VIDEO] ❌ UploadManager not initialized - _uploadsBox is null!

    // Verify manager starts uninitialized
    expect(uploadManager.isInitialized, false,
        reason: 'Manager should start uninitialized');

    // Call startUpload WITHOUT calling initialize() first
    // This simulates the exact scenario from the error logs
    final upload = await uploadManager.startUpload(
      videoFile: testVideoFile,
      nostrPubkey: 'test_pubkey_78a5c21b',
      title: 'Test Video',
      hashtags: ['openvine'],
    );

    // CRITICAL ASSERTIONS:

    // 1. Upload should be created successfully (not throw error)
    expect(upload, isNotNull,
        reason: 'Upload should be created despite no prior initialization');

    // 2. Manager should now be initialized
    expect(uploadManager.isInitialized, true,
        reason: 'Manager should auto-initialize when startUpload is called');

    // 3. Upload should be saved to storage
    final savedUpload = uploadManager.getUpload(upload.id);
    expect(savedUpload, isNotNull,
        reason: 'Upload should be saved to Hive storage');
    expect(savedUpload?.id, upload.id);
    expect(savedUpload?.title, 'Test Video');

    // 4. Verify we can retrieve the upload by various methods
    // Note: The upload might be in processing state if background upload started
    final allUploads = uploadManager.pendingUploads;
    expect(allUploads, isNotEmpty,
        reason: 'Should have at least one upload after startUpload');
    expect(allUploads.any((u) => u.id == upload.id), true,
        reason: 'Our upload should be in the list');

    // Clean up - cancel the upload to prevent actual upload attempt
    await uploadManager.cancelUpload(upload.id);
  });

  test('subsequent uploads work after auto-initialization', () async {
    // First upload triggers auto-init
    final upload1 = await uploadManager.startUpload(
      videoFile: testVideoFile,
      nostrPubkey: 'pubkey1',
      title: 'First',
    );

    // Second upload should work without issues
    final upload2 = await uploadManager.startUpload(
      videoFile: testVideoFile,
      nostrPubkey: 'pubkey2',
      title: 'Second',
    );

    expect(upload1.id, isNot(equals(upload2.id)));
    expect(uploadManager.pendingUploads.length, greaterThanOrEqualTo(2));

    // Clean up
    await uploadManager.cancelUpload(upload1.id);
    await uploadManager.cancelUpload(upload2.id);
  });

  test('explicit initialization still works correctly', () async {
    // Traditional flow: initialize first
    await uploadManager.initialize();
    expect(uploadManager.isInitialized, true);

    // Then upload
    final upload = await uploadManager.startUpload(
      videoFile: testVideoFile,
      nostrPubkey: 'test_pubkey',
      title: 'Traditional Flow',
    );

    expect(upload, isNotNull);
    expect(uploadManager.getUpload(upload.id), isNotNull);

    // Clean up
    await uploadManager.cancelUpload(upload.id);
  });
}
