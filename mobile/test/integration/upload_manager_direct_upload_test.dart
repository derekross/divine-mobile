// ABOUTME: Integration test for UploadManager with DirectUploadService
// ABOUTME: Verifies the upload flow uses DirectUploadService and falls back to Blossom when enabled

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/services/blossom_upload_service.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/upload_manager.dart';

// Mock classes
class MockDirectUploadService extends Mock implements DirectUploadService {}

class MockBlossomUploadService extends Mock implements BlossomUploadService {}

class MockFile extends Mock implements File {}

class FakeFile extends Fake implements File {}

void main() {
  group('UploadManager with DirectUploadService Integration', () {
    late UploadManager uploadManager;
    late MockDirectUploadService mockDirectUploadService;
    late MockBlossomUploadService mockBlossomService;
    late File testVideoFile;
    late String tempDirPath;

    setUpAll(() async {
      // Register fallback values for mocktail
      registerFallbackValue(FakeFile());
      
      // Initialize Hive for testing
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = await Directory.systemTemp.createTemp('upload_test');
      tempDirPath = tempDir.path;
      Hive.init(tempDirPath);

      // Register adapters
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(PendingUploadAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(UploadStatusAdapter());
      }
    });

    setUp(() async {
      mockDirectUploadService = MockDirectUploadService();
      mockBlossomService = MockBlossomUploadService();
      
      // Create a real temporary file for testing
      testVideoFile = File('$tempDirPath/test_video.mp4');
      await testVideoFile.writeAsBytes([1, 2, 3, 4, 5]); // Mock video data

      // Setup Blossom service defaults
      when(() => mockBlossomService.isBlossomEnabled())
          .thenAnswer((_) async => false);

      uploadManager = UploadManager(
        uploadService: mockDirectUploadService,
        blossomService: mockBlossomService,
      );

      await uploadManager.initialize();
    });

    tearDown(() async {
      uploadManager.dispose();
      // Clean up test file
      if (await testVideoFile.exists()) {
        await testVideoFile.delete();
      }
      // Clean up Hive boxes
      await Hive.deleteFromDisk();
    });

    tearDownAll(() async {
      await Hive.close();
      // Clean up temp directory
      try {
        await Directory(tempDirPath).delete(recursive: true);
      } catch (_) {}
    });

    group('Direct Upload Flow', () {
      test('should use DirectUploadService for normal uploads', () async {
        // Arrange
        when(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => DirectUploadResult.success(
            videoId: 'test-video-id',
            cdnUrl: 'https://cdn.divine.video/test-video-id/manifest/video.m3u8',
            thumbnailUrl: 'https://cdn.divine.video/test-video-id/thumbnails/thumbnail.jpg',
          ),
        );

        // Act
        final upload = await uploadManager.startUpload(
          videoFile: testVideoFile,
          nostrPubkey: 'test-pubkey',
          title: 'Test Video',
          description: 'Test Description',
          hashtags: ['test', 'upload'],
        );

        // Wait for upload to complete (with a reasonable timeout)
        int attempts = 0;
        while (attempts < 50) { // 5 seconds max
          await Future.delayed(Duration(milliseconds: 100));
          final currentUpload = uploadManager.getUpload(upload.id);
          if (currentUpload?.status == UploadStatus.readyToPublish ||
              currentUpload?.status == UploadStatus.failed) {
            break;
          }
          attempts++;
        }

        // Assert
        expect(upload.localVideoPath, testVideoFile.path);
        expect(upload.nostrPubkey, 'test-pubkey');
        expect(upload.title, 'Test Video');
        expect(upload.status, UploadStatus.pending);

        // Verify DirectUploadService was called
        verify(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: 'test-pubkey',
            title: 'Test Video',
            description: 'Test Description',
            hashtags: ['test', 'upload'],
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);

        // Verify Blossom service was checked but not used
        verify(() => mockBlossomService.isBlossomEnabled()).called(1);
        verifyNever(
          () => mockBlossomService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        );
      });

      test('should store CDN URL and video ID from DirectUploadResult', () async {
        // Arrange
        const testVideoId = 'test-video-123';
        const testCdnUrl = 'https://cdn.divine.video/test-video-123/manifest/video.m3u8';
        const testThumbnailUrl = 'https://cdn.divine.video/test-video-123/thumbnails/thumbnail.jpg';

        when(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => DirectUploadResult.success(
            videoId: testVideoId,
            cdnUrl: testCdnUrl,
            thumbnailUrl: testThumbnailUrl,
          ),
        );

        // Act
        final upload = await uploadManager.startUpload(
          videoFile: testVideoFile,
          nostrPubkey: 'test-pubkey',
        );

        // Wait for upload to complete
        int attempts = 0;
        PendingUpload? updatedUpload;
        while (attempts < 50) { // 5 seconds max
          await Future.delayed(Duration(milliseconds: 100));
          updatedUpload = uploadManager.getUpload(upload.id);
          if (updatedUpload?.status == UploadStatus.readyToPublish ||
              updatedUpload?.status == UploadStatus.failed) {
            break;
          }
          attempts++;
        }

        // Assert
        expect(updatedUpload?.videoId, testVideoId);
        expect(updatedUpload?.cdnUrl, testCdnUrl);
        expect(updatedUpload?.thumbnailPath, testThumbnailUrl);
        expect(updatedUpload?.status, UploadStatus.readyToPublish);
      });
    });

    group('Blossom Fallback', () {
      test('should use BlossomUploadService when Blossom is enabled', () async {
        // Arrange
        when(() => mockBlossomService.isBlossomEnabled())
            .thenAnswer((_) async => true);
        when(() => mockBlossomService.getBlossomServer())
            .thenAnswer((_) async => 'https://blossom.example.com');

        when(
          () => mockBlossomService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => DirectUploadResult.success(
            videoId: 'blossom-video-id',
            cdnUrl: 'https://blossom.example.com/video.mp4',
            thumbnailUrl: 'https://blossom.example.com/thumbnail.jpg',
          ),
        );

        // Act
        final upload = await uploadManager.startUpload(
          videoFile: testVideoFile,
          nostrPubkey: 'test-pubkey',
          title: 'Blossom Test Video',
        );

        // Wait for upload to complete
        int attempts = 0;
        while (attempts < 50) { // 5 seconds max
          await Future.delayed(Duration(milliseconds: 100));
          final currentUpload = uploadManager.getUpload(upload.id);
          if (currentUpload?.status == UploadStatus.readyToPublish ||
              currentUpload?.status == UploadStatus.failed) {
            break;
          }
          attempts++;
        }

        // Assert
        verify(() => mockBlossomService.isBlossomEnabled()).called(1);
        verify(() => mockBlossomService.getBlossomServer()).called(1);

        // Verify Blossom service was used
        verify(
          () => mockBlossomService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: 'test-pubkey',
            title: 'Blossom Test Video',
            description: null,
            hashtags: null,
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);

        // Verify DirectUploadService was not used for the actual upload
        verifyNever(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        );
      });

      test('should fall back to DirectUploadService when Blossom server is not configured', () async {
        // Arrange
        when(() => mockBlossomService.isBlossomEnabled())
            .thenAnswer((_) async => true);
        when(() => mockBlossomService.getBlossomServer())
            .thenAnswer((_) async => null); // No server configured

        when(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => DirectUploadResult.success(
            videoId: 'direct-video-id',
            cdnUrl: 'https://cdn.divine.video/direct-video-id/manifest/video.m3u8',
          ),
        );

        // Act
        await uploadManager.startUpload(
          videoFile: testVideoFile,
          nostrPubkey: 'test-pubkey',
          title: 'Fallback Test Video',
        );

        // Wait for upload to complete
        await Future.delayed(Duration(milliseconds: 500));

        // Assert
        verify(() => mockBlossomService.isBlossomEnabled()).called(1);
        verify(() => mockBlossomService.getBlossomServer()).called(1);

        // Verify DirectUploadService was used as fallback
        verify(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: 'test-pubkey',
            title: 'Fallback Test Video',
            description: null,
            hashtags: null,
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);
      });
    });

    group('Error Handling', () {
      test('should handle DirectUploadService failure', () async {
        // Arrange
        when(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => DirectUploadResult.failure('Network error'),
        );

        // Act
        final upload = await uploadManager.startUpload(
          videoFile: testVideoFile,
          nostrPubkey: 'test-pubkey',
        );

        // Wait for upload to fail (with retry attempts)
        // The upload manager does automatic retries with exponential backoff:
        // Attempt 1: 2s, Attempt 2: 4s, Attempt 3: 8s, Attempt 4: 16s, Attempt 5: 32s
        // Total time: ~62 seconds plus processing time
        int attempts = 0;
        PendingUpload? updatedUpload;
        while (attempts < 700) { // 70 seconds max (to allow for all retries)
          await Future.delayed(Duration(milliseconds: 100));
          updatedUpload = uploadManager.getUpload(upload.id);
          if (updatedUpload?.status == UploadStatus.failed) {
            break;
          }
          attempts++;
        }

        // Assert
        expect(updatedUpload?.status, UploadStatus.failed);
        // The error message could be either "Upload failed" or "Circuit breaker" message
        expect(updatedUpload?.errorMessage, anyOf(
          contains('Upload failed'),
          contains('Circuit breaker'),
          contains('service unavailable'),
        ));
      });

      test('should retry failed uploads', () async {
        // Arrange
        var callCount = 0;
        when(
          () => mockDirectUploadService.uploadVideo(
            videoFile: any(named: 'videoFile'),
            nostrPubkey: any(named: 'nostrPubkey'),
            title: any(named: 'title'),
            description: any(named: 'description'),
            hashtags: any(named: 'hashtags'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            // First call fails
            return DirectUploadResult.failure('Temporary network error');
          } else {
            // Second call succeeds
            return DirectUploadResult.success(
              videoId: 'retry-success-id',
              cdnUrl: 'https://cdn.divine.video/retry-success-id/manifest/video.m3u8',
            );
          }
        });

        // Act
        final upload = await uploadManager.startUpload(
          videoFile: testVideoFile,
          nostrPubkey: 'test-pubkey',
        );

        // Wait for first attempt to fail
        int attempts = 0;
        while (attempts < 50) { // 5 seconds max
          await Future.delayed(Duration(milliseconds: 100));
          final currentUpload = uploadManager.getUpload(upload.id);
          if (currentUpload?.status == UploadStatus.failed) {
            break;
          }
          attempts++;
        }

        // Retry the upload
        await uploadManager.retryUpload(upload.id);

        // Wait for retry to complete
        attempts = 0;
        PendingUpload? updatedUpload;
        while (attempts < 50) { // 5 seconds max
          await Future.delayed(Duration(milliseconds: 100));
          updatedUpload = uploadManager.getUpload(upload.id);
          if (updatedUpload?.status == UploadStatus.readyToPublish ||
              updatedUpload?.status == UploadStatus.failed) {
            break;
          }
          attempts++;
        }

        // Assert
        expect(updatedUpload?.status, UploadStatus.readyToPublish);
        expect(updatedUpload?.videoId, 'retry-success-id');
        expect(callCount, greaterThanOrEqualTo(2)); // At least 2 calls (initial + retry)
      });
    });
  });
}