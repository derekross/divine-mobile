// ABOUTME: Content moderation service with NIP-51 mute list support
// ABOUTME: Manages client-side content filtering while respecting decentralized principles

import 'dart:convert';

import 'package:nostr_sdk/event.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reasons for content filtering/reporting
enum ContentFilterReason {
  spam('Spam or unwanted content'),
  harassment('Harassment or bullying'),
  violence('Violence or threats'),
  sexualContent('Sexual or adult content'),
  copyright('Copyright violation'),
  falseInformation('Misinformation'),
  csam('Child safety concern'),
  other('Other violation');

  const ContentFilterReason(this.description);
  final String description;
}

/// Content severity levels for filtering
enum ContentSeverity {
  info, // Informational only
  warning, // Show warning but allow viewing
  hide, // Hide by default, show if requested
  block // Completely block content
}

/// Mute list entry representing filtered content
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class MuteListEntry {
  const MuteListEntry({
    required this.type,
    required this.value,
    required this.reason,
    required this.severity,
    required this.createdAt,
    this.note,
  });
  final String type; // 'pubkey', 'event', 'keyword', 'content-type'
  final String value;
  final ContentFilterReason reason;
  final ContentSeverity severity;
  final DateTime createdAt;
  final String? note;

  Map<String, dynamic> toJson() => {
        'type': type,
        'value': value,
        'reason': reason.name,
        'severity': severity.name,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
      };

  static MuteListEntry fromJson(Map<String, dynamic> json) => MuteListEntry(
        type: json['type'],
        value: json['value'],
        reason: ContentFilterReason.values.firstWhere(
          (r) => r.name == json['reason'],
          orElse: () => ContentFilterReason.other,
        ),
        severity: ContentSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => ContentSeverity.hide,
        ),
        createdAt: DateTime.parse(json['createdAt']),
        note: json['note'],
      );

  /// Convert to NIP-51 list entry tag format
  List<String> toNIP51Tag() {
    final tag = [type, value];
    if (note != null) tag.add(note!);
    return tag;
  }
}

/// Content moderation result
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class ModerationResult {
  const ModerationResult({
    required this.shouldFilter,
    required this.severity,
    required this.reasons,
    required this.matchingEntries,
    this.warningMessage,
  });
  final bool shouldFilter;
  final ContentSeverity severity;
  final List<ContentFilterReason> reasons;
  final String? warningMessage;
  final List<MuteListEntry> matchingEntries;

  static const ModerationResult clean = ModerationResult(
    shouldFilter: false,
    severity: ContentSeverity.info,
    reasons: [],
    matchingEntries: [],
  );
}

/// Content moderation service managing mute lists and filtering
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class ContentModerationService {
  ContentModerationService({
    required SharedPreferences prefs,
  }) : _prefs = prefs {
    _loadSettings();
    _loadLocalMuteList();
    _loadSubscribedLists();
  }
  final SharedPreferences _prefs;

  // Default divine moderation list
  static const String defaultMuteListId = 'openvine-default-mutes-v1';
  static const String defaultMuteListPubkey =
      'npub1openvinemoderation'; // Placeholder

  // Local storage keys
  static const String _localMuteListKey = 'content_moderation_local_mutes';
  static const String _subscribedListsKey =
      'content_moderation_subscribed_lists';
  static const String _settingsKey = 'content_moderation_settings';

  // Mute lists
  final Map<String, List<MuteListEntry>> _muteLists = {};
  List<String> _subscribedLists = [];

  // Settings
  bool _enableDefaultModeration = true;
  bool _enableCustomMuteLists = true;
  bool _showContentWarnings = true;
  ContentSeverity _autoHideLevel = ContentSeverity.hide;

  // Getters
  bool get enableDefaultModeration => _enableDefaultModeration;
  bool get enableCustomMuteLists => _enableCustomMuteLists;
  bool get showContentWarnings => _showContentWarnings;
  ContentSeverity get autoHideLevel => _autoHideLevel;
  List<String> get subscribedLists => List.unmodifiable(_subscribedLists);

  /// Initialize content moderation
  Future<void> initialize() async {
    try {
      // Subscribe to default divine moderation list
      if (_enableDefaultModeration) {
        await _subscribeToDefaultList();
      }

      // Subscribe to user's custom mute lists
      if (_enableCustomMuteLists) {
        for (final listId in _subscribedLists) {
          await _subscribeToMuteList(listId);
        }
      }

      Log.info('Content moderation initialized with ${_muteLists.length} lists',
          name: 'ContentModerationService', category: LogCategory.system);
    } catch (e) {
      Log.error('Failed to initialize content moderation: $e',
          name: 'ContentModerationService', category: LogCategory.system);
    }
  }

  /// Check if content should be filtered
  ModerationResult checkContent(Event event) {
    if (!_enableDefaultModeration && !_enableCustomMuteLists) {
      return ModerationResult.clean;
    }

    final matchingEntries = <MuteListEntry>[];
    final reasons = <ContentFilterReason>{};
    var maxSeverity = ContentSeverity.info;

    // Check against all active mute lists
    for (final entries in _muteLists.values) {
      for (final entry in entries) {
        if (_doesEntryMatch(entry, event)) {
          matchingEntries.add(entry);
          reasons.add(entry.reason);
          if (entry.severity.index > maxSeverity.index) {
            maxSeverity = entry.severity;
          }
        }
      }
    }

    final shouldFilter =
        matchingEntries.isNotEmpty && maxSeverity.index >= _autoHideLevel.index;

    String? warningMessage;
    if (matchingEntries.isNotEmpty) {
      final primaryReason = reasons.first;
      warningMessage =
          _buildWarningMessage(primaryReason, matchingEntries.length);
    }

    return ModerationResult(
      shouldFilter: shouldFilter,
      severity: maxSeverity,
      reasons: reasons.toList(),
      warningMessage: warningMessage,
      matchingEntries: matchingEntries,
    );
  }

  /// Add entry to local mute list
  Future<void> addToMuteList({
    required String type,
    required String value,
    required ContentFilterReason reason,
    ContentSeverity severity = ContentSeverity.hide,
    String? note,
  }) async {
    final entry = MuteListEntry(
      type: type,
      value: value,
      reason: reason,
      severity: severity,
      createdAt: DateTime.now(),
      note: note,
    );

    // Add to local list
    final localList = _muteLists['local'] ?? [];
    localList.add(entry);
    _muteLists['local'] = localList;

    await _saveLocalMuteList();

    Log.debug('Added to mute list: $type:$value (${reason.name})',
        name: 'ContentModerationService', category: LogCategory.system);
  }

  /// Remove entry from local mute list
  Future<void> removeFromMuteList(String type, String value) async {
    final localList = _muteLists['local'];
    if (localList != null) {
      localList.removeWhere(
        (entry) => entry.type == type && entry.value == value,
      );
      await _saveLocalMuteList();
    }
  }

  /// Block a user (add pubkey to mute list)
  Future<void> blockUser(String pubkey, {String? reason}) async {
    await addToMuteList(
      type: 'pubkey',
      value: pubkey,
      reason: ContentFilterReason.harassment,
      severity: ContentSeverity.block,
      note: reason,
    );
  }

  /// Mute a keyword
  Future<void> muteKeyword(String keyword, ContentSeverity severity) async {
    await addToMuteList(
      type: 'keyword',
      value: keyword.toLowerCase(),
      reason: ContentFilterReason.spam,
      severity: severity,
    );
  }

  /// Subscribe to external mute list
  Future<void> subscribeToMuteList(String listId) async {
    if (_subscribedLists.contains(listId)) return;

    try {
      _subscribedLists.add(listId);
      await _subscribeToMuteList(listId);
      await _saveSubscribedLists();

      Log.verbose('Subscribed to mute list: $listId',
          name: 'ContentModerationService', category: LogCategory.system);
    } catch (e) {
      _subscribedLists.remove(listId);
      Log.error('Failed to subscribe to mute list $listId: $e',
          name: 'ContentModerationService', category: LogCategory.system);
      rethrow;
    }
  }

  /// Unsubscribe from mute list
  Future<void> unsubscribeFromMuteList(String listId) async {
    _subscribedLists.remove(listId);
    _muteLists.remove(listId);
    await _saveSubscribedLists();
  }

  /// Update moderation settings
  Future<void> updateSettings({
    bool? enableDefaultModeration,
    bool? enableCustomMuteLists,
    bool? showContentWarnings,
    ContentSeverity? autoHideLevel,
  }) async {
    _enableDefaultModeration =
        enableDefaultModeration ?? _enableDefaultModeration;
    _enableCustomMuteLists = enableCustomMuteLists ?? _enableCustomMuteLists;
    _showContentWarnings = showContentWarnings ?? _showContentWarnings;
    _autoHideLevel = autoHideLevel ?? _autoHideLevel;

    await _saveSettings();
  }

  /// Get moderation statistics
  Map<String, dynamic> getModerationStats() {
    var totalEntries = 0;
    var pubkeyBlocks = 0;
    var keywordMutes = 0;

    for (final entries in _muteLists.values) {
      totalEntries += entries.length;
      pubkeyBlocks += entries.where((e) => e.type == 'pubkey').length;
      keywordMutes += entries.where((e) => e.type == 'keyword').length;
    }

    return {
      'totalMuteLists': _muteLists.length,
      'totalEntries': totalEntries,
      'pubkeyBlocks': pubkeyBlocks,
      'keywordMutes': keywordMutes,
      'subscribedLists': _subscribedLists.length,
    };
  }

  /// Subscribe to default divine moderation list
  Future<void> _subscribeToDefaultList() async {
    try {
      // This would subscribe to official divine moderation list
      // For now, create a basic default list
      final defaultEntries = [
        MuteListEntry(
          type: 'keyword',
          value: 'spam',
          reason: ContentFilterReason.spam,
          severity: ContentSeverity.hide,
          createdAt: DateTime.now(),
          note: 'Default spam filtering',
        ),
        MuteListEntry(
          type: 'keyword',
          value: 'nsfw',
          reason: ContentFilterReason.sexualContent,
          severity: ContentSeverity.warning,
          createdAt: DateTime.now(),
          note: 'Adult content warning',
        ),
      ];

      _muteLists['default'] = defaultEntries;
      Log.debug('Loaded default moderation list',
          name: 'ContentModerationService', category: LogCategory.system);
    } catch (e) {
      Log.error('Failed to load default moderation list: $e',
          name: 'ContentModerationService', category: LogCategory.system);
    }
  }

  /// Subscribe to external mute list via Nostr
  Future<void> _subscribeToMuteList(String listId) async {
    try {
      // TODO: Implement NIP-51 list subscription
      // This would fetch the mute list from Nostr and parse entries
      Log.debug('Subscribing to mute list: $listId',
          name: 'ContentModerationService', category: LogCategory.system);

      // Placeholder implementation
      _muteLists[listId] = [];
    } catch (e) {
      Log.error('Failed to subscribe to mute list $listId: $e',
          name: 'ContentModerationService', category: LogCategory.system);
      rethrow;
    }
  }

  /// Check if mute list entry matches event
  bool _doesEntryMatch(MuteListEntry entry, Event event) {
    switch (entry.type) {
      case 'pubkey':
        return event.pubkey == entry.value;
      case 'event':
        return event.id == entry.value;
      case 'keyword':
        return event.content.toLowerCase().contains(entry.value);
      case 'content-type':
        // Check event tags for content type indicators
        return event.tags.any(
          (tag) =>
              tag.length > 1 && tag[0] == 'm' && tag[1].startsWith(entry.value),
        );
      default:
        return false;
    }
  }

  /// Build warning message for filtered content
  String _buildWarningMessage(ContentFilterReason reason, int matchCount) {
    final String baseMessage;
    switch (reason) {
      case ContentFilterReason.spam:
        baseMessage = 'This content may be spam';
      case ContentFilterReason.harassment:
        baseMessage = 'This content may contain harassment';
      case ContentFilterReason.violence:
        baseMessage = 'This content may contain violence';
      case ContentFilterReason.sexualContent:
        baseMessage = 'This content may be sensitive';
      case ContentFilterReason.copyright:
        baseMessage = 'This content may violate copyright';
      case ContentFilterReason.falseInformation:
        baseMessage = 'This content may contain misinformation';
      case ContentFilterReason.csam:
        baseMessage = 'This content violates child safety policies';
      case ContentFilterReason.other:
        baseMessage = 'This content may violate community guidelines';
    }

    if (matchCount > 1) {
      return '$baseMessage (matched $matchCount filters)';
    }
    return baseMessage;
  }

  /// Load settings from storage
  void _loadSettings() {
    final settingsJson = _prefs.getString(_settingsKey);
    if (settingsJson != null) {
      try {
        final settings = jsonDecode(settingsJson) as Map<String, dynamic>;
        _enableDefaultModeration = settings['enableDefaultModeration'] ?? true;
        _enableCustomMuteLists = settings['enableCustomMuteLists'] ?? true;
        _showContentWarnings = settings['showContentWarnings'] ?? true;
        _autoHideLevel = ContentSeverity.values.firstWhere(
          (s) => s.name == settings['autoHideLevel'],
          orElse: () => ContentSeverity.hide,
        );
      } catch (e) {
        Log.error('Failed to load moderation settings: $e',
            name: 'ContentModerationService', category: LogCategory.system);
      }
    }
  }

  /// Save settings to storage
  Future<void> _saveSettings() async {
    final settings = {
      'enableDefaultModeration': _enableDefaultModeration,
      'enableCustomMuteLists': _enableCustomMuteLists,
      'showContentWarnings': _showContentWarnings,
      'autoHideLevel': _autoHideLevel.name,
    };
    await _prefs.setString(_settingsKey, jsonEncode(settings));
  }

  /// Load local mute list from storage
  void _loadLocalMuteList() {
    final muteListJson = _prefs.getString(_localMuteListKey);
    if (muteListJson != null) {
      try {
        final List<dynamic> entriesJson = jsonDecode(muteListJson);
        final entries = entriesJson
            .map((json) => MuteListEntry.fromJson(json as Map<String, dynamic>))
            .toList();
        _muteLists['local'] = entries;
      } catch (e) {
        Log.error('Failed to load local mute list: $e',
            name: 'ContentModerationService', category: LogCategory.system);
      }
    }
  }

  /// Save local mute list to storage
  Future<void> _saveLocalMuteList() async {
    final localList = _muteLists['local'] ?? [];
    final entriesJson = localList.map((entry) => entry.toJson()).toList();
    await _prefs.setString(_localMuteListKey, jsonEncode(entriesJson));
  }

  /// Load subscribed lists from storage
  void _loadSubscribedLists() {
    final listsJson = _prefs.getString(_subscribedListsKey);
    if (listsJson != null) {
      try {
        _subscribedLists = List<String>.from(jsonDecode(listsJson));
      } catch (e) {
        Log.error('Failed to load subscribed lists: $e',
            name: 'ContentModerationService', category: LogCategory.system);
      }
    }
  }

  /// Save subscribed lists to storage
  Future<void> _saveSubscribedLists() async {
    await _prefs.setString(_subscribedListsKey, jsonEncode(_subscribedLists));
  }

  void dispose() {
    // Clean up any active subscriptions
  }
}
