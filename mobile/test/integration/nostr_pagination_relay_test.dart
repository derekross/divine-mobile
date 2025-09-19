// ABOUTME: Test real pagination requests against relay3.openvine.co
import 'package:openvine/utils/unified_logger.dart';
// ABOUTME: Debug exactly what happens with 'until' parameter for historical events

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

void main() async {
  Log.info('🔍 Testing pagination against relay3.openvine.co...\n');

  WebSocket? socket;
  final List<Map<String, dynamic>> receivedEvents = [];

  try {
    // Connect to relay3.openvine.co
    Log.info('1. Connecting to wss://relay3.openvine.co...');
    socket = await WebSocket.connect('wss://relay3.openvine.co');
    Log.info('✅ Connected!\n');

    // Listen for messages
    socket.listen((message) {
      final data = jsonDecode(message);
      Log.info(
          '📨 Received: ${data[0]} ${data.length > 1 ? data[1] : ""}');

      if (data[0] == 'EVENT') {
        final event = data[2];
        receivedEvents.add(event);
        final timestamp = event['created_at'];
        final eventId = (event['id'] as String).substring(0, 8);
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        Log.info('   📺 Event $eventId created: $date');
      } else if (data[0] == 'EOSE') {
        Log.info('   ⏹️ End of stored events\n');
      } else if (data[0] == 'NOTICE') {
        Log.info('   📢 Notice: ${data[1]}');
      }
    });

    // Step 1: Get initial batch of recent events
    Log.info('2. Getting initial 10 recent events...');
    final req1 = jsonEncode([
      'REQ',
      'initial_test',
      {
        'kinds': [22],
        'limit': 10
      }
    ]);
    socket.add(req1);
    Log.info('   📤 Sent: $req1\n');

    // Wait for initial events
    await Future.delayed(Duration(seconds: 3));

    if (receivedEvents.isEmpty) {
      Log.info(
          '❌ No events received! Relay might be empty or not responding.');
      return;
    }

    // Sort events by timestamp to find oldest
    receivedEvents.sort(
        (a, b) => (a['created_at'] as int).compareTo(b['created_at'] as int));
    final oldestEvent = receivedEvents.first;
    final oldestTimestamp = oldestEvent['created_at'] as int;
    final oldestDate =
        DateTime.fromMillisecondsSinceEpoch(oldestTimestamp * 1000);
    final oldestId = (oldestEvent['id'] as String).substring(0, 8);

    Log.info('📊 Initial batch stats:');
    Log.info('   Total events: ${receivedEvents.length}');
    Log.info(
        '   Oldest event: $oldestId at $oldestDate (timestamp: $oldestTimestamp)\n');

    // Step 2: Try to get older events using 'until'
    Log.info(
        '3. Requesting events OLDER than $oldestDate using until=${oldestTimestamp - 1}...');

    // Clear previous subscription
    socket.add(jsonEncode(['CLOSE', 'initial_test']));
    await Future.delayed(Duration(milliseconds: 100));

    final untilTimestamp = oldestTimestamp - 1;
    final req2 = jsonEncode([
      'REQ',
      'pagination_test',
      {
        'kinds': [22],
        'until': untilTimestamp,
        'limit': 10
      }
    ]);

    socket.add(req2);
    Log.info('   📤 Sent: $req2\n');

    // Wait for pagination results
    final int eventCountBefore = receivedEvents.length;
    await Future.delayed(Duration(seconds: 5));
    final int eventCountAfter = receivedEvents.length;
    final int newEvents = eventCountAfter - eventCountBefore;

    Log.info('📊 Pagination results:');
    Log.info('   Events before pagination: $eventCountBefore');
    Log.info('   Events after pagination: $eventCountAfter');
    Log.info('   New events loaded: $newEvents');

    if (newEvents > 0) {
      Log.info(
          '✅ SUCCESS: Pagination worked! Got $newEvents older events');

      // Show details of new events
      final newEventsList = receivedEvents.skip(eventCountBefore).toList();
      for (final event in newEventsList) {
        final timestamp = event['created_at'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        final eventId = (event['id'] as String).substring(0, 8);
        Log.info('   📺 New event $eventId: $date');
      }
    } else {
      Log.info('❌ PROBLEM: No older events found!');
      Log.info('   This could mean:');
      Log.info('   - No older events exist on the relay');
      Log.info('   - The "until" parameter is not working correctly');
      Log.info('   - There is a bug in our pagination logic');
    }

    // Step 3: Test edge case - what if we ask for WAY older events?
    Log.info(
        '\n4. Testing edge case: requesting events from 30 days ago...');
    final thirtyDaysAgo =
        DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch ~/
            1000;

    socket.add(jsonEncode(['CLOSE', 'pagination_test']));
    await Future.delayed(Duration(milliseconds: 100));

    final req3 = jsonEncode([
      'REQ',
      'old_test',
      {
        'kinds': [22],
        'until': thirtyDaysAgo,
        'limit': 5
      }
    ]);

    socket.add(req3);
    Log.info('   📤 Sent: $req3');

    await Future.delayed(Duration(seconds: 3));
    Log.info('   Done with old events test\n');
  } catch (e) {
    Log.info('❌ Error: $e');
  } finally {
    socket?.close();
    Log.info('🔌 Connection closed');
  }
}
