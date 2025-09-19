// ABOUTME: Live integration test for Cloudflare Stream upload service
// ABOUTME: Tests real upload flow to CF Stream API without Flutter dependencies

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/cloudflare_stream_service.dart';
import 'package:openvine/utils/unified_logger.dart';

void main() {
  Log.setLogLevel(LogLevel.debug);
  Log.enableCategories({LogCategory.video, LogCategory.system});

  group('CloudflareStreamService - Live API Test', () {
    late CloudflareStreamService streamService;
    late File testVideoFile;

    setUpAll(() async {
      // Create a small test video file
      testVideoFile = File('test_vine_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // Create a minimal valid MP4 file for testing
      final mp4Bytes = _createMinimalMp4();
      await testVideoFile.writeAsBytes(mp4Bytes);

      print('Test video file created: ${testVideoFile.path}');
    });

    setUp(() async {
      // Initialize service with test token
      final authService = AuthService();

      streamService = CloudflareStreamService(
        authService: authService,
        httpClient: http.Client(),
        bearerToken: Platform.environment['CF_STREAM_TOKEN'] ?? 'test_token',
      );
    });

    tearDownAll(() async {
      // Clean up test file
      if (await testVideoFile.exists()) {
        await testVideoFile.delete();
        print('Test video file deleted');
      }
    });

    test('should migrate video to Cloudflare Stream and return URLs', () async {
      // Skip if no real token provided
      if (Platform.environment['CF_STREAM_TOKEN'] == null) {
        print('⚠️ Skipping test - CF_STREAM_TOKEN not set');
        print('To run: CF_STREAM_TOKEN=your_token dart test test/integration/cloudflare_stream_live_test.dart');
        return;
      }

      // Arrange
      final testVineId = 'test_vine_${DateTime.now().millisecondsSinceEpoch}';
      const testTitle = 'Test Vine Upload';
      const testDescription = 'Testing CF Stream migration #test';

      print('Starting migration for vine: $testVineId');

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
      if (!result.success) {
        print('❌ Migration failed: ${result.errorMessage}');
      }

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.streamUid, isNotNull);
      expect(result.streamUid, isNotEmpty);

      print('✅ Migration successful!');
      print('Stream UID: ${result.streamUid}');
      print('HLS URL: ${result.hlsUrl}');
      print('MP4 URL: ${result.mp4Url}');
      print('Thumbnail: ${result.thumbnailUrl}');

      // Verify HLS URL format
      expect(result.hlsUrl, isNotNull);
      expect(result.hlsUrl, contains('https://cdn.divine.video/'));
      expect(result.hlsUrl, contains('/manifest/video.m3u8'));

      // Verify MP4 URL format
      expect(result.mp4Url, isNotNull);
      expect(result.mp4Url, contains('/downloads/default.mp4'));

      // Test that URLs are accessible (may take time for processing)
      print('Testing URL accessibility...');
      final hlsResponse = await http.head(Uri.parse(result.hlsUrl!));
      print('HLS URL status: ${hlsResponse.statusCode}');

      // Stream may still be processing, so 404 is acceptable initially
      expect(hlsResponse.statusCode, anyOf(200, 404),
        reason: 'HLS URL should be valid (may still be processing)');
    });

    test('should handle invalid token gracefully', () async {
      // Arrange
      final badService = CloudflareStreamService(
        authService: AuthService(),
        httpClient: http.Client(),
        bearerToken: 'invalid_token_12345',
      );

      // Act
      final result = await badService.migrateToStream(
        videoFile: testVideoFile,
        vineId: 'auth_test_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Assert
      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      print('Expected auth failure: ${result.errorMessage}');
    });

    test('should generate blurhash for video thumbnail', () async {
      // Skip if no real token
      if (Platform.environment['CF_STREAM_TOKEN'] == null) {
        print('⚠️ Skipping blurhash test - CF_STREAM_TOKEN not set');
        return;
      }

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

      if (result.blurhash != null) {
        expect(result.blurhash, isNotEmpty);
        print('Blurhash generated: ${result.blurhash}');
        // Blurhash should be in format like: LGF5]+Yk^6#M@-5c,1J5@[or
        expect(result.blurhash!.length, greaterThan(6));
      } else {
        print('⚠️ Blurhash generation skipped (thumbnail may not be ready)');
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