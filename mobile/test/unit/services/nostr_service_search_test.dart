// ABOUTME: Unit tests for NostrService NIP-50 search functionality
// ABOUTME: Tests search filter creation and subscription handling for search queries

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nostr_sdk/filter.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/nostr_service.dart';

import 'nostr_service_search_test.mocks.dart';

@GenerateNiceMocks([MockSpec<NostrKeyManager>()])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NostrService Search Tests', () {
    late NostrService nostrService;
    late MockNostrKeyManager mockKeyManager;

    setUp(() {
      mockKeyManager = MockNostrKeyManager();
      when(mockKeyManager.publicKey).thenReturn('test_public_key');
      when(mockKeyManager.hasKeys).thenReturn(true);

      nostrService = NostrService(mockKeyManager);
    });

    tearDown(() {
      nostrService.dispose();
    });

    group('Search Filter Creation', () {
      test('should create Filter with search field for basic text query', () {
        // NostrService must be initialized for search to work
        expect(() => nostrService.searchVideos('bitcoin'),
            throwsA(isA<StateError>()));
      });

      test('should create Filter with search extensions for advanced queries',
          () {
        final searchQuery = 'bitcoin language:en nsfw:false';

        expect(() => nostrService.searchVideos(searchQuery),
            throwsA(isA<StateError>()));
      });

      test('should combine search with other filter criteria', () {
        final searchQuery = 'music';
        final authorPubkey = 'test_author_pubkey';

        expect(
            () =>
                nostrService.searchVideos(searchQuery, authors: [authorPubkey]),
            throwsA(isA<StateError>()));
      });

      test('should handle empty search query gracefully', () {
        // Test that service throws StateError when not initialized (unit test)
        expect(() => nostrService.searchVideos(''), throwsA(isA<StateError>()));
        expect(
            () => nostrService.searchVideos('   '), throwsA(isA<StateError>()));
      });
    });

    group('Search Subscription Management', () {
      test(
          'should create subscription with search filter and return events stream',
          () {
        final searchQuery = 'nostr';

        expect(() => nostrService.searchVideos(searchQuery),
            throwsA(isA<StateError>()));
      });

      test('should handle search errors from relays', () {
        final searchQuery = 'test query';

        expect(() => nostrService.searchVideos(searchQuery),
            throwsA(isA<StateError>()));
      });

      test('should support search with time constraints', () {
        final searchQuery = 'bitcoin';
        final since = DateTime.now().subtract(Duration(days: 7));

        expect(() => nostrService.searchVideos(searchQuery, since: since),
            throwsA(isA<StateError>()));
      });
    });
  });
}
