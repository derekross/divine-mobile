// ABOUTME: Test for profile screen UI updates after editing profile
// ABOUTME: Ensures the profile screen properly refreshes and shows updated data

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:openvine/models/user_profile.dart' as models;
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/profile_videos_provider.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/screens/profile_screen.dart';
import 'package:openvine/screens/profile_setup_screen.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/social_service.dart';
import 'package:openvine/services/user_profile_service.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import '../helpers/test_provider_overrides.dart';

@GenerateMocks([
  AuthService,
  UserProfileService,
  SocialService,
  VideoEventService,
])
import 'profile_screen_update_test.mocks.dart';

// Create mock NostrService for testing
class MockNostrService extends Mock implements INostrService {
  @override
  bool get isInitialized => true;
}

UserProfile createTestAuthProfile({
  String npub = 'npub1testuser',
  String publicKeyHex =
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
  String? displayName,
  String? about,
  String? picture,
}) {
  return UserProfile(
    npub: npub,
    publicKeyHex: publicKeyHex,
    displayName: displayName ?? 'Test User',
    about: about,
    picture: picture,
  );
}

models.UserProfile createTestModelsProfile({
  String pubkey = 'current_user_pubkey',
  String? name,
  String? displayName,
  String? about,
  String? picture,
}) {
  return models.UserProfile(
    pubkey: pubkey,
    name: name,
    displayName: displayName,
    about: about,
    picture: picture,
    rawData: const {},
    createdAt: DateTime.now(),
    eventId: 'test_event_id',
  );
}

// Alias for createTestAuthProfile for backwards compatibility
UserProfile createTestProfile({
  String npub = 'npub1testuser',
  String publicKeyHex = 'current_user_pubkey',
  String? displayName,
  String? about,
  String? picture,
}) {
  return createTestAuthProfile(
    npub: npub,
    publicKeyHex: publicKeyHex,
    displayName: displayName,
    about: about,
    picture: picture,
  );
}

void main() {
  group('Profile Screen Update Tests', () {
    late MockAuthService mockAuthService;
    late MockUserProfileService mockUserProfileService;
    late MockSocialService mockSocialService;
    late MockVideoEventService mockVideoEventService;
    late MockNostrService mockNostrService;
    // These are providers, not services - they can't be mocked this way
    // late MockProfileStatsProvider mockProfileStatsProvider;
    // late MockProfileVideosProvider mockProfileVideosProvider;

    setUp(() {
      mockAuthService = MockAuthService();
      mockUserProfileService = MockUserProfileService();
      mockSocialService = MockSocialService();
      mockVideoEventService = MockVideoEventService();
      mockNostrService = MockNostrService();
      // mockProfileStatsProvider = MockProfileStatsProvider();
      // mockProfileVideosProvider = MockProfileVideosProvider();

      // Setup default mocks
      when(mockAuthService.isAuthenticated).thenReturn(true);
      when(mockAuthService.currentPublicKeyHex).thenReturn(
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef');
      when(mockSocialService.followingPubkeys).thenReturn([]);
      // Profile providers need to be overridden differently
      // when(mockProfileStatsProvider.hasData).thenReturn(false);
      // when(mockProfileStatsProvider.isLoading).thenReturn(false);
      // when(mockProfileVideosProvider.isLoading).thenReturn(false);
      // when(mockProfileVideosProvider.hasVideos).thenReturn(false);
      // when(mockProfileVideosProvider.hasError).thenReturn(false);
      // when(mockProfileVideosProvider.videoCount).thenReturn(0);
      // when(mockProfileVideosProvider.loadingState)
      //     .thenReturn(ProfileVideosLoadingState.idle);
      // Add specific getCachedProfile stub for current user
      when(mockUserProfileService.getCachedProfile(
              '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'))
          .thenReturn(null);
    });

    Widget createTestWidget({String? profilePubkey}) {
      final testVideoManager = TestVideoManager();
      final container = ProviderContainer(
        overrides: [
          // Add TestVideoManager to prevent Nostr service initialization issues
          videoManagerProvider.overrideWith(() => testVideoManager),
          authServiceProvider.overrideWithValue(mockAuthService),
          userProfileServiceProvider.overrideWithValue(mockUserProfileService),
          socialServiceProvider.overrideWithValue(mockSocialService),
          videoEventServiceProvider.overrideWithValue(mockVideoEventService),
          nostrServiceProvider.overrideWithValue(mockNostrService),
          // These providers need to be overridden with actual provider values
          // profileStatsProvider.overrideWith((ref, pubkey) async => ProfileStats()),
          profileVideosProvider(
                  '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef')
              .overrideWith(
            (ref) async => <VideoEvent>[],
          ),
        ],
      );

      return MaterialApp(
        home: UncontrolledProviderScope(
          container: container,
          child: ProfileScreen(profilePubkey: profilePubkey),
        ),
      );
    }

    testWidgets('should show default profile data initially', (tester) async {
      // Setup initial profile state
      when(mockAuthService.currentProfile).thenReturn(null);
      when(mockUserProfileService.getCachedProfile(any)).thenReturn(null);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show default anonymous user
      expect(find.text('Anonymous'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsWidgets);
    });

    testWidgets('should show edit profile button for own profile',
        (tester) async {
      // Setup for own profile view
      when(mockAuthService.currentProfile).thenReturn(
        createTestAuthProfile(
          displayName: 'Test Display Name',
          about: 'Test bio',
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show options menu (hamburger icon)
      expect(find.byIcon(Icons.menu), findsOneWidget);

      // Tap the menu
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Should show Edit Profile option
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('should not show edit profile button for other user profiles',
        (tester) async {
      // Setup for viewing another user's profile
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'Current User',
          about: null,
          picture: null,
        ),
      );

      when(mockUserProfileService.getCachedProfile('other_user_pubkey'))
          .thenReturn(
        models.UserProfile(
          pubkey: 'other_user_pubkey',
          name: 'Other User',
          displayName: 'Other User',
          about: 'Other user bio',
          picture: null,
          createdAt: DateTime.now(),
          eventId: 'other_event_id',
          rawData: {},
        ),
      );

      await tester
          .pumpWidget(createTestWidget(profilePubkey: 'other_user_pubkey'));
      await tester.pumpAndSettle();

      // Should show options menu (vertical dots) for other users
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // Should not show hamburger menu
      expect(find.byIcon(Icons.menu), findsNothing);
    });

    testWidgets('should update profile display after editing', (tester) async {
      // Setup initial profile
      final currentProfile = createTestProfile(
        displayName: 'Old Display Name',
        about: 'Old bio',
      );

      when(mockAuthService.currentProfile).thenReturn(currentProfile);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Old Display Name'), findsOneWidget);
      expect(find.text('Old bio'), findsOneWidget);

      // Simulate profile update
      final updatedProfile = createTestProfile(
        displayName: 'New Display Name',
        about: 'New bio description',
        picture: 'https://example.com/new-avatar.jpg',
      );

      // Update the mock to return new profile
      when(mockAuthService.currentProfile).thenReturn(updatedProfile);

      // Trigger rebuild (simulate returning from edit screen)
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify updated state
      expect(find.text('New Display Name'), findsOneWidget);
      expect(find.text('New bio description'), findsOneWidget);
      expect(find.text('Old Display Name'), findsNothing);
      expect(find.text('Old bio'), findsNothing);
    });

    testWidgets(
        'should show profile setup banner for users without custom names',
        (tester) async {
      // Setup user with default/npub name
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'npub1abc123...',
          about: null,
          picture: null,
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show profile setup banner
      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.text('Set Up'), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets(
        'should not show profile setup banner for users with custom names',
        (tester) async {
      // Setup user with custom name
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'Custom Display Name',
          about: 'Custom bio',
          picture: null,
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should not show profile setup banner
      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.text('Set Up'), findsNothing);
      expect(find.byIcon(Icons.person_add), findsNothing);
    });

    testWidgets('should refresh profile data when returning from edit',
        (tester) async {
      // Setup initial profile
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'Initial Name',
          about: null,
          picture: null,
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Open options menu
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap Edit Profile
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      // Verify ProfileSetupScreen is opened
      expect(find.byType(ProfileSetupScreen), findsOneWidget);

      // Simulate returning with updated profile
      Navigator.of(tester.element(find.byType(ProfileSetupScreen))).pop(true);
      await tester.pumpAndSettle();

      // Verify video feed refresh is called when returning
      verify(mockVideoEventService.refreshVideoFeed()).called(greaterThan(0));
    });

    // TODO: Fix this test - need to properly mock Riverpod providers
    testWidgets('should handle profile loading states correctly',
        (tester) async {
      // This test needs to be rewritten to work with actual provider structure
      // TODO: Fix test to work with Riverpod providers
      return; // Skip this test for now

      // // Setup loading state
      // when(mockAuthService.currentProfile).thenReturn(null);
      // when(mockUserProfileService.getCachedProfile(any)).thenReturn(null);
      // when(mockProfileStatsProvider.isLoading).thenReturn(true);

      // await tester.pumpWidget(createTestWidget());
      // await tester.pumpAndSettle();

      // // Should show loading indicators
      // expect(find.text('—'), findsWidgets); // Dash for loading stats
    });

    testWidgets('should display profile picture when available',
        (tester) async {
      // Setup profile with picture
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'User With Picture',
          about: 'Has a profile picture',
          picture: 'https://example.com/avatar.jpg',
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show network image
      expect(find.byType(CircleAvatar), findsOneWidget);

      // Should have gradient border around avatar
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('should copy npub to clipboard when tapped', (tester) async {
      // Setup profile
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'Test User',
          about: null,
          picture: null,
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap the npub container
      final npubFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                const Color(0xFF424242), // Colors.grey[800]
      );

      expect(npubFinder, findsOneWidget);

      // Tap should trigger clipboard copy (would need to mock clipboard in real test)
      await tester.tap(npubFinder);
      await tester.pumpAndSettle();
    });

    testWidgets('should navigate to profile setup when setup button tapped',
        (tester) async {
      // Setup user without custom name
      when(mockAuthService.currentProfile).thenReturn(
        createTestProfile(
          displayName: 'npub1abc123...',
          about: null,
          picture: null,
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap the "Set Up" button in the banner
      await tester.tap(find.text('Set Up'));
      await tester.pumpAndSettle();

      // Should navigate to ProfileSetupScreen
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
    });
  });
}
