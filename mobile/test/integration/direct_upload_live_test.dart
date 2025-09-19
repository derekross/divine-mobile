// ABOUTME: Live integration test for DirectUploadService with real backend
// ABOUTME: Tests actual video upload functionality against production API

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/services/direct_upload_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('DirectUploadService Live Integration', () {
    late DirectUploadService uploadService;
    late File testVideoFile;

    setUpAll(() async {
      // Create service without auth for testing
      uploadService = DirectUploadService();

      // Create a small test video file in system temp
      final tempPath = Directory.systemTemp.path;
      testVideoFile = File(
          '$tempPath/test_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // Create a minimal MP4 file (simplified header for testing)
      // This is a very basic MP4 structure that should be accepted
      final mp4Data = Uint8List.fromList([
        // ftyp box
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
        0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
        0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
        0x61, 0x76, 0x63, 0x31, 0x6D, 0x70, 0x34, 0x31,
        // mdat box with minimal data
        0x00, 0x00, 0x00, 0x10, 0x6D, 0x64, 0x61, 0x74,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]);

      await testVideoFile.writeAsBytes(mp4Data);
    });

    tearDownAll(() async {
      // Clean up test file
      if (await testVideoFile.exists()) {
        await testVideoFile.delete();
      }
    });

    test('uploads video to real backend without SHA256', () async {
      // Skip if no backend is available
      final backendUrl = 'https://api.openvine.co/health';
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(backendUrl));
        final response = await request.close();
        await response.drain();
        if (response.statusCode != 200) {
          print('Backend not available, skipping test');
          return;
        }
      } catch (e) {
        print('Backend not reachable: $e, skipping test');
        return;
      }

      // Test actual upload
      final result = await uploadService.uploadVideo(
        videoFile: testVideoFile,
        nostrPubkey: 'test_pubkey_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Integration Test Video',
        description: 'Testing iOS upload fix',
        hashtags: ['test', 'ios'],
      );

      // Verify upload succeeded
      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.cdnUrl, isNotNull);
      expect(result.cdnUrl, contains('openvine'));

      print('✅ Upload successful! CDN URL: ${result.cdnUrl}');
    });

    test('handles upload without authentication gracefully', () async {
      // Test that uploads work even without NIP-98 auth
      final result = await uploadService.uploadProfilePicture(
        imageFile: testVideoFile, // Using video file as image for simplicity
        nostrPubkey: 'test_pubkey_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Should either succeed or fail with HTTP error
      if (!result.success) {
        expect(result.errorMessage,
            anyOf(contains('400'), contains('401'), contains('auth')),
            reason: 'Should fail with HTTP error');
      } else {
        expect(result.cdnUrl, isNotNull);
      }
    });
  });
}
