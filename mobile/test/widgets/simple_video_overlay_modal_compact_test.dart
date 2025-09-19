// ABOUTME: Simple test to verify video_overlay_modal_compact compiles with Riverpod
// ABOUTME: Minimal test that just confirms the widget can be instantiated

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/widgets/video_overlay_modal_compact.dart';

void main() {
  group('VideoOverlayModalCompact Simple Tests', () {
    testWidgets('should instantiate without error', (tester) async {
      // Create minimal test data
      final testVideo = VideoEvent(
        id: 'test-id',
        content: 'Test content',
        pubkey: 'test-pubkey',
        timestamp: DateTime.now(),
        createdAt: 1000,
        hashtags: [],
      );

      final widget = VideoOverlayModalCompact(
        startingVideo: testVideo,
        videoList: [testVideo],
        contextTitle: 'Test Context',
      );

      // This should not throw an exception if the widget is properly converted
      expect(widget, isA<ConsumerStatefulWidget>());
      expect(
          widget.runtimeType.toString(), contains('VideoOverlayModalCompact'));
    });
  });
}
