import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/providers/profile_stats_provider.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/services/social_service.dart';

// Generate mocks
@GenerateMocks([SocialService])
import 'profile_stats_provider_test.mocks.dart';

void main() {
  group('ProfileStatsProvider', () {
    late ProviderContainer container;
    late MockSocialService mockSocialService;

    setUp(() {
      mockSocialService = MockSocialService();
      container = ProviderContainer(
        overrides: [
          socialServiceProvider.overrideWithValue(mockSocialService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    group('Initial State', () {
      test('should have correct initial state', () {
        final state = container.read(profileStatsProvider);
        expect(state.isLoading, false);
        expect(state.stats, isNull);
        expect(state.error, isNull);
        expect(state.hasError, false);
        expect(state.hasData, false);
      });
    });

    group('Loading Profile Stats', () {
      const testPubkey = 'test_pubkey_123';

      test('should load profile stats successfully', () async {
        // Mock social service responses
        when(mockSocialService.getFollowerStats(testPubkey)).thenAnswer(
          (_) async => {'followers': 100, 'following': 50},
        );
        when(mockSocialService.getUserVideoCount(testPubkey)).thenAnswer(
          (_) async => 25,
        );

        // Load stats using the notifier
        final notifier = container.read(profileStatsProvider.notifier);
        await notifier.loadStats(testPubkey);

        // Verify final state
        final state = container.read(profileStatsProvider);
        expect(state.isLoading, false);
        expect(state.hasData, true);
        expect(state.error, isNull);

        // Verify stats content
        final stats = state.stats!;
        expect(stats.videoCount, 25);
        expect(stats.totalLikes, 0); // Not showing reactions for now
        expect(stats.followers, 100);
        expect(stats.following, 50);
        expect(stats.totalViews, 0); // Placeholder

        // Verify service calls
        verify(mockSocialService.getFollowerStats(testPubkey)).called(1);
        verify(mockSocialService.getUserVideoCount(testPubkey)).called(1);
      });

      test('should handle loading errors gracefully', () async {
        // Mock service failure
        when(mockSocialService.getFollowerStats(testPubkey)).thenThrow(
          Exception('Network error'),
        );

        // Load stats using the notifier
        final notifier = container.read(profileStatsProvider.notifier);
        await notifier.loadStats(testPubkey);

        // Verify error state
        final state = container.read(profileStatsProvider);
        expect(state.isLoading, false);
        expect(state.hasError, true);
        expect(state.error, contains('Network error'));
        expect(state.stats, isNull);
      });

      test('should refresh stats by clearing cache', () async {
        // First load
        when(mockSocialService.getFollowerStats(testPubkey)).thenAnswer(
          (_) async => {'followers': 100, 'following': 50},
        );
        when(mockSocialService.getUserVideoCount(testPubkey)).thenAnswer(
          (_) async => 25,
        );

        final notifier = container.read(profileStatsProvider.notifier);
        await notifier.loadStats(testPubkey);
        clearInteractions(mockSocialService);

        // Mock updated stats
        when(mockSocialService.getFollowerStats(testPubkey)).thenAnswer(
          (_) async => {'followers': 150, 'following': 75},
        );
        when(mockSocialService.getUserVideoCount(testPubkey)).thenAnswer(
          (_) async => 30,
        );

        // Refresh stats
        await notifier.refreshStats(testPubkey);

        // Should have new stats
        final state = container.read(profileStatsProvider);
        expect(state.stats!.videoCount, 30);
        expect(state.stats!.followers, 150);
        expect(state.stats!.following, 75);

        // Should have called services again
        verify(mockSocialService.getFollowerStats(testPubkey)).called(1);
        verify(mockSocialService.getUserVideoCount(testPubkey)).called(1);
      });

      test('should clear error state', () async {
        // Create error state first
        when(mockSocialService.getFollowerStats(testPubkey)).thenThrow(
          Exception('Network error'),
        );

        final notifier = container.read(profileStatsProvider.notifier);
        await notifier.loadStats(testPubkey);

        // Verify error state
        var state = container.read(profileStatsProvider);
        expect(state.hasError, true);

        // Clear error
        notifier.clearError();

        // Verify error cleared
        state = container.read(profileStatsProvider);
        expect(state.error, isNull);
        expect(state.hasError, false);
      });

      test('should clear all cache', () {
        clearAllProfileStatsCache();
        // Just verify it doesn't throw - internal state is private
      });
    });

    group('Utility Methods', () {
      test('should format counts correctly', () {
        expect(formatProfileStatsCount(0), '0');
        expect(formatProfileStatsCount(999), '999');
        expect(formatProfileStatsCount(1000), '1k');
        expect(formatProfileStatsCount(1500), '1.5k');
        expect(formatProfileStatsCount(1000000), '1M');
        expect(formatProfileStatsCount(2500000), '2.5M');
        expect(formatProfileStatsCount(1000000000), '1B');
        expect(formatProfileStatsCount(3200000000), '3.2B');
      });
    });

    group('ProfileStats Model', () {
      test('should create ProfileStats correctly', () {
        final stats = ProfileStats(
          videoCount: 25,
          totalLikes: 500,
          followers: 100,
          following: 50,
          totalViews: 1000,
          lastUpdated: DateTime.now(),
        );

        expect(stats.videoCount, 25);
        expect(stats.totalLikes, 500);
        expect(stats.followers, 100);
        expect(stats.following, 50);
        expect(stats.totalViews, 1000);
      });

      test('should copy ProfileStats with changes', () {
        final original = ProfileStats(
          videoCount: 25,
          totalLikes: 500,
          followers: 100,
          following: 50,
          totalViews: 1000,
          lastUpdated: DateTime.now(),
        );

        final updated = original.copyWith(
          videoCount: 30,
          totalLikes: 600,
        );

        expect(updated.videoCount, 30);
        expect(updated.totalLikes, 600);
        expect(updated.followers, 100); // Unchanged
        expect(updated.following, 50); // Unchanged
        expect(updated.totalViews, 1000); // Unchanged
      });

      test('should have meaningful toString', () {
        final stats = ProfileStats(
          videoCount: 25,
          totalLikes: 500,
          followers: 100,
          following: 50,
          totalViews: 1000,
          lastUpdated: DateTime.now(),
        );

        final string = stats.toString();
        expect(string, contains('25'));
        expect(string, contains('500'));
        expect(string, contains('100'));
        expect(string, contains('50'));
        expect(string, contains('1000'));
      });
    });
  });
}
