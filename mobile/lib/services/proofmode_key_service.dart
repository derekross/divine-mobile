// ABOUTME: ProofMode PGP key management service for device-specific cryptographic operations
// ABOUTME: Handles secure key generation, storage, and signing for proof validation

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openvine/services/proofmode_config.dart';
import 'package:openvine/utils/unified_logger.dart';

/// PGP key pair information
class ProofModeKeyPair {
  const ProofModeKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.fingerprint,
    required this.createdAt,
  });

  final String publicKey;
  final String privateKey;
  final String fingerprint;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        'privateKey': privateKey,
        'fingerprint': fingerprint,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ProofModeKeyPair.fromJson(Map<String, dynamic> json) =>
      ProofModeKeyPair(
        publicKey: json['publicKey'] as String,
        privateKey: json['privateKey'] as String,
        fingerprint: json['fingerprint'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Proof signature result
class ProofSignature {
  const ProofSignature({
    required this.signature,
    required this.publicKeyFingerprint,
    required this.signedAt,
  });

  final String signature;
  final String publicKeyFingerprint;
  final DateTime signedAt;

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'publicKeyFingerprint': publicKeyFingerprint,
        'signedAt': signedAt.toIso8601String(),
      };

  factory ProofSignature.fromJson(Map<String, dynamic> json) => ProofSignature(
        signature: json['signature'] as String,
        publicKeyFingerprint: json['publicKeyFingerprint'] as String,
        signedAt: DateTime.parse(json['signedAt'] as String),
      );
}

/// ProofMode PGP key management service
class ProofModeKeyService {
  static const String _keyPrefix = 'proofmode_key_';
  static const String _publicKeyKey = '${_keyPrefix}public';
  static const String _privateKeyKey = '${_keyPrefix}private';
  static const String _fingerprintKey = '${_keyPrefix}fingerprint';
  static const String _createdAtKey = '${_keyPrefix}created_at';

  static const FlutterSecureStorage _defaultSecureStorage =
      FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _secureStorage;
  ProofModeKeyPair? _cachedKeyPair;

  /// Create ProofModeKeyService with optional storage (for testing)
  ProofModeKeyService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? _defaultSecureStorage;

  /// Initialize the key service and generate keys if needed
  Future<void> initialize() async {
    Log.info('Initializing ProofMode key service',
        name: 'ProofModeKeyService', category: LogCategory.auth);

    if (!await ProofModeConfig.isCryptoEnabled) {
      Log.info('ProofMode crypto disabled, skipping key initialization',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      return;
    }

    try {
      // Check if keys already exist
      final existingKeyPair = await getKeyPair();
      if (existingKeyPair != null) {
        Log.info(
            'Found existing ProofMode keys, fingerprint: ${existingKeyPair.fingerprint}',
            name: 'ProofModeKeyService',
            category: LogCategory.auth);
        return;
      }

      // Generate new keys
      Log.info('No existing keys found, generating new ProofMode key pair',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      await generateKeyPair();
    } catch (e) {
      Log.error('Failed to initialize ProofMode keys: $e',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      rethrow;
    }
  }

  /// Generate a new PGP key pair for this device
  Future<ProofModeKeyPair> generateKeyPair() async {
    Log.info('Generating ProofMode key pair',
        name: 'ProofModeKeyService', category: LogCategory.auth);

    try {
      // For now, we'll use a simplified approach with basic crypto
      // In production, this would use proper PGP libraries like dart_pg

      // Generate a simple key pair using crypto library
      final keyData = _generateSimpleKeyPair();

      final keyPair = ProofModeKeyPair(
        publicKey: keyData['publicKey']!,
        privateKey: keyData['privateKey']!,
        fingerprint: keyData['fingerprint']!,
        createdAt: DateTime.now(),
      );

      // Store in secure storage
      await _storeKeyPair(keyPair);
      _cachedKeyPair = keyPair;

      Log.info(
          'Generated ProofMode key pair with fingerprint: ${keyPair.fingerprint}',
          name: 'ProofModeKeyService',
          category: LogCategory.auth);

      return keyPair;
    } catch (e) {
      Log.error('Failed to generate ProofMode key pair: $e',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      rethrow;
    }
  }

  /// Get the current key pair
  Future<ProofModeKeyPair?> getKeyPair() async {
    if (_cachedKeyPair != null) {
      return _cachedKeyPair;
    }

    try {
      final publicKey = await _secureStorage.read(key: _publicKeyKey);
      final privateKey = await _secureStorage.read(key: _privateKeyKey);
      final fingerprint = await _secureStorage.read(key: _fingerprintKey);
      final createdAtStr = await _secureStorage.read(key: _createdAtKey);

      if (publicKey == null ||
          privateKey == null ||
          fingerprint == null ||
          createdAtStr == null) {
        Log.debug('No complete key pair found in secure storage',
            name: 'ProofModeKeyService', category: LogCategory.auth);
        return null;
      }

      final keyPair = ProofModeKeyPair(
        publicKey: publicKey,
        privateKey: privateKey,
        fingerprint: fingerprint,
        createdAt: DateTime.parse(createdAtStr),
      );

      _cachedKeyPair = keyPair;
      return keyPair;
    } catch (e) {
      Log.error('Failed to retrieve key pair: $e',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      return null;
    }
  }

  /// Get just the public key fingerprint for verification tags
  Future<String?> getPublicKeyFingerprint() async {
    final keyPair = await getKeyPair();
    return keyPair?.fingerprint;
  }

  /// Sign data with the private key
  Future<ProofSignature?> signData(String data) async {
    if (!await ProofModeConfig.isCryptoEnabled) {
      Log.debug('ProofMode crypto disabled, skipping signing',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      return null;
    }

    try {
      final keyPair = await getKeyPair();
      if (keyPair == null) {
        Log.warning('No key pair available for signing',
            name: 'ProofModeKeyService', category: LogCategory.auth);
        return null;
      }

      // Generate signature (simplified approach for now)
      final signature = _signWithPrivateKey(data, keyPair.privateKey);

      final proofSignature = ProofSignature(
        signature: signature,
        publicKeyFingerprint: keyPair.fingerprint,
        signedAt: DateTime.now(),
      );

      Log.debug('Signed data with fingerprint: ${keyPair.fingerprint}',
          name: 'ProofModeKeyService', category: LogCategory.auth);

      return proofSignature;
    } catch (e) {
      Log.error('Failed to sign data: $e',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      return null;
    }
  }

  /// Verify a signature (for testing/validation)
  Future<bool> verifySignature(String data, ProofSignature signature) async {
    try {
      final keyPair = await getKeyPair();
      if (keyPair == null ||
          keyPair.fingerprint != signature.publicKeyFingerprint) {
        Log.warning('Key mismatch for signature verification',
            name: 'ProofModeKeyService', category: LogCategory.auth);
        return false;
      }

      // Verify signature (simplified approach)
      final isValid =
          _verifyWithPublicKey(data, signature.signature, keyPair.publicKey);

      Log.debug('Signature verification result: $isValid',
          name: 'ProofModeKeyService', category: LogCategory.auth);

      return isValid;
    } catch (e) {
      Log.error('Failed to verify signature: $e',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      return false;
    }
  }

  /// Delete all keys (for testing/reset)
  Future<void> deleteKeys() async {
    Log.warning('Deleting ProofMode keys',
        name: 'ProofModeKeyService', category: LogCategory.auth);

    try {
      await _secureStorage.delete(key: _publicKeyKey);
      await _secureStorage.delete(key: _privateKeyKey);
      await _secureStorage.delete(key: _fingerprintKey);
      await _secureStorage.delete(key: _createdAtKey);
      _cachedKeyPair = null;

      Log.info('ProofMode keys deleted successfully',
          name: 'ProofModeKeyService', category: LogCategory.auth);
    } catch (e) {
      Log.error('Failed to delete keys: $e',
          name: 'ProofModeKeyService', category: LogCategory.auth);
      rethrow;
    }
  }

  // Private helper methods

  /// Store key pair in secure storage
  Future<void> _storeKeyPair(ProofModeKeyPair keyPair) async {
    await _secureStorage.write(key: _publicKeyKey, value: keyPair.publicKey);
    await _secureStorage.write(key: _privateKeyKey, value: keyPair.privateKey);
    await _secureStorage.write(
        key: _fingerprintKey, value: keyPair.fingerprint);
    await _secureStorage.write(
        key: _createdAtKey, value: keyPair.createdAt.toIso8601String());
  }

  /// Generate a simple key pair (placeholder for proper PGP implementation)
  Map<String, String> _generateSimpleKeyPair() {
    // This is a simplified implementation
    // In production, use proper PGP libraries like dart_pg or platform channels

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final entropy = List.generate(
        32, (i) => (timestamp.codeUnits[i % timestamp.length] + i) % 256);

    // Generate mock keys (base64 encoded for storage)
    final privateKeyBytes = Uint8List.fromList(entropy);
    final publicKeyBytes = Uint8List.fromList(entropy.take(16).toList());

    final privateKey = base64Encode(privateKeyBytes);
    final publicKey = base64Encode(publicKeyBytes);

    // Generate fingerprint from public key
    final fingerprintHash = sha256.convert(publicKeyBytes);
    final fingerprint =
        fingerprintHash.toString().substring(0, 16).toUpperCase();

    return {
      'privateKey': 'MOCK_PRIVATE_$privateKey',
      'publicKey': 'MOCK_PUBLIC_$publicKey',
      'fingerprint': fingerprint,
    };
  }

  /// Sign data with private key (simplified implementation)
  String _signWithPrivateKey(String data, String privateKey) {
    // Simplified signing - in production use proper PGP signing
    final dataBytes = utf8.encode(data);
    final keyBytes = utf8.encode(privateKey);
    final combined = [...dataBytes, ...keyBytes];
    final hash = sha256.convert(combined);
    return 'MOCK_SIG_${base64Encode(hash.bytes)}';
  }

  /// Verify signature with public key (simplified implementation)
  bool _verifyWithPublicKey(String data, String signature, String publicKey) {
    // Simplified verification - in production use proper PGP verification
    try {
      if (!signature.startsWith('MOCK_SIG_')) return false;

      final expectedSig = _signWithPrivateKey(
          data, 'MOCK_PRIVATE_${publicKey.replaceFirst('MOCK_PUBLIC_', '')}');
      return signature == expectedSig;
    } catch (e) {
      return false;
    }
  }
}
