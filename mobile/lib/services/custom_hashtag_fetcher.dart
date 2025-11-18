// ABOUTME: Custom WebSocket-based hashtag video fetcher using NIP-50 search
// ABOUTME: Bypasses nostr_sdk for direct relay communication with hashtag search

import 'dart:async';
import 'dart:convert';
import 'package:nostr_sdk/nostr_sdk.dart' as sdk;
import 'package:openvine/models/video_event.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class CustomHashtagFetcher {
  static const String DEFAULT_RELAY = 'wss://relay.divine.video';

  /// Fetch videos for a hashtag using NIP-50 search
  /// Returns a Future with list of VideoEvent objects
  static Future<List<VideoEvent>> fetchHashtagVideos({
    required String hashtag,
    String relayUrl = DEFAULT_RELAY,
    int limit = 100,
    String? sortMode, // 'hot', 'top', 'rising', 'controversial'
  }) async {
    final normalizedHashtag = hashtag.toLowerCase().trim();
    final videos = <VideoEvent>[];

    // Build NIP-50 search query
    final searchQuery = sortMode != null && sortMode.isNotEmpty
        ? '#$normalizedHashtag sort:$sortMode'
        : '#$normalizedHashtag';

    Log.info(
      '🔍 CustomHashtagFetcher: Connecting to $relayUrl for hashtag #$normalizedHashtag',
      name: 'CustomHashtagFetcher',
      category: LogCategory.video,
    );

    WebSocketChannel? channel;
    StreamSubscription? subscription;

    try {
      // Connect to relay
      final uri = Uri.parse(relayUrl);
      channel = WebSocketChannel.connect(uri);

      await channel.ready;

      Log.info(
        '✅ CustomHashtagFetcher: Connected to $relayUrl',
        name: 'CustomHashtagFetcher',
        category: LogCategory.video,
      );

      // Generate subscription ID
      final subId = 'hashtag_${DateTime.now().millisecondsSinceEpoch}';

      // Create REQ message with standard #t tag filter
      // Note: Using #t tag instead of NIP-50 search for better relay compatibility
      final reqMessage = [
        'REQ',
        subId,
        {
          'kinds': [34236], // Only addressable video events
          'limit': limit,
          '#t': [normalizedHashtag], // Standard hashtag tag filter
        }
      ];

      final reqJson = jsonEncode(reqMessage);
      Log.info(
        '📨 CustomHashtagFetcher: Sending REQ: $reqJson',
        name: 'CustomHashtagFetcher',
        category: LogCategory.video,
      );

      channel.sink.add(reqJson);

      // Listen for events
      int eventCount = 0;
      final completer = Completer<void>();

      subscription = channel.stream.listen(
        (message) {
          try {
            final decoded = jsonDecode(message as String) as List;
            final messageType = decoded[0] as String;

            if (messageType == 'EVENT') {
              final eventSubId = decoded[1] as String;
              if (eventSubId != subId) return;

              final eventJson = decoded[2] as Map<String, dynamic>;
              eventCount++;

              Log.debug(
                '📥 CustomHashtagFetcher: Received event #$eventCount',
                name: 'CustomHashtagFetcher',
                category: LogCategory.video,
              );

              // Parse as VideoEvent and add to list
              try {
                // Create Event from JSON, then VideoEvent from that
                final event = sdk.Event.fromJson(eventJson);
                final video = VideoEvent.fromNostrEvent(event);
                videos.add(video);
              } catch (e) {
                Log.warning(
                  'CustomHashtagFetcher: Failed to parse event: $e',
                  name: 'CustomHashtagFetcher',
                  category: LogCategory.video,
                );
              }
            } else if (messageType == 'EOSE') {
              final eoseSubId = decoded[1] as String;
              if (eoseSubId == subId) {
                Log.info(
                  '✅ CustomHashtagFetcher: EOSE received. Total events: $eventCount',
                  name: 'CustomHashtagFetcher',
                  category: LogCategory.video,
                );
                completer.complete();
              }
            }
          } catch (e, stackTrace) {
            Log.error(
              'CustomHashtagFetcher: Error parsing message: $e',
              name: 'CustomHashtagFetcher',
              category: LogCategory.video,
              error: e,
              stackTrace: stackTrace,
            );
          }
        },
        onError: (error) {
          Log.error(
            'CustomHashtagFetcher: WebSocket error: $error',
            name: 'CustomHashtagFetcher',
            category: LogCategory.video,
            error: error,
          );
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        onDone: () {
          Log.info(
            '🔌 CustomHashtagFetcher: WebSocket closed',
            name: 'CustomHashtagFetcher',
            category: LogCategory.video,
          );
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      // Wait for EOSE or error
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Log.warning(
            '⏰ CustomHashtagFetcher: Timeout waiting for EOSE after $eventCount events',
            name: 'CustomHashtagFetcher',
            category: LogCategory.video,
          );
        },
      );

      // Close subscription
      final closeMessage = jsonEncode(['CLOSE', subId]);
      channel.sink.add(closeMessage);

    } catch (e, stackTrace) {
      Log.error(
        'CustomHashtagFetcher: Fatal error: $e',
        name: 'CustomHashtagFetcher',
        category: LogCategory.video,
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      await subscription?.cancel();
      await channel?.sink.close();
    }

    Log.info(
      '✅ CustomHashtagFetcher: Returning ${videos.length} videos for #$normalizedHashtag',
      name: 'CustomHashtagFetcher',
      category: LogCategory.video,
    );

    return videos;
  }

}
