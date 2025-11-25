# diVine + Faro - Complete Moderation Architecture

## The Complete System

diVine uses a **three-tier moderation architecture**:

1. **Mobile App (diVine)** - User-facing moderation and filtering
2. **Faro** - Moderator tools for triaging reports and publishing labels
3. **Nostr Network** - Decentralized event distribution

```
┌─────────────────────────────────────────────────────────────┐
│                  Complete Moderation Flow                    │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  User Reports Content                                        │
│         ↓                                                     │
│  diVine creates kind 1984 report event                    │
│         ↓                                                     │
│  Broadcast to Nostr relays                                   │
│         ↓                                                     │
│  ┌─────────────────────────────────┐                        │
│  │  FARO (Moderator Dashboard)     │                        │
│  │  - Moderator sees report         │                        │
│  │  - Reviews content               │                        │
│  │  - Makes decision                │                        │
│  │  - Publishes kind 1985 label    │                        │
│  └─────────────────────────────────┘                        │
│         ↓                                                     │
│  Kind 1985 label broadcast to Nostr                         │
│         ↓                                                     │
│  diVine ModerationLabelService subscribes                 │
│         ↓                                                     │
│  Content automatically filtered in app                       │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Component Roles

### 1. diVine Mobile App (End Users)

**Creates Reports (kind 1984):**
- `ContentReportingService` - User reports problematic content
- Broadcasts to Nostr relays
- Stores locally for history

**Consumes Labels (kind 1985):**
- `ModerationLabelService` - Subscribes to trusted labelers
- `ReportAggregationService` - Aggregates reports from friends
- `ContentModerationService` - Personal mute lists (kind 10000)
- `ModerationFeedService` - Combines all sources into filtering decisions

**User Experience:**
- Users see content warnings/blurs based on labels
- Users can subscribe to trusted moderators (labelers)
- Users can report content with one tap
- Community-driven moderation through friend reports

### 2. Faro (Moderators/Curators)

**Purpose:** Triage reports and publish authoritative labels

**Processes Reports (kind 1984):**
- Moderation queue displays incoming reports
- Moderators review flagged content
- Decision workflow (approve/label/block)
- DMCA/legal compliance workflows

**Publishes Labels (kind 1985):**
- Creates NIP-32 label events
- Signs with moderator keypair
- Broadcasts to Nostr network
- Labels include:
  - Namespace (e.g., `com.openvine.moderation`)
  - Label value (e.g., `nsfw`, `spam`, `violence`)
  - Target (event ID or pubkey)
  - Optional reason/context

**Additional Features:**
- Geoblock management (regional restrictions)
- CDN enforcement integration
- Admin APIs for takedowns
- Audit logging
- DMCA processing

### 3. Nostr Network (Distribution Layer)

**Event Types:**
- **kind 1984** - Reports (user → Faro)
- **kind 1985** - Labels (Faro → users)
- **kind 10000** - Mute lists (users share blocklists)

**Relays:**
- Embedded relay (local, fast queries)
- External relays (distribution, P2P sync)
- Specialized moderation relays

## Data Flow Examples

### Example 1: User Reports NSFW Content

```
1. User in diVine taps "Report" → "NSFW Content"
   ↓
2. ContentReportingService creates kind 1984 event:
   {
     "kind": 1984,
     "tags": [
       ["e", "video_event_id"],
       ["p", "video_author_pubkey"],
       ["report", "nudity"],
       ["P", "faro_moderator_pubkey"]  // Route to Faro
     ],
     "content": "This video contains nudity"
   }
   ↓
3. Broadcast to Nostr relays
   ↓
4. Faro moderator dashboard shows report in queue
   ↓
5. Moderator reviews video → Confirms NSFW
   ↓
6. Faro publishes kind 1985 label:
   {
     "kind": 1985,
     "tags": [
       ["L", "com.openvine.moderation"],
       ["l", "nsfw", "com.openvine.moderation"],
       ["e", "video_event_id"]
     ]
   }
   ↓
7. diVine ModerationLabelService receives label
   ↓
8. Video automatically blurred for all users subscribed to this moderator
```

### Example 2: Threshold-Based Community Filtering

```
1. Multiple users report same spam video
   ↓
2. Each creates kind 1984 report
   ↓
3. ReportAggregationService in other users' apps aggregates:
   - 5 total reports
   - 3 from trusted friends
   ↓
4. Threshold exceeded (3+ trusted reports)
   ↓
5. Content automatically hidden for users who trust these reporters
   ↓
6. Meanwhile, Faro moderator also sees reports
   ↓
7. Moderator confirms spam, publishes kind 1985 label
   ↓
8. Label provides additional authoritative signal
```

### Example 3: User Subscribes to Curator's Mute List

```
1. User discovers "Tech Content Curator" moderator
   ↓
2. User subscribes to curator's NIP-51 mute list
   ↓
3. ContentModerationService queries curator's kind 10000 events
   ↓
4. Curator has muted 50 spam accounts
   ↓
5. All 50 accounts automatically muted in user's feed
```

## diVine Services (Current State)

### ✅ Implemented

1. **ModerationLabelService** - Subscribes to Faro's kind 1985 labels
2. **ReportAggregationService** - Aggregates community kind 1984 reports
3. **ContentModerationService** - Personal + external NIP-51 mute lists
4. **ContentReportingService** - Creates kind 1984 reports → Faro

### 🔨 Missing

1. **ModerationFeedService** - Coordinator combining all sources
2. **ModeratorRegistryService** - Manage trusted moderators/Faro instances
3. **Integration** - Wire services into ContentModerationService
4. **UI** - Subscribe to moderators, content warnings, report flows

## Faro Integration Points

### How diVine Integrates with Faro

**1. Report Routing (kind 1984 → Faro)**

diVine can tag reports to route to specific Faro instances:
```dart
// In ContentReportingService
tags.add(['P', faroModeratorPubkey]); // Route to Faro moderator
```

**2. Label Subscription (Faro → diVine)**

diVine subscribes to labels from trusted Faro moderators:
```dart
// In ModerationLabelService
await service.subscribeToLabeler(faroModeratorPubkey);
```

**3. Multiple Faro Instances**

Users can subscribe to multiple Faro moderators:
- diVine official safety team
- Community-run Faro instances
- Niche moderators (tech, art, news, etc)
- Up to 20 labelers (Bluesky pattern)

### Faro Configuration in diVine

```dart
// Default Faro moderators
final defaultModerators = [
  ModeratorProfile(
    pubkey: 'openvine_faro_pubkey',
    displayName: 'diVine Safety',
    faroUrl: 'https://faro.openvine.co',
    description: 'Official diVine content safety team',
    specialties: ['csam', 'illegal', 'violence'],
  ),
  ModeratorProfile(
    pubkey: 'community_faro_pubkey',
    displayName: 'Community Moderators',
    faroUrl: 'https://faro.nos.social',
    description: 'Community-run moderation',
    specialties: ['spam', 'harassment'],
  ),
];
```

## Trust & Safety Workflow

### For Regular Users (diVine)

1. **Report problematic content** - One tap, kind 1984 created
2. **Subscribe to moderators** - Choose trusted Faro instances
3. **See filtered content** - Automatic based on labels + reports
4. **Trust friends' reports** - Community threshold filtering
5. **Maintain personal mute list** - NIP-51 blocklists

### For Moderators (Faro)

1. **Receive reports** - Queue of kind 1984 events
2. **Review content** - Video playback, context, reporter history
3. **Make decision** - Label, ignore, escalate
4. **Publish labels** - Kind 1985 to Nostr network
5. **Manage rules** - Geoblocks, takedowns, policy enforcement
6. **Audit trail** - All actions logged

## Decentralization Benefits

**No Single Authority:**
- Users choose which Faro instances to trust
- Multiple independent Faro moderators
- No central censorship point
- Transparent moderation decisions

**User Sovereignty:**
- Subscribe/unsubscribe from any moderator
- Combine multiple moderation sources
- Personal overrides (always allow/block)
- See why content was filtered

**Moderator Competition:**
- Multiple Faro instances compete on quality
- Users vote with subscriptions
- Specialized moderators emerge (tech, art, news)
- Reputation-based trust

## Implementation Status

### diVine Mobile

| Component | Status | Description |
|-----------|--------|-------------|
| Report Creation | ✅ | ContentReportingService creates kind 1984 |
| Label Subscription | ✅ | ModerationLabelService subscribes to kind 1985 |
| Report Aggregation | ✅ | ReportAggregationService aggregates kind 1984 |
| Mute Lists | ✅ | ContentModerationService handles kind 10000 |
| Feed Coordinator | 🔨 | ModerationFeedService - combines all sources |
| Moderator Registry | 🔨 | ModeratorRegistryService - manage Faro subs |
| UI Components | 🔨 | Content warnings, moderator browse |

### Faro

| Component | Status | Notes |
|-----------|--------|-------|
| Report Queue | ✅ | External system (rabble/faro) |
| Label Publisher | ✅ | Creates kind 1985 events |
| Geoblock Manager | ✅ | Regional restrictions |
| DMCA Processing | ✅ | Legal compliance |
| Admin APIs | ✅ | Takedown management |

## Next Steps for diVine

### 1. ModerationFeedService (CRITICAL)

Implement coordinator that combines:
- Labels from Faro (kind 1985)
- Community reports (kind 1984)
- Mute lists (kind 10000)
- Built-in safety filters

### 2. Faro Integration

- Add Faro moderator discovery
- Configure default diVine Faro instance
- Route reports to Faro with `P` tag
- Subscribe to Faro labels automatically

### 3. ModeratorRegistryService

- Manage multiple Faro subscriptions
- Track moderator reputation
- Display moderator policies/stats
- Handle up to 20 subscriptions

### 4. UI Components

- "Subscribe to Moderator" button
- Content warning overlays
- Report flow with Faro routing
- Moderation settings screen
- "Why was this filtered?" explanation

## Architecture Advantages

**Three-Tier Design:**
1. **Users** (diVine) - Simple, one-tap reporting
2. **Moderators** (Faro) - Professional triage and labeling
3. **Network** (Nostr) - Decentralized distribution

**Benefits:**
- Users don't need moderation expertise
- Professional moderators use specialized tools
- No central bottleneck
- Transparent and auditable
- User choice and control

**Compared to Centralized:**
- Traditional: Reports → Backend → Admins → Decision
- diVine + Faro: Reports → Nostr → Multiple Faro Instances → Labels → Users choose which to trust

## Summary

**Faro is the professional moderator interface** for triaging kind 1984 reports and publishing authoritative kind 1985 labels.

**diVine is the end-user interface** that creates reports, subscribes to labels, and filters content.

Together they form a **decentralized, multi-stakeholder moderation system** where:
- Users report easily
- Moderators triage professionally
- Labels distribute via Nostr
- Users choose which moderators to trust
- No single point of control

The missing piece in diVine is the **ModerationFeedService** coordinator that ties these systems together into a unified user experience.
