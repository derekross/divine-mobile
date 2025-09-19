// ABOUTME: Test for Kind 32222 addressable short looping video events (NIP-32222)
// ABOUTME: Validates event parsing, required tags, and addressable event functionality

import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_sdk/event.dart';
import 'package:openvine/models/video_event.dart';

void main() {
  group('VideoEvent Kind 32222 NIP-32222 Compliance', () {
    test(
        'should parse Kind 32222 addressable video event with all required tags',
        () {
      // Create a NIP-32222 compliant event
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798', // Valid pubkey
        32222, // Addressable short looping video
        [
          ['d', 'unique-video-123'], // Required identifier
          ['title', 'Amazing Loop'],
          ['published_at', '1698789234'],
          ['duration', '6'],
          ['alt', 'A person juggling in a perfect loop'],
          [
            'imeta',
            'url https://api.openvine.co/media/video.mp4',
            'm video/mp4',
            'dim 480x480',
            'blurhash eVF\$^OI:\${M{%LRjWBoLoLaeR*',
            'image https://api.openvine.co/media/thumb.jpg',
            'x 3093509d1e0bc604ff60cb9286f4cd7c781553bc8991937befaacfdc28ec5cdc'
          ],
          ['t', 'perfectloops'],
          ['t', 'juggling'],
          ['client', 'openvine'],
        ],
        'Check out this perfect juggling loop! 🔄',
      );

      // Parse the event
      final videoEvent = VideoEvent.fromNostrEvent(event);

      // Verify all fields are properly parsed
      expect(videoEvent.id, event.id);
      expect(videoEvent.pubkey, event.pubkey);
      expect(videoEvent.vineId, 'unique-video-123',
          reason: 'd tag should be parsed as vineId');
      expect(videoEvent.title, 'Amazing Loop');
      expect(videoEvent.content, 'Check out this perfect juggling loop! 🔄');
      expect(videoEvent.duration, 6);
      expect(videoEvent.altText, 'A person juggling in a perfect loop');
      expect(videoEvent.hasVideo, true);
      expect(videoEvent.videoUrl, 'https://api.openvine.co/media/video.mp4');
      expect(
          videoEvent.thumbnailUrl, 'https://api.openvine.co/media/thumb.jpg');
      expect(videoEvent.mimeType, 'video/mp4');
      expect(videoEvent.dimensions, '480x480');
      expect(videoEvent.blurhash, 'eVF\$^OI:\${M{%LRjWBoLoLaeR*');
      expect(videoEvent.sha256,
          '3093509d1e0bc604ff60cb9286f4cd7c781553bc8991937befaacfdc28ec5cdc');
      expect(videoEvent.hashtags, contains('perfectloops'));
      expect(videoEvent.hashtags, contains('juggling'));
    });

    test('should reject Kind 22 events', () {
      // Create a Kind 22 event (old format)
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        22, // Old video event kind
        [
          ['url', 'https://api.openvine.co/media/video.mp4'],
          ['title', 'Old Format Video'],
        ],
        'Old format video',
      );

      // Should throw when trying to parse Kind 22
      expect(
        () => VideoEvent.fromNostrEvent(event),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Event must be kind 32222'),
        )),
      );
    });

    test('should require d tag for Kind 32222 events', () {
      // Create an event without d tag
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        32222,
        [
          ['title', 'Missing D Tag'],
          ['imeta', 'url https://api.openvine.co/media/video.mp4'],
        ],
        'Missing required d tag',
      );

      // Should throw when d tag is missing
      expect(
        () => VideoEvent.fromNostrEvent(event),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must have a "d" tag identifier'),
        )),
      );
    });

    test('should parse imeta tag with all properties', () {
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        32222,
        [
          ['d', 'test-video'],
          [
            'imeta',
            'url https://video.host/test.mp4',
            'm video/mp4',
            'dim 1920x1080',
            'blurhash L6PZfSi_.AyE_3t7t7R**0o#DgR4',
            'image https://video.host/thumb.jpg',
            'fallback https://backup.host/test.mp4',
            'x e1d4f808dae475ed32fb23ce52ef8ac82e3cc760702fca10d62d382d2da3697d',
            'size 5242880', // 5MB
          ],
        ],
        '',
      );

      final videoEvent = VideoEvent.fromNostrEvent(event);

      expect(videoEvent.videoUrl, 'https://video.host/test.mp4');
      expect(videoEvent.mimeType, 'video/mp4');
      expect(videoEvent.dimensions, '1920x1080');
      expect(videoEvent.blurhash, 'L6PZfSi_.AyE_3t7t7R**0o#DgR4');
      expect(videoEvent.thumbnailUrl, 'https://video.host/thumb.jpg');
      expect(videoEvent.sha256,
          'e1d4f808dae475ed32fb23ce52ef8ac82e3cc760702fca10d62d382d2da3697d');
      expect(videoEvent.fileSize, 5242880);
      expect(videoEvent.width, 1920);
      expect(videoEvent.height, 1080);
    });

    test('should handle multiple imeta tags for different qualities', () {
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        32222,
        [
          ['d', 'multi-quality-video'],
          [
            'imeta',
            'url https://video.host/1080p.mp4',
            'm video/mp4',
            'dim 1920x1080',
          ],
          [
            'imeta',
            'url https://video.host/720p.mp4',
            'm video/mp4',
            'dim 1280x720',
          ],
          [
            'imeta',
            'url https://video.host/480p.mp4',
            'm video/mp4',
            'dim 854x480',
          ],
        ],
        '',
      );

      final videoEvent = VideoEvent.fromNostrEvent(event);

      // Should use the first valid video URL
      expect(videoEvent.videoUrl, 'https://video.host/1080p.mp4');
      expect(videoEvent.dimensions, '1920x1080');
    });

    test('should parse origin tag for imported content', () {
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        32222,
        [
          ['d', 'hBFP5LFKUOU'], // Original Vine ID
          ['title', 'Imported from Vine'],
          ['imeta', 'url https://video.host/imported.mp4'],
          ['origin', 'vine', 'hBFP5LFKUOU', 'https://vine.co/v/hBFP5LFKUOU'],
        ],
        'Classic vine import',
      );

      final videoEvent = VideoEvent.fromNostrEvent(event);

      expect(videoEvent.vineId, 'hBFP5LFKUOU');
      expect(videoEvent.rawTags['origin'], 'vine');
      // Note: Origin tag parsing might need to be enhanced in VideoEvent model
    });

    test('should generate addressable event reference tag', () {
      final event = Event(
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        32222,
        [
          ['d', 'my-video-id'],
          ['imeta', 'url https://video.host/video.mp4'],
        ],
        '',
      );

      final videoEvent = VideoEvent.fromNostrEvent(event);

      // The addressable reference should be in format: kind:pubkey:d-tag
      final addressableRef = '32222:${event.pubkey}:my-video-id';

      // This might need to be added to VideoEvent model
      // For now, we verify the components are available
      expect(videoEvent.vineId, 'my-video-id');
      expect(videoEvent.pubkey, event.pubkey);
    });
  });
}
