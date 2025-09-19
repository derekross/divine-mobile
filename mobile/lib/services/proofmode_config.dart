// ABOUTME: ProofMode configuration service managing feature flags and settings
// ABOUTME: Controls progressive rollout of ProofMode functionality phases

import 'package:openvine/services/feature_flag_service.dart';
import 'package:openvine/utils/unified_logger.dart';

/// ProofMode configuration and feature flag management
class ProofModeConfig {
  static FeatureFlagService? _featureFlagService;

  /// Initialize with feature flag service
  static void initialize(FeatureFlagService service) {
    _featureFlagService = service;
    Log.info('ProofModeConfig initialized',
        name: 'ProofModeConfig', category: LogCategory.system);
  }

  /// Check if ProofMode is enabled for development/testing
  static Future<bool> get isDevelopmentEnabled async {
    if (_featureFlagService == null) {
      Log.warning('ProofModeConfig not initialized, defaulting to false',
          name: 'ProofModeConfig', category: LogCategory.system);
      return false;
    }

    final enabled = await _featureFlagService!.isEnabled('proofmode_dev');
    Log.debug('ProofMode development enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if crypto key generation is enabled
  static Future<bool> get isCryptoEnabled async {
    if (_featureFlagService == null) return false;

    final enabled = await _featureFlagService!.isEnabled('proofmode_crypto');
    Log.debug('ProofMode crypto enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if proof generation during capture is enabled
  static Future<bool> get isCaptureEnabled async {
    if (_featureFlagService == null) return false;

    final enabled = await _featureFlagService!.isEnabled('proofmode_capture');
    Log.debug('ProofMode capture enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if proof data publishing to Nostr is enabled
  static Future<bool> get isPublishEnabled async {
    if (_featureFlagService == null) return false;

    final enabled = await _featureFlagService!.isEnabled('proofmode_publish');
    Log.debug('ProofMode publish enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if verification services are enabled
  static Future<bool> get isVerifyEnabled async {
    if (_featureFlagService == null) return false;

    final enabled = await _featureFlagService!.isEnabled('proofmode_verify');
    Log.debug('ProofMode verify enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if UI verification badges are enabled
  static Future<bool> get isUIEnabled async {
    if (_featureFlagService == null) return false;

    final enabled = await _featureFlagService!.isEnabled('proofmode_ui');
    Log.debug('ProofMode UI enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if full production ProofMode is enabled
  static Future<bool> get isProductionEnabled async {
    if (_featureFlagService == null) return false;

    final enabled =
        await _featureFlagService!.isEnabled('proofmode_production');
    Log.debug('ProofMode production enabled: $enabled',
        name: 'ProofModeConfig', category: LogCategory.system);
    return enabled;
  }

  /// Check if any ProofMode functionality is enabled
  static Future<bool> get isAnyEnabled async {
    return await isDevelopmentEnabled ||
        await isCryptoEnabled ||
        await isCaptureEnabled ||
        await isPublishEnabled ||
        await isVerifyEnabled ||
        await isUIEnabled ||
        await isProductionEnabled;
  }

  /// Get current ProofMode capabilities as a map
  static Future<Map<String, bool>> getCapabilities() async {
    final capabilities = {
      'development': await isDevelopmentEnabled,
      'crypto': await isCryptoEnabled,
      'capture': await isCaptureEnabled,
      'publish': await isPublishEnabled,
      'verify': await isVerifyEnabled,
      'ui': await isUIEnabled,
      'production': await isProductionEnabled,
    };

    Log.debug('ProofMode capabilities: $capabilities',
        name: 'ProofModeConfig', category: LogCategory.system);

    return capabilities;
  }

  /// Log current ProofMode status
  static Future<void> logStatus() async {
    final capabilities = await getCapabilities();
    final enabledFeatures = capabilities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (enabledFeatures.isEmpty) {
      Log.info('ProofMode: All features disabled',
          name: 'ProofModeConfig', category: LogCategory.system);
    } else {
      Log.info('ProofMode: Enabled features: ${enabledFeatures.join(", ")}',
          name: 'ProofModeConfig', category: LogCategory.system);
    }
  }
}
