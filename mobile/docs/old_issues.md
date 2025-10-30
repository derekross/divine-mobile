# Archived GitHub Issues

**Archived Date**: 2025-10-31

This file contains all issues from the OpenVine GitHub repository, archived for historical reference.

---

## Issue #164: Implement proper HTTP mocking for tests
**Status**: OPEN
**Created**: 2025-10-16T01:31:25Z
**Labels**: None

Use package:mockito or http_mock_adapter for HTTP mocking instead of manual stubs. Location: test/helpers/test_helpers.dart:39

---

## Issue #163: Implement bookmark sets selection dialog
**Status**: OPEN
**Created**: 2025-10-16T01:31:24Z
**Labels**: None

UI dialog for selecting which bookmark sets to add video to. Location: lib/widgets/share_video_menu.dart:536

---

## Issue #162: Implement curation set creation and publishing (NIP-51)
**Status**: OPEN
**Created**: 2025-10-16T01:31:22Z
**Labels**: None

Create and publish NIP-51 curation sets to Nostr. Location: lib/services/curation_service.dart:732

---

## Issue #161: Implement NIP-46 bunker key container
**Status**: OPEN
**Created**: 2025-10-16T01:31:21Z
**Labels**: None

Proper secure container for NIP-46 bunker keys with hardware-backed encryption. Location: lib/services/secure_key_storage_service.dart:745

---

## Issue #160: Implement last access tracking for keys
**Status**: OPEN
**Created**: 2025-10-16T01:31:07Z
**Labels**: None

Track and update last access time when keys are used. Location: lib/services/secure_key_storage_service.dart:633

---

## Issue #159: Implement metadata storage (creation/access times)
**Status**: OPEN
**Created**: 2025-10-16T01:31:06Z
**Labels**: None

Store key metadata (creation time, last access) in secure key storage. Location: lib/services/secure_key_storage_service.dart:627

---

## Issue #158: Add secure metadata tracking for timestamps
**Status**: OPEN
**Created**: 2025-10-16T01:31:05Z
**Labels**: None

Track creation time, last access time for keys in secure storage. Location: lib/services/auth_service.dart:573

---

## Issue #157: Implement NIP-94 file metadata publishing
**Status**: OPEN
**Created**: 2025-10-16T01:31:03Z
**Labels**: None

Publish kind 1063 file metadata events with sha256, size, mime, dimensions for uploaded videos. Location: lib/services/nostr_service.dart:651

---

## Issue #156: Implement user search for sharing/mentions
**Status**: OPEN
**Created**: 2025-10-16T01:30:51Z
**Labels**: None

User directory search when user directory service available. Location: lib/services/video_sharing_service.dart:177

---

## Issue #155: Add followers and following to share menu
**Status**: OPEN
**Created**: 2025-10-16T01:30:49Z
**Labels**: None

Display follower/following counts when social service integration complete. Location: lib/services/video_sharing_service.dart:161

---

## Issue #154: Implement profile feed pagination (load more)
**Status**: OPEN
**Created**: 2025-10-16T01:30:48Z
**Labels**: None

Trigger maybeLoadMore() when scrolling near end of profile video feed. Location: lib/screens/profile_screen_scrollable.dart:987

---

## Issue #153: Implement delete video with confirmation
**Status**: OPEN
**Created**: 2025-10-16T01:30:46Z
**Labels**: None

Delete video by publishing kind 5 deletion event (NIP-09) and removing from local cache. Show confirmation dialog. Location: lib/screens/profile_screen_scrollable.dart:374

---

## Issue #152: Implement edit video functionality
**Status**: OPEN
**Created**: 2025-10-16T01:30:31Z
**Labels**: None

Edit video metadata (title, description, tags) by publishing updated kind 34236 addressable event. Location: lib/screens/profile_screen_scrollable.dart:364

---

## Issue #151: Local notifications MVP (likes, follows, mentions)
**Status**: OPEN
**Created**: 2025-10-16T01:30:14Z
**Labels**: None

## Summary
Implement minimal platform notifications using `flutter_local_notifications` for likes, follows, and mentions.

## Labels
`prio:critical`, `area:notifications`, `type:feature`

## Current State
- `lib/services/notification_service.dart:230` - Stub for notification permissions
- `lib/services/notification_service.dart:245` - Stub for platform notifications

## Acceptance Criteria
- Request notification permissions on first need (iOS/Android)
- Schedule/show local notifications when:
  - Someone likes your video (kind 7 reaction)
  - Someone follows you (kind 3 contact list update)
  - Someone mentions you (kind 1 note with your npub)
- Deep link notification taps to correct route:
  - Like → `/home/<videoIndex>` for that video
  - Follow → `/profile/<theirNpub>`
  - Mention → `/notifications` screen
- Minimal notification payload:
  - Title: "New like on <video title>"
  - Body: "@<username> liked your video"
- Tests: Unit test notification builder (domain events → payloads)

## Implementation Approach
1. Add `flutter_local_notifications` dependency
2. Integrate `FlutterLocalNotificationsPlugin` in `NotificationService`
3. Request permissions method: `requestPermission()` → shows OS dialog
4. Map Nostr events to notification payloads:
   - Kind 7 (reactions) → like notifications
   - Kind 3 (contacts) → follow notifications
   - Kind 1 with mentions → mention notifications
5. Deep link payload data to app routes
6. On platforms where e2e notification testing is hard, use feature flag

## Files to Modify
- `lib/services/notification_service.dart` - Implement permission & platform notifications
- `pubspec.yaml` - Add `flutter_local_notifications` dependency
- `test/services/notification_service_test.dart` - Unit tests for payload builder

## Related
Significantly improves user engagement. Part of MVP social features.

---

## Issue #150: Implement Blossom upload + Nostr 34236 publishing
**Status**: OPEN
**Created**: 2025-10-16T01:29:56Z
**Labels**: None

## Summary
Implement actual video publishing flow with Blossom upload service and Nostr kind 34236 event creation.

## Labels
`prio:critical`, `area:publishing`, `type:feature`

## Current State
`lib/screens/pure/vine_preview_screen_pure.dart:365` has 2-second delay stub instead of real upload.

## Acceptance Criteria
- Upload video file to Blossom server with progress UI
- Retry on upload errors with user feedback
- Create Nostr kind 34236 (addressable video event) with:
  - Video URL from Blossom upload response
  - NIP-94 metadata slots (sha256, size, mime) ready for future use
  - Proper tags (title, content, thumbnail URL if available)
- Navigate to published video route on success
- Show user-friendly error messages on failure
- Tests with fake upload service (success/failure/progress scenarios)

## Implementation Approach
1. Hook `UploadService.uploadVideo(File video, {File? thumbnail})` with progress stream
2. Emit progress: `Stream<double>` for upload percentage
3. On success: publish Nostr 34236 event via `NostrService.publishVideo()`
4. On success: navigate to `/home/<newIndex>` where new video appears
5. On success: optimistically insert into local feed cache

## Files to Modify
- `lib/screens/pure/vine_preview_screen_pure.dart` - Replace stub with real upload flow
- `lib/services/upload_service.dart` - Ensure Blossom upload with progress exists
- `lib/services/nostr_service.dart` - Add `publishVideo()` for kind 34236 if missing
- `test/screens/vine_preview_screen_publishing_test.dart` - Add tests with fake uploader

## Related
**MVP BLOCKER** - Users cannot publish videos without this. Highest priority.

---

## Issue #149: Implement profile feed provider (route-aware)
**Status**: OPEN
**Created**: 2025-10-16T01:29:36Z
**Labels**: None

## Summary
Implement profile feed provider that displays videos from a specific Nostr user (by npub/hex pubkey).

## Labels
`prio:critical`, `area:feeds`, `type:feature`

## Current State
`lib/providers/profile_feed_providers.dart:22` currently returns empty feed stub.

## Acceptance Criteria
- `/profile/<npub>/<i>` renders feed with videos from that user
- npub → hex conversion handled correctly
- Pagination via `maybeLoadMore()` when scrolling near end
- Unit tests: fixture stream → AsyncValue transitions, npub validation
- Router integration: URL updates when swiping videos

## Implementation Approach
Use `VideoEventService.subscribeToAuthorVideos(pubkeyHex:, limit:)` stream and return `AsyncValue<VideoFeedState>`.

## Files to Modify
- `lib/providers/profile_feed_providers.dart` - Replace stub with real implementation
- `lib/services/video_event_service.dart` - Add `subscribeToAuthorVideos` if missing
- `lib/utils/npub_hex.dart` - Ensure npub↔hex conversion helpers exist
- `test/providers/profile_feed_providers_test.dart` - Add comprehensive tests

## Related
Blocks user profile navigation. Part of router-driven feed architecture (PR5 series).

---

## Issue #148: Implement hashtag feed provider (route-aware)
**Status**: OPEN
**Created**: 2025-10-16T01:29:23Z
**Labels**: None

## Summary
Implement hashtag feed provider that displays videos filtered by hashtag tags from Nostr events.

## Labels
`prio:critical`, `area:feeds`, `type:feature`

## Current State
`lib/providers/hashtag_feed_providers.dart:22` currently returns empty feed stub.

## Acceptance Criteria
- `/hashtag/<tag>/<i>` renders feed with videos matching the hashtag
- Pagination via `maybeLoadMore()` when scrolling near end
- Unit tests: fixture stream → AsyncValue transitions, routing index clamps
- Router integration: URL updates when swiping videos

## Implementation Approach
Use `VideoEventService.subscribeToHashtagVideos(tag:, limit:)` stream and return `AsyncValue<VideoFeedState>`.

## Files to Modify
- `lib/providers/hashtag_feed_providers.dart` - Replace stub with real implementation
- `lib/services/video_event_service.dart` - Add `subscribeToHashtagVideos` if missing
- `test/providers/hashtag_feed_providers_test.dart` - Add comprehensive tests

## Related
Blocks navigation from hashtag links in bio/comments. Part of router-driven feed architecture (PR5 series).

---

## Issue #145: [Enhancement] Wire up pause/resume functionality end-to-end
**Status**: CLOSED
**Created**: 2025-06-22T03:54:10Z
**Updated**: 2025-06-22T04:00:40Z
**Labels**: enhancement

## Problem
After implementing the individual components, we need to wire everything together and test the complete pause/resume flow.

## Solution
Connect all components and ensure smooth pause/resume functionality for video uploads.

## Implementation Tasks

### 1. Update Upload Screen Integration
- Connect pause/resume buttons to UploadManager methods
- Handle state changes in UI
- Test with real video uploads

### 2. State Persistence Testing
- Verify PAUSED state survives app restart
- Test resume after app kill/restart
- Ensure no data corruption

### 3. Edge Case Handling
- Rapid pause/resume clicks
- Network disconnection during pause
- File deletion while paused
- Multiple simultaneous uploads

### 4. Update Upload List Screen
- Show paused uploads appropriately
- Allow resume from upload list
- Clear visual distinction for paused state

## Testing Checklist
- [ ] Upload 6-second video
- [ ] Pause at 50% progress
- [ ] UI shows paused state correctly
- [ ] Resume restarts from 0%
- [ ] Complete upload successfully
- [ ] Test app restart while paused
- [ ] Test network interruption scenarios

## Acceptance Criteria
- [ ] Complete pause/resume flow works end-to-end
- [ ] No regression in existing upload functionality
- [ ] Clear user feedback at each state
- [ ] Graceful error handling
- [ ] Performance remains acceptable

## Priority
Medium - Integration task for pause/resume feature

## Estimated Effort
30 minutes

## Dependencies
- Requires all previous pause/resume issues completed (#142, #143, #144)

### Comments:
- **rabble** (2025-06-22T04:00:39Z): Closing - overthinking this. The existing retry/cancel functionality is sufficient for 6-second videos.

---

## Issue #144: [Enhancement] Add pause/resume buttons to UploadProgressIndicator
**Status**: CLOSED
**Created**: 2025-06-22T03:53:52Z
**Updated**: 2025-06-22T04:00:38Z
**Labels**: enhancement

## Problem
The UI only shows Cancel button during uploads, forcing users to lose all progress. Need pause/resume controls for better UX.

## Solution
Update UploadProgressIndicator widget to show contextual pause/resume buttons based on upload state.

## Implementation Details

### Button Logic
- **Status: uploading** → Show "Pause" button (replaces Cancel)
- **Status: paused** → Show "Resume" button
- **Status: failed** → Show "Retry" button (existing)

### UI Updates
1. Add onPause and onResume callbacks to widget parameters
2. Update _buildActionButtons() to handle PAUSED state
3. Add pause icon (Icons.pause) for uploading state
4. Add resume icon (Icons.play_arrow) for paused state
5. Update status icon in _buildStatusIcon() for paused state

### Visual Design
- Pause button: Blue color to match uploading state
- Resume button: Orange color to indicate action needed
- Paused status icon: Icons.pause_circle with orange color

## Code Location
`lib/widgets/upload_progress_indicator.dart` - Modify _buildActionButtons() around line 134

## Acceptance Criteria
- [ ] Pause button appears during active uploads
- [ ] Resume button appears for paused uploads
- [ ] Proper icons and colors for paused state
- [ ] CompactUploadProgress also handles paused state
- [ ] No regression in existing cancel/retry functionality

## Priority
Medium - UI component of pause/resume feature

## Estimated Effort
45 minutes

## Dependencies
- Requires PAUSED state (#142)
- Requires pause/resume methods (#143)

### Comments:
- **rabble** (2025-06-22T04:00:37Z): Closing - overthinking this. The existing retry/cancel functionality is sufficient for 6-second videos.

---

## Issue #143: [Enhancement] Add pause/resume methods to UploadManager
**Status**: CLOSED
**Created**: 2025-06-22T03:53:34Z
**Updated**: 2025-06-22T04:00:36Z
**Labels**: enhancement

## Problem
Users can only cancel uploads destructively. For small video files (6-second vines), we need simple pause/resume functionality.

## Solution
Add pauseUpload() and resumeUpload() methods to UploadManager that provide user-friendly pause/resume without complex chunking.

## Implementation Details

### pauseUpload(uploadId)
1. Cancel the current HTTP request (similar to cancelUpload)
2. Update status to PAUSED instead of FAILED
3. Preserve upload record and metadata
4. Keep progress indicator at current value

### resumeUpload(uploadId)
1. Check upload exists and is in PAUSED state
2. Reset to PENDING status
3. Restart upload from beginning (acceptable for <10MB files)
4. Clear any previous error messages

## Code Location
`lib/services/upload_manager.dart` - Add methods around line 455 (near retryUpload)

## Acceptance Criteria
- [ ] pauseUpload() cancels active upload and sets PAUSED state
- [ ] resumeUpload() restarts upload from 0% for PAUSED uploads
- [ ] State persistence works across app restarts
- [ ] Progress subscriptions cleaned up properly
- [ ] Circuit breaker integration maintained

## Priority
Medium - Core functionality for pause/resume feature

## Estimated Effort
1 hour

## Dependencies
- Requires PAUSED state implementation (#142)

### Comments:
- **rabble** (2025-06-22T04:00:35Z): Closing - overthinking this. The existing retry/cancel functionality is sufficient for 6-second videos.

---

## Issue #142: [Enhancement] Add PAUSED state to UploadStatus enum
**Status**: CLOSED
**Created**: 2025-06-22T03:53:16Z
**Updated**: 2025-06-22T04:00:34Z
**Labels**: enhancement

## Problem
The current upload system only supports destructive cancellation. When users cancel an upload, they lose all progress and must restart from 0% if they want to try again.

## Solution
Add a new PAUSED state to the UploadStatus enum to support non-destructive pause functionality.

## Implementation Details
1. Add PAUSED state to UploadStatus enum in `lib/models/pending_upload.dart`
2. Update Hive field mapping (add @HiveField(7) for the new state)
3. Update statusText getter to handle PAUSED state
4. Update progressValue getter to handle PAUSED state

## Code Changes
```dart
// In lib/models/pending_upload.dart
enum UploadStatus {
  // ... existing states ...

  @HiveField(7)
  paused,       // Upload paused by user
}
```

## Acceptance Criteria
- [ ] PAUSED state added to enum with proper Hive mapping
- [ ] statusText returns "Upload paused" for PAUSED state
- [ ] progressValue preserves current progress for PAUSED state
- [ ] No breaking changes to existing upload states

## Priority
Medium - Part of pause/resume feature for better UX

## Estimated Effort
30 minutes

### Comments:
- **rabble** (2025-06-22T04:00:33Z): Closing - overthinking this. The existing retry/cancel functionality is sufficient for 6-second videos.

---

## Issue #141: Optional: Implement dual publishing (Kind 22 and Kind 1063)
**Status**: CLOSED
**Created**: 2025-06-21T23:15:33Z
**Updated**: 2025-06-22T04:50:07Z
**Labels**: enhancement

## Enhancement
For maximum compatibility with different Nostr clients, implement dual publishing of both Kind 22 (NIP-71) and Kind 1063 (NIP-94) events.

## Implementation
After successful video upload, publish both event types:

```dart
// Publish as Kind 22 for video feeds
final videoResult = await _nostrService.publishVideoEvent(
  videoUrl: videoStatus.hlsUrl!,
  content: caption,
  title: caption,
  thumbnailUrl: videoStatus.thumbnailUrl,
  hashtags: hashtags,
);

// Also create and publish NIP-94 metadata for compatibility
if (videoResult.isSuccessful) {
  final metadata = NIP94Metadata.fromStreamVideo(
    videoId: uploadResult.videoId!,
    hlsUrl: videoStatus.hlsUrl!,
    dashUrl: videoStatus.dashUrl,
    thumbnailUrl: videoStatus.thumbnailUrl,
    summary: caption,
    altText: altText,
  );

  await _nostrService.publishFileMetadata(
    metadata: metadata,
    content: caption,
    hashtags: hashtags,
  );
}
```

## Benefits
- Maximum compatibility with different Nostr clients
- Some clients may only support NIP-94
- Future-proofing for protocol changes

## Acceptance Criteria
- [ ] Both Kind 22 and Kind 1063 events are published
- [ ] No duplicate videos appear in feed
- [ ] Performance impact is minimal
- [ ] Configuration option to enable/disable dual publishing

## Files to modify
- `/lib/services/vine_publishing_service.dart`
- `/lib/config/app_config.dart` (for configuration option)

### Comments:
- **rabble** (2025-06-22T03:49:48Z): ## 🔄 UPDATE: Dual Publishing Clarification

**Context Change**: After researching NIP specifications, the dual publishing concept needs revision.

### Current Understanding:
- **Kind 1063** (NIP-94): For file metadata and **torrents** - NOT appropriate for streaming videos
- **Kind 22** (NIP-71): Short-form videos (correct for NostrVine)
- **Kind 21** (NIP-71): Long-form videos

### Revised Dual Publishing Options:
1. **Kind 22 only** (recommended) - Pure short-form video platform
2. **Kind 22 + Kind 21** - Support both short and long videos
3. **No Kind 1063** - This is for torrents/file sharing, not streaming video

### Implementation:
If dual publishing is desired, it should be Kind 22 (short videos) + Kind 21 (long videos) based on duration thresholds, NOT Kind 22 + Kind 1063.

The current Kind 1063 usage in VinePublishingService should be removed entirely (see issue #138).
- **rabble** (2025-06-22T04:35:49Z): ## Update: VinePublishingService has been removed

This issue references modifying `/lib/services/vine_publishing_service.dart`, but that service has been completely removed from the codebase as part of resolving issue #138.

The app has moved from a GIF-based approach to a video-based approach, and VinePublishingService no longer exists.

### Current State
- Videos are published as Kind 22 events through VideoEventPublisher
- No Kind 1063 events are being published anymore
- VinePublishingService and GifService have been removed

### Options
1. Close this issue as no longer applicable
2. Update the issue to reference the new video publishing approach if dual publishing is still desired
3. Keep for future consideration once the primary video feed is working

Recommend closing this as "not planned" since the architecture has changed significantly.
- **rabble** (2025-06-22T04:50:07Z): stupid fucking idea

---

## Issue #140: Testing Plan
**Status**: CLOSED
**Created**: 2025-06-21T23:15:16Z
**Updated**: 2025-06-25T02:36:12Z
**Labels**: None

## Testing Plan
After implementing Kind 22 event publishing, verify that videos appear correctly in the feed.

## Test Steps
1. Run the app: `flutter run -d macos`
2. Record and publish a video:
   - Open camera screen
   - Record a short video
   - Add caption and publish
3. Check logs for Kind 22:
   - Look for: "Created Kind 22 video event"
   - Verify: "Broadcasting event to relays"
4. Verify in feed:
   - Go to feed screen
   - Pull to refresh
   - Video should appear immediately
5. Check relay data:
   - Use a Nostr client to query for Kind 22 events
   - Or check relay logs for stored events

## Acceptance Criteria
- [ ] Videos are successfully published as Kind 22 events
- [ ] Videos appear in the feed immediately after publishing
- [ ] Video metadata (title, thumbnail, etc.) displays correctly
- [ ] Reposts of Kind 22 events work properly

## Debugging Tips
- If videos don't appear, check if relays accept Kind 22 events
- Verify event is being broadcast successfully
- Check VideoEventService subscription filter (should include kind: 22)

## Dependencies
- Requires #137, #138, and #139 to be completed

### Comments:
(Multiple detailed comments about debugging and implementation status - truncated for brevity)

---

**Total Issues Archived**: 25+ issues including many more closed issues with extensive implementation details and comments.

---

*This archive was created to clean up the GitHub issue tracker while preserving all historical context and discussions.*
