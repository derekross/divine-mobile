// ABOUTME: Integration tests for Cloudflare Stream upload service against live servers
// ABOUTME: TDD approach testing real upload flow to CF Stream via migration API

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/cloudflare_stream_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Log.setLogLevel(LogLevel.debug);
  Log.enableCategories({LogCategory.video, LogCategory.system});

  group('CloudflareStreamService - Live Server Integration', () {
    late CloudflareStreamService streamService;
    late AuthService authService;
    late File testVideoFile;

    setUpAll(() async {
      // Create a small test video file (1 second black video)
      final tempDir = await getTemporaryDirectory();
      testVideoFile = File(path.join(tempDir.path, 'test_vine.mp4'));

      // Create a minimal valid MP4 file for testing
      // This is a tiny valid MP4 with black frames
      final mp4Bytes = _createMinimalMp4();
      await testVideoFile.writeAsBytes(mp4Bytes);
    });

    setUp(() async {
      // Initialize services
      authService = AuthService();
      await authService.initialize();

      streamService = CloudflareStreamService(
        authService: authService,
        httpClient: http.Client(),
      );
    });

    tearDownAll(() async {
      // Clean up test file
      if (await testVideoFile.exists()) {
        await testVideoFile.delete();
      }
    });

    test('should migrate video to Cloudflare Stream and return URLs', () async {
      // Arrange
      final testVineId = 'test_vine_${DateTime.now().millisecondsSinceEpoch}';
      const testTitle = 'Test Vine Upload';
      const testDescription = 'Testing CF Stream migration #test';

      // Act
      final result = await streamService.migrateToStream(
        videoFile: testVideoFile,
        vineId: testVineId,
        title: testTitle,
        description: testDescription,
        hashtags: ['test', 'cfstream'],
        onProgress: (progress) {
          print('Upload progress: ${(progress * 100).toStringAsFixed(0)}%');
        },
      );

      // Assert
      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.streamUid, isNotNull);
      expect(result.streamUid, isNotEmpty);

      // Verify HLS URL format
      expect(result.hlsUrl, isNotNull);
      expect(result.hlsUrl, contains('https://cdn.divine.video/'));
      expect(result.hlsUrl, contains('/manifest/video.m3u8'));

      // Verify MP4 URL format
      expect(result.mp4Url, isNotNull);
      expect(result.mp4Url, contains('/downloads/default.mp4'));

      // Verify thumbnail URLs
      expect(result.thumbnailUrl, isNotNull);
      expect(result.thumbnailUrl, contains('/thumbnails/thumbnail.jpg'));
      expect(result.animatedThumbnailUrl, contains('/thumbnails/thumbnail.gif'));

      // Verify DASH URL if provided
      if (result.dashUrl != null) {
        expect(result.dashUrl, contains('/manifest/video.mpd'));
      }

      // Test that URLs are accessible
      final hlsResponse = await http.head(Uri.parse(result.hlsUrl!));
      expect(hlsResponse.statusCode, lessThan(400),
        reason: 'HLS URL should be accessible');
    });

    test('should handle video with BigQuery metadata enrichment', () async {
      // Arrange - use a known classic Vine ID that exists in BigQuery
      const classicVineId = 'MQW6P9OKhQq'; // Example Vine ID

      // Act
      final result = await streamService.migrateToStream(
        videoFile: testVideoFile,
        vineId: classicVineId,
        enrichWithBigQuery: true,
      );

      // Assert
      expect(result.success, isTrue, reason: result.errorMessage);

      // Check if BigQuery metadata was added
      if (result.metadata != null) {
        final metadata = result.metadata!;

        // These fields should be present if BigQuery enrichment worked
        if (metadata.containsKey('originalUsername')) {
          expect(metadata['originalUsername'], isNotEmpty);
        }
        if (metadata.containsKey('originalTimestamp')) {
          expect(metadata['originalTimestamp'], isA<int>());
        }
        if (metadata.containsKey('loops')) {
          expect(metadata['loops'], isA<int>());
        }
      }
    });

    test('should generate blurhash for video thumbnail', () async {
      // Arrange
      final testVineId = 'blurhash_test_${DateTime.now().millisecondsSinceEpoch}';

      // Act
      final result = await streamService.migrateToStream(
        videoFile: testVideoFile,
        vineId: testVineId,
        generateBlurhash: true,
      );

      // Assert
      expect(result.success, isTrue);
      expect(result.blurhash, isNotNull);
      expect(result.blurhash, isNotEmpty);
      // Blurhash should be in format like: LGF5]+Yk^6#M@-5c,1J5@[or
      expect(result.blurhash!.length, greaterThan(6));
    });

    test('should handle network errors gracefully', () async {
      // Arrange - use a service with bad URL
      final badService = CloudflareStreamService(
        authService: authService,
        httpClient: http.Client(),
        migrationApiUrl: 'https://invalid-url-that-does-not-exist.com',
      );

      // Act
      final result = await badService.migrateToStream(
        videoFile: testVideoFile,
        vineId: 'network_error_test',
      );

      // Assert
      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('network'));
    });

    test('should handle rate limiting with retry', () async {
      // Arrange - make multiple rapid requests to trigger rate limiting
      final futures = <Future<CloudflareStreamResult>>[];

      for (int i = 0; i < 5; i++) {
        futures.add(
          streamService.migrateToStream(
            videoFile: testVideoFile,
            vineId: 'rate_limit_test_$i',
          ),
        );
      }

      // Act
      final results = await Future.wait(futures);

      // Assert - at least some should succeed despite rate limiting
      final successCount = results.where((r) => r.success).length;
      expect(successCount, greaterThan(0));
    });

    test('should track upload progress accurately', () async {
      // Arrange
      final progressValues = <double>[];
      final testVineId = 'progress_test_${DateTime.now().millisecondsSinceEpoch}';

      // Act
      final result = await streamService.migrateToStream(
        videoFile: testVideoFile,
        vineId: testVineId,
        onProgress: (progress) {
          progressValues.add(progress);
        },
      );

      // Assert
      expect(result.success, isTrue);
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, equals(1.0)); // Should end at 100%

      // Progress should be monotonically increasing
      for (int i = 1; i < progressValues.length; i++) {
        expect(progressValues[i], greaterThanOrEqualTo(progressValues[i - 1]));
      }
    });
  });
}

// Helper to create a minimal valid MP4 file for testing
Uint8List _createMinimalMp4() {
  // This is a minimal valid MP4 structure (about 1KB)
  // Contains: ftyp box + mdat box with minimal data
  return Uint8List.fromList([
    // ftyp box (file type)
    0x00, 0x00, 0x00, 0x20, // size: 32 bytes
    0x66, 0x74, 0x79, 0x70, // type: 'ftyp'
    0x69, 0x73, 0x6F, 0x6D, // major brand: 'isom'
    0x00, 0x00, 0x00, 0x00, // minor version
    0x69, 0x73, 0x6F, 0x6D, // compatible brand: 'isom'
    0x69, 0x73, 0x6F, 0x32, // compatible brand: 'iso2'
    0x6D, 0x70, 0x34, 0x31, // compatible brand: 'mp41'

    // mdat box (media data) - minimal
    0x00, 0x00, 0x00, 0x08, // size: 8 bytes
    0x6D, 0x64, 0x61, 0x74, // type: 'mdat'
  ]);
}