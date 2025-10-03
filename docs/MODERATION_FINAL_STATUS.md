# OpenVine Moderation System - Final Status (Nostr-First Architecture)

## Completed Services ✅

### 1. ModerationLabelService (NIP-32 kind 1985)
**File:** `lib/services/moderation_label_service.dart` ✅

**Purpose:** Subscribe to trusted labelers who apply structured labels to content

**Features:**
- ✅ Subscribe to multiple labelers (up to 20, Bluesky pattern)
- ✅ Parse NIP-32 label events (L/l tags, e/p targets)
- ✅ Multiple namespace support (moderation, quality, metadata)
- ✅ Label consensus counting ("3 moderators say nsfw")
- ✅ Query by event/pubkey/namespace
- ✅ Local caching with SharedPreferences
- ✅ Integrated with NostrListServiceMixin

**Example:**
```dart
await labelService.subscribeToLabeler(moderatorPubkey);
final hasNSFW = labelService.hasLabel(eventId, 'com.openvine.moderation', 'nsfw');
final counts = labelService.getLabelCounts(eventId); // {'nsfw': 3, 'spam': 1}
```

### 2. ReportAggregationService (NIP-56 kind 1984)
**File:** `lib/services/report_aggregation_service.dart` ✅

**Purpose:** Aggregate community reports from trusted network for threshold-based filtering

**Features:**
- ✅ Subscribe to kind 1984 reports from follows/trusted users
- ✅ Parse NIP-56 report events (e/p/report tags)
- ✅ Aggregate reports by event ID and pubkey
- ✅ Track report types (spam, harassment, illegal, csam, etc)
- ✅ Threshold-based recommendations (blur/hide/block)
- ✅ Trusted reporter weighting
- ✅ Recent report tracking (last 7 days)
- ✅ Time-based report expiry
- ✅ Local caching

**Thresholds:**
- 1 report: Allow (no action)
- 2-4 reports OR 1 trusted: Blur
- 5+ reports OR 3+ trusted: Hide
- 1+ CSAM reports: Block immediately
- 2+ illegal reports: Block

**Example:**
```dart
await reportService.subscribeToNetworkReports(followsPubkeys);
final aggregation = reportService.getReportsForEvent(eventId);
if (aggregation.recommendation.shouldHide) {
  // Hide content
}
```

### 3. ContentModerationService (NIP-51 kind 10000)
**File:** `lib/services/content_moderation_service.dart` ✅

**Purpose:** Personal mute lists and external mute list subscription

**Features:**
- ✅ Subscribe to external NIP-51 mute lists by pubkey
- ✅ Parse p/e/word/t tags (pubkeys, events, keywords, hashtags)
- ✅ Query embedded relay efficiently
- ✅ Multiple list support with aggregation
- ✅ NostrListServiceMixin integration

**Example:**
```dart
await contentModerationService.subscribeToMuteList('pubkey:curator_hex');
final result = contentModerationService.checkContent(event);
```

### 4. ContentReportingService (NIP-56 kind 1984)
**File:** `lib/services/content_reporting_service.dart` ✅

**Purpose:** Create and broadcast report events to Nostr

**Features:**
- ✅ Create NIP-56 kind 1984 report events
- ✅ Broadcast to Nostr relays (Nostr-first, no backend API)
- ✅ Local report history tracking
- ✅ Support all report types
- ✅ Quick report helpers

## Architecture - Nostr-First Approach 🎯

```
┌─────────────────────────────────────────────────────────┐
│     OpenVine Moderation (100% Nostr, No Backend)       │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Built-in Safety (CSAM detection, illegal)    │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Personal Filters                             │
│           - NIP-51 Mute Lists (kind 10000) ✅           │
│           - Personal blocks/keywords                     │
├─────────────────────────────────────────────────────────┤
│  Layer 3: Subscribed Moderators                        │
│           - NIP-32 Labels (kind 1985) ✅                │
│           - External Mute Lists (kind 10000) ✅         │
├─────────────────────────────────────────────────────────┤
│  Layer 4: Community Reports                            │
│           - NIP-56 Reports (kind 1984) ✅               │
│           - Threshold-based filtering ✅                 │
│           - Trusted reporter weighting ✅                │
└─────────────────────────────────────────────────────────┘

ALL via Embedded Relay + External Nostr Relays
```

### Data Flow

**User Reports Content:**
```
User taps Report → ContentReportingService creates kind 1984
  ↓
Broadcast to Nostr relays (embedded + external)
  ↓
Other users' ReportAggregationService subscribes to reports
  ↓
Aggregates by threshold → Recommends blur/hide/block
  ↓
ModerationFeedService applies recommendation
```

**User Subscribes to Moderator:**
```
User subscribes to moderator → ModerationLabelService subscribes
  ↓
Queries kind 1985 label events from embedded relay
  ↓
Caches labels locally
  ↓
ModerationFeedService checks labels when rendering content
```

## What's Missing 🔨

### CRITICAL: ModerationFeedService (Coordinator)

**The missing piece that ties everything together:**

```dart
class ModerationFeedService {
  final ModerationLabelService _labels;           // NIP-32
  final ReportAggregationService _reports;        // NIP-56
  final ContentModerationService _mutes;          // NIP-51

  /// Unified decision from ALL sources
  Future<ModerationDecision> checkContent(Event event) {
    // 1. Check built-in safety (CSAM, illegal)
    // 2. Check personal mutes (NIP-51)
    // 3. Check subscribed labelers (NIP-32)
    // 4. Check community reports (NIP-56)
    // → Return single unified decision
  }

  ModerationDecision {
    final ModerationAction action; // allow, blur, hide, block
    final List<ModerationSource> sources; // Why was this decision made?
    final double confidence;
  }
}
```

**Why Critical:** Without this, the three services work independently. Need coordinator to combine their decisions into single filtering action.

### Secondary: Integration & UI

1. **ModeratorRegistryService** - Manage trusted labelers/moderators
2. **Update ContentModerationService** - Delegate to ModerationFeedService
3. **UI Components** - Content warnings, moderator browse, settings
4. **Default Moderators** - Bootstrap trusted labelers

## Key Learnings 🧠

### 1. Nostr-First Architecture

**You were right** - OpenVine uses Nostr events, not backend APIs for moderation:
- Reports: kind 1984 Nostr events (not REST API)
- Labels: kind 1985 Nostr events
- Mute Lists: kind 10000 Nostr events

Backend moderation API exists but is **separate** - it's for centralized admin moderation, not the primary user-facing moderation system.

### 2. Embedded Relay is Key

All moderation data flows through embedded relay:
- Fast local queries
- Privacy (no backend knows your subscriptions)
- Offline support
- P2P sync with external relays

### 3. Trust-Based Filtering

OpenVine implements **web of trust** moderation:
- Subscribe to reports from follows (trusted network)
- Subscribe to labels from trusted moderators
- Aggregate consensus from multiple sources
- User controls their moderation stack

### 4. Threshold-Based Decisions

Smart aggregation logic:
- 1-2 reports: Might be noise, just blur
- 3-5 reports: Likely problematic, hide
- 5+ reports: Definitely bad, hide completely
- CSAM/illegal: Immediate block regardless of count
- Trusted reporters count more heavily

## Backend Moderation API (Separate System)

**Note:** The Cloudflare Workers moderation API (`backend/src/handlers/moderation-api.ts`) is **NOT** used by the mobile app for primary moderation.

**What it's for:**
- Admin moderation dashboard
- Centralized abuse reporting for app store compliance
- Analytics/metrics on reports
- Admin actions (manual takedowns)

**Mobile uses:**
- ✅ Nostr kind 1984/1985/10000 events
- ❌ Backend REST API

## Summary

### Done ✅
- NIP-32 Label Service (kind 1985)
- NIP-56 Report Aggregation (kind 1984)
- NIP-51 Mute Lists (kind 10000)
- Report Creation (kind 1984)
- Architecture following Nostr-first principles

### Next Steps 🔨
1. **ModerationFeedService** - Unified coordinator (CRITICAL)
2. **Integration** - Wire up ContentModerationService
3. **ModeratorRegistryService** - Manage subscriptions
4. **UI** - User-facing moderation experience

### Bottom Line

We have **all the building blocks** for Bluesky-style stackable moderation using pure Nostr:
- Labels from trusted moderators ✅
- Reports from trusted network ✅
- Mute lists from curators ✅
- Built-in safety filters ✅

Just need the **coordinator** to combine them into unified filtering decisions!
