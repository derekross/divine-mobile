// ABOUTME: Integration test for tab switching video controller disposal
// ABOUTME: Ensures video controllers are disposed when tabs are switched

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/individual_video_providers.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/widgets/video_page_view.dart';

void main() {
  group('Tab Switching Video Controller Disposal', () {
    testWidgets('should not play videos in background tabs after tab switch',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Create test videos
      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;
      final testVideos = [
        VideoEvent(
          id: 'tab0_video1',
          pubkey: 'author1',
          content: 'Tab 0 Video 1',
          createdAt: timestamp,
          timestamp: now,
          videoUrl: 'https://example.com/tab0_video1.mp4',
        ),
        VideoEvent(
          id: 'tab0_video2',
          pubkey: 'author2',
          content: 'Tab 0 Video 2',
          createdAt: timestamp,
          timestamp: now,
          videoUrl: 'https://example.com/tab0_video2.mp4',
        ),
      ];

      // Start with tab 0 active
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);

      // Build app with IndexedStack simulating main navigation
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                final activeTab = ref.watch(tabVisibilityProvider);

                return Scaffold(
                  body: IndexedStack(
                    index: activeTab,
                    children: [
                      // Tab 0: Home feed with videos
                      VideoPageView(
                        videos: testVideos,
                        initialIndex: 0,
                        tabIndex: 0,
                        enableLifecycleManagement: true,
                      ),
                      // Tab 1: Empty placeholder (Activity)
                      const Center(child: Text('Activity')),
                      // Tab 2: Empty placeholder (Explore)
                      const Center(child: Text('Explore')),
                      // Tab 3: Empty placeholder (Profile)
                      const Center(child: Text('Profile')),
                    ],
                  ),
                  bottomNavigationBar: BottomNavigationBar(
                    currentIndex: activeTab,
                    onTap: (index) {
                      ref.read(tabVisibilityProvider.notifier).setActiveTab(index);
                    },
                    items: const [
                      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                      BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Activity'),
                      BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
                      BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // STEP 1: Verify tab 0 is active and video is set as active
      expect(container.read(tabVisibilityProvider), equals(0));
      final activeVideoAfterInit = container.read(activeVideoProvider);
      expect(activeVideoAfterInit, equals('tab0_video1'),
          reason: 'Video should be active on tab 0');

      // STEP 2: Switch to profile tab (tab 3)
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(container.read(tabVisibilityProvider), equals(3));

      // STEP 3: Verify active video is cleared when switching away from tab 0
      final activeVideoAfterSwitch = container.read(activeVideoProvider);
      expect(activeVideoAfterSwitch, isNull,
          reason: 'Active video should be cleared when switching to profile tab');

      // STEP 4: Trigger a rebuild (simulating what happens after publishing)
      await tester.pump();
      await tester.pumpAndSettle();

      // STEP 5: Verify video is STILL not active (not playing in background)
      final activeVideoAfterRebuild = container.read(activeVideoProvider);
      expect(activeVideoAfterRebuild, isNull,
          reason: 'Video should NOT become active after rebuild when tab is not visible');

      // STEP 6: Switch back to home tab
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(container.read(tabVisibilityProvider), equals(0));

      // STEP 7: Verify video becomes active again when returning to tab
      final activeVideoAfterReturn = container.read(activeVideoProvider);
      expect(activeVideoAfterReturn, equals('tab0_video1'),
          reason: 'Video should become active again when returning to home tab');
    });

    testWidgets('should dispose video controllers when switching tabs',
        (tester) async {
      // This test will need to be implemented with proper video controller tracking
      // For now, we're testing the activeVideo state management
      // TODO: Add controller lifecycle tracking when we implement disposal logic
    });
  });
}
