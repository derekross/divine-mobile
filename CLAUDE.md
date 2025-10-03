# OpenVine Memory

## Project Overview
OpenVine is a decentralized vine-like video sharing application powered by Nostr with:
- **Flutter Mobile App**: Cross-platform client for capturing and sharing short videos
- **Cloudflare Workers Backend**: Serverless backend for GIF creation and media processing

## Current Focus
**Upload System** - Using Blossom server upload (decentralized media hosting)

## Technology Stack
- **Frontend**: Flutter (Dart) with Camera plugin
- **Backend**: Cloudflare Workers + R2 Storage
- **Protocol**: Nostr (decentralized social network)
- **Media Processing**: Real-time frame capture → GIF creation

## Nostr Architecture

**CRITICAL**: OpenVine uses an embedded relay architecture. The app does NOT connect directly to external relays.

### Architecture Overview
1. **NostrService** (app layer) uses `nostr_sdk` to connect to `ws://localhost:7447`
2. **EmbeddedNostrRelay** runs inside the app, providing:
   - Local WebSocket server on port 7447
   - SQLite event storage for instant queries
   - External relay proxy management
   - P2P sync capabilities
3. **External Relays** (like `wss://relay3.openvine.co`) are managed by the embedded relay

**Key Point**: NostrService should NEVER use `nostr_sdk/relay/Relay` to connect to external relays. Instead, the embedded relay handles external connections via `addExternalRelay()`.

See `mobile/docs/NOSTR_RELAY_ARCHITECTURE.md` for detailed architecture documentation.

## Nostr Event Requirements
OpenVine requires specific Nostr event types for proper functionality:
- **Kind 0**: User profiles (NIP-01) - Required for user display names and avatars
- **Kind 6**: Reposts (NIP-18) - Required for video repost/reshare functionality  
- **Kind 34236**: Addressable short looping videos (NIP-71) - Primary video content with editable metadata
- **Kind 7**: Reactions (NIP-25) - Like/heart interactions
- **Kind 3**: Contact lists (NIP-02) - Follow/following relationships

See `mobile/docs/NOSTR_EVENT_TYPES.md` for complete event type documentation.

## Development Environment

### Local Development Server
**App URL**: http://localhost:53424/

The Flutter app is typically already running locally on Chrome when working on development. Use this URL to access the running app during debugging sessions.

### Debug Environment
- **Platform**: Chrome browser (flutter run -d chrome)
- **Hot Reload**: Available for rapid development
- **Debug Tools**: Chrome DevTools for Flutter debugging

## Build/Test Commands


```bash
./run_dev.sh                       # Run on Chrome in debug mode
./run_dev.sh chrome release        # Run on Chrome in release mode
./run_dev.sh ios debug             # Run on iOS simulator in debug mode


# Standard Flutter commands (run from /mobile directory)
flutter test                       # Run unit tests
flutter analyze                    # Static analysis
```

```bash
./build_native.sh ios release      # Build iOS release
./build_native.sh macos debug      # Build macOS debug
./build_testflight.sh               # Build for TestFlight
./build_web_optimized.sh            # Build optimized web version
./build_ios.sh release             # iOS-specific build
./build_macos.sh release           # macOS-specific build

# Backend commands (run from /backend directory)
npm run dev                        # Local Cloudflare Workers development
npm run deploy                     # Deploy to Cloudflare
npm test                           # Run backend tests
```

### Analytics Database Management
```bash
./flush-analytics-simple.sh true   # Dry run - preview analytics keys to delete
./flush-analytics-simple.sh false  # Actually flush analytics database
```




### Upload Architecture

**Current**:
```
Flutter App → Blossom Server → Nostr Event
```

**Architecture Benefits**:
- User-configurable Blossom media servers
- Fully decentralized media hosting
- No centralized backend dependencies

## API Documentation

**Backend API Reference**: See `docs/BACKEND_API_REFERENCE.md` for complete documentation of all backend endpoints.

**Domain Architecture**:
- User-configured Blossom servers - Decentralized media hosting (primary)

**Share URL Formats**:
- Profile URLs: `https://divine.video/profile/{npub}`
- Video URLs: `https://divine.video/video/{videoId}`

## Native Build Scripts
**IMPORTANT**: Use these scripts instead of direct Flutter builds for iOS/macOS to prevent CocoaPods sync errors.

```bash
# Native builds (run from /mobile directory)
./build_native.sh ios debug        # Build iOS debug with proper CocoaPods sync
./build_native.sh ios release      # Build iOS release  
./build_native.sh macos debug      # Build macOS debug
./build_native.sh macos release    # Build macOS release
./build_native.sh both debug       # Build both platforms

# Platform-specific scripts
./build_ios.sh debug               # iOS-only build script
./build_macos.sh release           # macOS-only build script

# Pre-build scripts for Xcode integration
./pre_build_ios.sh                 # Ensure iOS CocoaPods sync before Xcode build
./pre_build_macos.sh               # Ensure macOS CocoaPods sync before Xcode build
```

**Common CocoaPods Issues**: The scripts automatically handle "sandbox is not in sync with Podfile.lock" errors by ensuring `pod install` runs at the proper time. See `BUILD_SCRIPTS_README.md` for detailed usage and Xcode integration instructions.

## Development Workflow Requirements

### Library Versions and Freshness Policy
- Always choose the latest stable/released versions of libraries, SDKs, and tools.
- Avoid outdated code snippets and deprecated APIs; prefer modern, maintained approaches.
- When searching docs/packages/snippets or installing dependencies, treat the current date as the system time and prefer sources updated recently.
- For Dart/Flutter, add dependencies at their latest stable release (`flutter pub add <package>` without pinning unless required by constraints).
- For Node/TypeScript, prefer the latest stable versions from npm; only pin versions when necessary for compatibility.
- If a newer major version exists, review changelogs/migrations and adopt it unless blocked.

### Destructive Commands Policy
**CRITICAL**: NEVER run destructive git commands or server operations without explicit confirmation from Rabble first.

**Prohibited without confirmation**:
- `git reset --hard`
- `git push --force` or `git push -f`
- `git clean -fd`
- `git branch -D`
- Any database drop/truncate commands
- Any server deployment commands that modify production
- Any commands that delete remote data or resources

**When in doubt**: STOP and ask Rabble before running any command that could permanently delete or overwrite data.

### Code Quality Checks
**MANDATORY**: Always run `flutter analyze` after completing any task that modifies Dart code. This catches:
- Syntax errors
- Linting issues
- Type errors
- Import problems
- Dead code warnings

**Process**:
1. Complete code changes
2. Run `flutter analyze`
3. Fix any issues found
4. Confirm clean analysis before considering task complete

**Never** mark a Flutter task as complete without running analysis and addressing all issues.

## Learning and Memory Management

- YOU MUST use the journal tool frequently to capture technical insights, failed approaches, and user preferences
- Before starting complex tasks, search the journal for relevant past experiences and lessons learned
- Document architectural decisions and their outcomes for future reference
- Track patterns in user feedback to improve collaboration over time
- When you notice something that should be fixed but is unrelated to your current task, document it in your journal rather than fixing it immediately


### Golden Testing (Visual Regression Testing)

OpenVine uses **golden_toolkit** and **alchemist** for visual regression testing. Golden tests capture screenshots of widgets/screens and compare them against reference images to detect unintended UI changes.

**Quick Commands**:
```bash
# Update/generate golden images
./scripts/golden.sh update

# Verify golden tests pass
./scripts/golden.sh verify

# Update specific test
./scripts/golden.sh update test/goldens/widgets/user_avatar_golden_test.dart

# Show changes to golden images
./scripts/golden.sh diff
```

**When to Use Golden Tests**:
- **New UI Components**: Add golden tests for new widgets to establish visual baseline
- **UI Modifications**: Update goldens when making intentional visual changes
- **Before PRs**: Run `./scripts/golden.sh verify` to ensure no visual regressions

**Golden Test Structure**:
```
test/goldens/
├── widgets/     # Component-level golden tests
├── screens/     # Full screen golden tests
├── flows/       # Multi-screen flow tests
└── ci/          # CI-specific goldens
```

**Writing Golden Tests**:
```dart
testGoldens('Widget renders correctly', (tester) async {
  await tester.pumpWidgetBuilder(MyWidget());
  await screenMatchesGolden(tester, 'widget_name');
});
```

See `mobile/docs/GOLDEN_TESTING_GUIDE.md` for complete golden testing documentation.

### Asynchronous Programming Standards
**CRITICAL RULE**: NEVER use arbitrary delays or `Future.delayed()` as a solution to timing issues. This is crude, unreliable, and unprofessional.

**ALWAYS use proper asynchronous patterns instead**:
- **Callbacks**: Use proper event callbacks and listeners
- **Completers**: Use `Completer<T>` for custom async operations
- **Streams**: Use `Stream` and `StreamController` for event sequences  
- **Future chaining**: Use `then()`, `catchError()`, and `whenComplete()`
- **State management**: Use proper state change notifications
- **Platform channels**: Use method channels with proper completion handling

**Examples of FORBIDDEN patterns**:
```dart
// ❌ NEVER DO THIS
await Future.delayed(Duration(milliseconds: 500));
await Future.delayed(Duration(seconds: 2));
Timer(Duration(milliseconds: 100), () => checkAgain());
```

**Examples of CORRECT patterns**:
```dart
// ✅ Use callbacks and completers
final completer = Completer<String>();
controller.onInitialized = () => completer.complete('ready');
return completer.future;

// ✅ Use streams for events
final controller = StreamController<CameraEvent>();
await controller.stream.where((e) => e.type == 'initialized').first;

// ✅ Use proper state notifications
class Controller extends ChangeNotifier {
  bool _initialized = false;
  bool get isInitialized => _initialized;
  Future<void> waitForInitialization() async {
    if (_initialized) return;
    final completer = Completer<void>();
    void listener() {
      if (_initialized) {
        removeListener(listener);
        completer.complete();
      }
    }
    addListener(listener);
    return completer.future;
  }
}
```

## Video Feed Architecture

OpenVine uses a **Riverpod-based reactive architecture** for managing video feeds with multiple subscription types:

### Core Components

**VideoEventService** (`mobile/lib/services/video_event_service.dart`):
- Manages Nostr video event subscriptions by type (homeFeed, discovery, trending, etc.)
- Uses per-subscription-type event lists (`_eventLists` map)
- Supports multiple feed types: `SubscriptionType.homeFeed`, `SubscriptionType.discovery`, `SubscriptionType.hashtag`, etc.
- Provides getters: `homeFeedVideos`, `discoveryVideos`, `getVideos(subscriptionType)`

**VideoManager** (`mobile/lib/providers/video_manager_providers.dart`):
- Riverpod provider managing video player controllers and preloading
- **CRITICAL**: Listens to BOTH `videoEventsProvider` (discovery) AND `homeFeedProvider` (home feed)
- Automatically adds received videos to internal state via `_addVideoEvent()`
- Prevents `VideoManagerException: Video not found in manager state` errors during preloading
- Manages memory efficiently with controller limits and cleanup

**Feed Providers**:
- `videoEventsProvider` → Discovery videos (general public feed)
- `homeFeedProvider` → Videos from users you follow only
- Both providers automatically sync with VideoManager for seamless playback

### Video Feed Flow

1. **Nostr Events** → VideoEventService receives and categorizes by subscription type
2. **Provider Reactivity** → `videoEventsProvider` and `homeFeedProvider` emit updates
3. **VideoManager Sync** → Automatically adds videos from both providers to internal state
4. **UI Display** → Video feed screens render from respective providers
5. **Preloading** → VideoManager can preload any video because it has all videos in state

### Feed Types

- **Home Feed** (`VideoFeedScreen` with `homeFeedProvider`): Shows videos only from followed users
- **Discovery Feed** (`explore_screen.dart` with `videoEventsProvider`): Shows all public videos
- **Hashtag Feeds**: Filter videos by hashtags
- **Profile Feeds**: Show videos from specific users

### Critical Fix (2024-07-30)

Fixed broken bridge between VideoEventService and VideoManager:
- VideoManager was only listening to discovery videos (`videoEventsProvider`)
- Home feed videos (`homeFeedProvider`) weren't being added to VideoManager state
- Result: Videos appeared in feed providers but caused preload failures
- **Solution**: Added home feed listener to VideoManager alongside discovery listener

## AI Rules for Flutter

See `docs/AI_RULES_FLUTTER.md` for complete Flutter/Dart AI guidelines. Always read and follow these rules when generating or editing code in `mobile/`.

## Key Files
- `mobile/lib/services/camera_service.dart` - Hybrid frame capture implementation
- `mobile/lib/screens/camera_screen.dart` - Camera UI with real preview
- `mobile/spike/frame_capture_approaches/` - Research prototypes and analysis
- `backend/src/` - Cloudflare Workers GIF creation logic
- `backend/flush-analytics-simple.sh` - Analytics database flush script

[See ./.claude/memories/ for universal standards]