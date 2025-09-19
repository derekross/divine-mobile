// ABOUTME: Test to verify VideoEvent parsing of NIP-32222 compliant kind 32222 events
// ABOUTME: Tests proper imeta tag parsing according to the NIP-32222 specification

import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_sdk/event.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/utils/unified_logger.dart';

void main() {
  group('VideoEvent NIP-32222 Spec Compliance', () {
    test('should parse properly formatted NIP-32222 imeta tags', () {
      Log.debug('🔍 Testing NIP-32222 compliant video event...',
          name: 'VideoEventSpecComplianceTest', category: LogCategory.system);

      // Properly formatted NIP-32222 kind 32222 event with imeta tags
      final event = Event(
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        32222,
        [
          ["d", "test-video-id"], // Required for addressable events
          ["title", "Test Video"],
          ["published_at", "1751355472"],
          ["alt", "A test video for NIP-32222 compliance"],
          [
            "imeta",
            "url https://api.openvine.co/media/test-video.mp4",
            "x 3093509d1e0bc604ff60cb9286f4cd7c781553bc8991937befaacfdc28ec5cdc",
            "m video/mp4",
            "dim 1080x1920",
            "duration 15"
          ],
          ["duration", "15"],
          ["t", "test"],
          ["t", "nip32222"]
        ],
        'A test video demonstrating NIP-32222 compliance',
      );

      // Parse the event
      final videoEvent = VideoEvent.fromNostrEvent(event);

      Log.info(
          '✅ Parsed NIP-32222 event: hasVideo=${videoEvent.hasVideo}, videoUrl=${videoEvent.videoUrl}',
          name: 'VideoEventSpecComplianceTest',
          category: LogCategory.system);
      Log.info(
          '✅ Duration: ${videoEvent.duration}, dimensions: ${videoEvent.dimensions}',
          name: 'VideoEventSpecComplianceTest',
          category: LogCategory.system);

      // Verify parsing results
      expect(videoEvent.hasVideo, true,
          reason: 'NIP-32222 compliant event should have video URL');
      expect(
          videoEvent.videoUrl, 'https://api.openvine.co/media/test-video.mp4');
      expect(videoEvent.mimeType, 'video/mp4');
      expect(videoEvent.title, 'Test Video');
      expect(videoEvent.duration, 15);
      expect(videoEvent.dimensions, '1080x1920');
      expect(videoEvent.hashtags, contains('test'));
      expect(videoEvent.hashtags, contains('nip32222'));
    });

    test('should handle multiple imeta tags for different video qualities', () {
      Log.debug('🔍 Testing multiple video quality variants...',
          name: 'VideoEventSpecComplianceTest', category: LogCategory.system);

      // Event with multiple imeta tags for different qualities
      final event = Event(
        'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
        32222,
        [
          ["d", "multi-quality-video"], // Required for addressable events
          ["title", "Multi-Quality Video"],
          [
            "imeta",
            "url https://api.openvine.co/media/video-1080p.mp4",
            "dim 1920x1080",
            "m video/mp4"
          ],
          [
            "imeta",
            "url https://api.openvine.co/media/video-720p.mp4",
            "dim 1280x720",
            "m video/mp4"
          ],
          [
            "imeta",
            "url https://api.openvine.co/media/video-480p.mp4",
            "dim 854x480",
            "m video/mp4"
          ]
        ],
        'Video with multiple quality variants',
      );

      // Parse the event - should use the first valid URL found
      final videoEvent = VideoEvent.fromNostrEvent(event);

      Log.info(
          '✅ Multi-quality event: hasVideo=${videoEvent.hasVideo}, videoUrl=${videoEvent.videoUrl}',
          name: 'VideoEventSpecComplianceTest',
          category: LogCategory.system);

      // Should have parsed at least one video URL
      expect(videoEvent.hasVideo, true,
          reason: 'Should parse first valid video URL');
      expect(videoEvent.videoUrl, isNotNull);
      expect(videoEvent.videoUrl,
          startsWith('https://api.openvine.co/media/video-'));
    });

    test('should handle migration from Kind 22 to Kind 32222 format', () {
      Log.debug('🔍 Analyzing Kind 22 legacy format vs NIP-32222 spec...',
          name: 'VideoEventSpecComplianceTest', category: LogCategory.system);

      // Legacy Kind 22 format (should be rejected)
      final legacyEvent = Event(
        'd95aa8fc0eff8e488952495b8064991d27fb96ed8652f12cdedc5a4e8b5ae540',
        22,
        [
          ["url", "https://api.openvine.co/media/1751355501029-7553157a"],
          ["m", "video/mp4"],
          ["title", "Untitled"],
          ["summary", ""],
          ["t", "openvine"],
          ["client", "openvine"],
          ["h", "vine"]
        ],
        '',
      );

      // New NIP-32222 format
      final compliantEvent = Event(
        'd95aa8fc0eff8e488952495b8064991d27fb96ed8652f12cdedc5a4e8b5ae540',
        32222,
        [
          ["d", "vine-id-123"], // Required for addressable events
          ["title", "Untitled"],
          [
            "imeta",
            "url https://api.openvine.co/media/1751355501029-7553157a",
            "m video/mp4"
          ],
          ["t", "openvine"],
          ["h", "vine"]
        ],
        '',
      );

      // Legacy format should be rejected
      expect(
        () => VideoEvent.fromNostrEvent(legacyEvent),
        throwsA(isA<ArgumentError>()),
        reason: 'Kind 22 events should be rejected',
      );

      // New format should work
      final compliantVideo = VideoEvent.fromNostrEvent(compliantEvent);
      expect(compliantVideo.hasVideo, true,
          reason: 'NIP-32222 format should work');
      expect(compliantVideo.vineId, 'vine-id-123', reason: 'Should have d tag');
    });
  });
}
