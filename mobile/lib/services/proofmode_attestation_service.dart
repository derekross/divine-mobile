// ABOUTME: ProofMode device attestation service for iOS App Attest and Android Play Integrity
// ABOUTME: Provides hardware-backed device verification without user permission prompts

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:openvine/services/proofmode_config.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Device attestation result
class DeviceAttestation {
  const DeviceAttestation({
    required this.token,
    required this.platform,
    required this.deviceId,
    required this.isHardwareBacked,
    required this.createdAt,
    this.challenge,
    this.metadata,
  });

  final String token;
  final String platform;
  final String deviceId;
  final bool isHardwareBacked;
  final DateTime createdAt;
  final String? challenge;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
        'token': token,
        'platform': platform,
        'deviceId': deviceId,
        'isHardwareBacked': isHardwareBacked,
        'createdAt': createdAt.toIso8601String(),
        'challenge': challenge,
        'metadata': metadata,
      };

  factory DeviceAttestation.fromJson(Map<String, dynamic> json) =>
      DeviceAttestation(
        token: json['token'] as String,
        platform: json['platform'] as String,
        deviceId: json['deviceId'] as String,
        isHardwareBacked: json['isHardwareBacked'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
        challenge: json['challenge'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

/// Device information for attestation
class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    required this.model,
    required this.version,
    required this.deviceId,
    this.manufacturer,
    this.isPhysicalDevice,
    this.metadata,
  });

  final String platform;
  final String model;
  final String version;
  final String deviceId;
  final String? manufacturer;
  final bool? isPhysicalDevice;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'model': model,
        'version': version,
        'deviceId': deviceId,
        'manufacturer': manufacturer,
        'isPhysicalDevice': isPhysicalDevice,
        'metadata': metadata,
      };
}

/// ProofMode device attestation service
class ProofModeAttestationService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  DeviceInfo? _cachedDeviceInfo;

  /// Initialize the attestation service
  Future<void> initialize() async {
    Log.info('Initializing ProofMode attestation service',
        name: 'ProofModeAttestationService', category: LogCategory.auth);

    if (!await ProofModeConfig.isCryptoEnabled) {
      Log.info('ProofMode crypto disabled, skipping attestation initialization',
          name: 'ProofModeAttestationService', category: LogCategory.auth);
      return;
    }

    try {
      // Cache device info
      _cachedDeviceInfo = await _getDeviceInfo();
      Log.info(
          'Device attestation initialized for ${_cachedDeviceInfo?.platform} ${_cachedDeviceInfo?.model}',
          name: 'ProofModeAttestationService',
          category: LogCategory.auth);
    } catch (e) {
      Log.error('Failed to initialize device attestation: $e',
          name: 'ProofModeAttestationService', category: LogCategory.auth);
    }
  }

  /// Generate device attestation for a challenge
  Future<DeviceAttestation?> generateAttestation(String challenge) async {
    if (!await ProofModeConfig.isCryptoEnabled) {
      Log.debug('ProofMode crypto disabled, skipping attestation generation',
          name: 'ProofModeAttestationService', category: LogCategory.auth);
      return null;
    }

    Log.info(
        'Generating device attestation for challenge: ${challenge.substring(0, 8)}...',
        name: 'ProofModeAttestationService',
        category: LogCategory.auth);

    try {
      final deviceInfo = _cachedDeviceInfo ?? await _getDeviceInfo();

      if (Platform.isIOS) {
        return await _generateiOSAttestation(challenge, deviceInfo);
      } else if (Platform.isAndroid) {
        return await _generateAndroidAttestation(challenge, deviceInfo);
      } else {
        return await _generateFallbackAttestation(challenge, deviceInfo);
      }
    } catch (e) {
      Log.error('Failed to generate device attestation: $e',
          name: 'ProofModeAttestationService', category: LogCategory.auth);
      return null;
    }
  }

  /// Get device information
  Future<DeviceInfo> getDeviceInfo() async {
    return _cachedDeviceInfo ?? await _getDeviceInfo();
  }

  /// Check if hardware-backed attestation is available
  Future<bool> isHardwareAttestationAvailable() async {
    try {
      if (Platform.isIOS) {
        // iOS 14+ with compatible hardware supports App Attest
        final info = await _deviceInfo.iosInfo;
        final version = info.systemVersion;
        final majorVersion = int.tryParse(version.split('.').first) ?? 0;
        return majorVersion >= 14;
      } else if (Platform.isAndroid) {
        // Most Android devices with Play Services support Play Integrity
        final info = await _deviceInfo.androidInfo;
        return info.isPhysicalDevice;
      }
      return false;
    } catch (e) {
      Log.error('Failed to check hardware attestation availability: $e',
          name: 'ProofModeAttestationService', category: LogCategory.auth);
      return false;
    }
  }

  /// Verify an attestation token (basic validation)
  Future<bool> verifyAttestation(
      DeviceAttestation attestation, String originalChallenge) async {
    try {
      // Basic validation
      if (attestation.challenge != originalChallenge) {
        Log.warning('Attestation challenge mismatch',
            name: 'ProofModeAttestationService', category: LogCategory.auth);
        return false;
      }

      // Check if token is recent (within 1 hour)
      final age = DateTime.now().difference(attestation.createdAt);
      if (age.inHours > 1) {
        Log.warning('Attestation token too old: ${age.inMinutes} minutes',
            name: 'ProofModeAttestationService', category: LogCategory.auth);
        return false;
      }

      // Platform-specific validation would go here
      // For now, just check if token looks valid
      final isValid = attestation.token.isNotEmpty &&
          attestation.deviceId.isNotEmpty &&
          attestation.platform.isNotEmpty;

      Log.debug('Attestation verification result: $isValid',
          name: 'ProofModeAttestationService', category: LogCategory.auth);

      return isValid;
    } catch (e) {
      Log.error('Failed to verify attestation: $e',
          name: 'ProofModeAttestationService', category: LogCategory.auth);
      return false;
    }
  }

  // Private helper methods

  /// Get device information
  Future<DeviceInfo> _getDeviceInfo() async {
    if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return DeviceInfo(
        platform: 'iOS',
        model: info.model,
        version: info.systemVersion,
        deviceId: info.identifierForVendor ?? 'unknown',
        manufacturer: 'Apple',
        isPhysicalDevice: info.isPhysicalDevice,
        metadata: {
          'name': info.name,
          'systemName': info.systemName,
          'utsname': info.utsname.machine,
        },
      );
    } else if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return DeviceInfo(
        platform: 'Android',
        model: info.model,
        version: info.version.release,
        deviceId: info.id,
        manufacturer: info.manufacturer,
        isPhysicalDevice: info.isPhysicalDevice,
        metadata: {
          'brand': info.brand,
          'device': info.device,
          'product': info.product,
          'androidId': info.id,
          'sdkInt': info.version.sdkInt,
        },
      );
    } else {
      // Web or other platforms
      return DeviceInfo(
        platform: Platform.operatingSystem,
        model: 'unknown',
        version: Platform.operatingSystemVersion,
        deviceId: 'web-${DateTime.now().millisecondsSinceEpoch}',
        isPhysicalDevice: false,
        metadata: {
          'userAgent': Platform.isAndroid ? 'Android' : 'Other',
        },
      );
    }
  }

  /// Generate iOS App Attest attestation
  Future<DeviceAttestation> _generateiOSAttestation(
      String challenge, DeviceInfo deviceInfo) async {
    Log.info('Generating iOS App Attest attestation',
        name: 'ProofModeAttestationService', category: LogCategory.auth);

    // TODO: Implement actual iOS App Attest API integration
    // For now, generate a mock attestation

    final attestationData = {
      'challenge': challenge,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'deviceInfo': deviceInfo.toJson(),
      'attestationType': 'app_attest',
    };

    final token = _generateMockToken('ios_app_attest', attestationData);

    return DeviceAttestation(
      token: token,
      platform: 'iOS',
      deviceId: deviceInfo.deviceId,
      isHardwareBacked: true,
      createdAt: DateTime.now(),
      challenge: challenge,
      metadata: {
        'attestationType': 'app_attest',
        'deviceInfo': deviceInfo.toJson(),
      },
    );
  }

  /// Generate Android Play Integrity attestation
  Future<DeviceAttestation> _generateAndroidAttestation(
      String challenge, DeviceInfo deviceInfo) async {
    Log.info('Generating Android Play Integrity attestation',
        name: 'ProofModeAttestationService', category: LogCategory.auth);

    // TODO: Implement actual Play Integrity API integration
    // For now, generate a mock attestation

    final attestationData = {
      'challenge': challenge,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'deviceInfo': deviceInfo.toJson(),
      'attestationType': 'play_integrity',
    };

    final token = _generateMockToken('android_play_integrity', attestationData);

    return DeviceAttestation(
      token: token,
      platform: 'Android',
      deviceId: deviceInfo.deviceId,
      isHardwareBacked: deviceInfo.isPhysicalDevice ?? false,
      createdAt: DateTime.now(),
      challenge: challenge,
      metadata: {
        'attestationType': 'play_integrity',
        'deviceInfo': deviceInfo.toJson(),
      },
    );
  }

  /// Generate fallback attestation for unsupported platforms
  Future<DeviceAttestation> _generateFallbackAttestation(
      String challenge, DeviceInfo deviceInfo) async {
    Log.info('Generating fallback attestation for ${deviceInfo.platform}',
        name: 'ProofModeAttestationService', category: LogCategory.auth);

    final attestationData = {
      'challenge': challenge,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'deviceInfo': deviceInfo.toJson(),
      'attestationType': 'fallback',
    };

    final token = _generateMockToken('fallback', attestationData);

    return DeviceAttestation(
      token: token,
      platform: deviceInfo.platform,
      deviceId: deviceInfo.deviceId,
      isHardwareBacked: false,
      createdAt: DateTime.now(),
      challenge: challenge,
      metadata: {
        'attestationType': 'fallback',
        'deviceInfo': deviceInfo.toJson(),
      },
    );
  }

  /// Generate a mock attestation token (placeholder for real implementation)
  String _generateMockToken(String type, Map<String, dynamic> data) {
    final payload = {
      'type': type,
      'data': data,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    final payloadBytes = utf8.encode(jsonEncode(payload));
    final hash = sha256.convert(payloadBytes);

    return 'MOCK_ATTESTATION_${type.toUpperCase()}_${base64Encode(hash.bytes)}';
  }
}
