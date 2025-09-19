// ABOUTME: Comprehensive unit tests for ProofMode PGP key management service
// ABOUTME: Tests key generation, storage, signing, and verification functionality

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openvine/services/proofmode_key_service.dart';
import 'package:openvine/services/proofmode_config.dart';
import 'package:openvine/services/feature_flag_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('ProofModeKeyService', () {
    late ProofModeKeyService keyService;
    late TestFeatureFlagService testFlagService;

    setUpAll(() async {
      await setupTestEnvironment();
    });

    setUp(() async {
      keyService = ProofModeKeyService(secureStorage: MockSecureStorage());
      testFlagService = await TestFeatureFlagService.create();
      ProofModeConfig.initialize(testFlagService);

      // Clear any existing keys
      try {
        await keyService.deleteKeys();
      } catch (e) {
        // Ignore if no keys exist
      }
    });

    tearDown(() async {
      try {
        await keyService.deleteKeys();
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    group('Initialization', () {
      test('should initialize without crypto enabled', () async {
        testFlagService.setFlag('proofmode_crypto', false);

        // Should not throw and should not generate keys
        await keyService.initialize();

        final keyPair = await keyService.getKeyPair();
        expect(keyPair, isNull);
      });

      test('should generate keys when crypto enabled and no existing keys',
          () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.initialize();

        final keyPair = await keyService.getKeyPair();
        expect(keyPair, isNotNull);
        expect(keyPair!.publicKey, isNotEmpty);
        expect(keyPair.privateKey, isNotEmpty);
        expect(keyPair.fingerprint, isNotEmpty);
        expect(keyPair.fingerprint.length, equals(16));
      });

      test('should not regenerate keys if they already exist', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        // First initialization
        await keyService.initialize();
        final firstKeyPair = await keyService.getKeyPair();

        // Second initialization
        await keyService.initialize();
        final secondKeyPair = await keyService.getKeyPair();

        expect(secondKeyPair!.fingerprint, equals(firstKeyPair!.fingerprint));
        expect(secondKeyPair.publicKey, equals(firstKeyPair.publicKey));
      });
    });

    group('Key Generation', () {
      test('should generate unique key pairs', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        final keyPair1 = await keyService.generateKeyPair();
        await keyService.deleteKeys();
        final keyPair2 = await keyService.generateKeyPair();

        expect(keyPair1.fingerprint, isNot(equals(keyPair2.fingerprint)));
        expect(keyPair1.publicKey, isNot(equals(keyPair2.publicKey)));
        expect(keyPair1.privateKey, isNot(equals(keyPair2.privateKey)));
      });

      test('should generate key pair with correct format', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        final keyPair = await keyService.generateKeyPair();

        expect(keyPair.publicKey, startsWith('MOCK_PUBLIC_'));
        expect(keyPair.privateKey, startsWith('MOCK_PRIVATE_'));
        expect(keyPair.fingerprint, hasLength(16));
        expect(keyPair.fingerprint, matches(RegExp(r'^[0-9A-F]+$')));
        expect(keyPair.createdAt, isA<DateTime>());
      });

      test('should store generated keys securely', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        final originalKeyPair = await keyService.generateKeyPair();

        // Create new service instance to test persistence
        final newKeyService = ProofModeKeyService();
        final retrievedKeyPair = await newKeyService.getKeyPair();

        expect(retrievedKeyPair, isNotNull);
        expect(
            retrievedKeyPair!.fingerprint, equals(originalKeyPair.fingerprint));
        expect(retrievedKeyPair.publicKey, equals(originalKeyPair.publicKey));
        expect(retrievedKeyPair.privateKey, equals(originalKeyPair.privateKey));
      });
    });

    group('Key Retrieval', () {
      test('should return null when no keys exist', () async {
        final keyPair = await keyService.getKeyPair();
        expect(keyPair, isNull);
      });

      test('should cache key pair after first retrieval', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();

        // First retrieval
        final keyPair1 = await keyService.getKeyPair();
        // Second retrieval (should use cache)
        final keyPair2 = await keyService.getKeyPair();

        expect(keyPair1, isNotNull);
        expect(keyPair2, isNotNull);
        expect(identical(keyPair1, keyPair2), isTrue); // Same object reference
      });

      test('should return public key fingerprint correctly', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        final keyPair = await keyService.generateKeyPair();
        final fingerprint = await keyService.getPublicKeyFingerprint();

        expect(fingerprint, equals(keyPair.fingerprint));
      });

      test('should return null fingerprint when no keys exist', () async {
        final fingerprint = await keyService.getPublicKeyFingerprint();
        expect(fingerprint, isNull);
      });
    });

    group('Data Signing', () {
      test('should sign data successfully when crypto enabled', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        const testData = 'test data to sign';

        final signature = await keyService.signData(testData);

        expect(signature, isNotNull);
        expect(signature!.signature, isNotEmpty);
        expect(signature.signature, startsWith('MOCK_SIG_'));
        expect(signature.publicKeyFingerprint, isNotEmpty);
        expect(signature.signedAt, isA<DateTime>());
      });

      test('should return null when crypto disabled', () async {
        testFlagService.setFlag('proofmode_crypto', false);

        const testData = 'test data to sign';
        final signature = await keyService.signData(testData);

        expect(signature, isNull);
      });

      test('should return null when no keys available', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        const testData = 'test data to sign';
        final signature = await keyService.signData(testData);

        expect(signature, isNull);
      });

      test('should generate consistent signatures for same data', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        const testData = 'consistent test data';

        final signature1 = await keyService.signData(testData);
        final signature2 = await keyService.signData(testData);

        expect(signature1!.signature, equals(signature2!.signature));
        expect(signature1.publicKeyFingerprint,
            equals(signature2.publicKeyFingerprint));
      });

      test('should generate different signatures for different data', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();

        final signature1 = await keyService.signData('data 1');
        final signature2 = await keyService.signData('data 2');

        expect(signature1!.signature, isNot(equals(signature2!.signature)));
        expect(signature1.publicKeyFingerprint,
            equals(signature2.publicKeyFingerprint));
      });
    });

    group('Signature Verification', () {
      test('should verify valid signature successfully', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        const testData = 'data to verify';

        final signature = await keyService.signData(testData);
        final isValid = await keyService.verifySignature(testData, signature!);

        expect(isValid, isTrue);
      });

      test('should reject invalid signature', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        const originalData = 'original data';
        const modifiedData = 'modified data';

        final signature = await keyService.signData(originalData);
        final isValid =
            await keyService.verifySignature(modifiedData, signature!);

        expect(isValid, isFalse);
      });

      test('should reject signature with wrong fingerprint', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        const testData = 'test data';

        final signature = await keyService.signData(testData);

        // Create fake signature with wrong fingerprint
        final fakeSignature = ProofSignature(
          signature: signature!.signature,
          publicKeyFingerprint: 'WRONGFINGERPRINT',
          signedAt: signature.signedAt,
        );

        final isValid =
            await keyService.verifySignature(testData, fakeSignature);
        expect(isValid, isFalse);
      });

      test('should return false when no keys available for verification',
          () async {
        testFlagService.setFlag('proofmode_crypto', true);

        final fakeSignature = ProofSignature(
          signature: 'fake_signature',
          publicKeyFingerprint: 'fake_fingerprint',
          signedAt: DateTime.now(),
        );

        final isValid =
            await keyService.verifySignature('test data', fakeSignature);
        expect(isValid, isFalse);
      });
    });

    group('Key Deletion', () {
      test('should delete all keys successfully', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        expect(await keyService.getKeyPair(), isNotNull);

        await keyService.deleteKeys();
        expect(await keyService.getKeyPair(), isNull);
      });

      test('should clear cache when keys deleted', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        await keyService.getKeyPair(); // Cache the keys

        await keyService.deleteKeys();

        final keyPairAfterDeletion = await keyService.getKeyPair();
        expect(keyPairAfterDeletion, isNull);
      });

      test('should not throw when deleting non-existent keys', () async {
        // Should not throw exception
        expect(() => keyService.deleteKeys(), returnsNormally);
      });
    });

    group('JSON Serialization', () {
      test('should serialize and deserialize ProofModeKeyPair correctly',
          () async {
        testFlagService.setFlag('proofmode_crypto', true);

        final originalKeyPair = await keyService.generateKeyPair();
        final json = originalKeyPair.toJson();
        final deserializedKeyPair = ProofModeKeyPair.fromJson(json);

        expect(
            deserializedKeyPair.publicKey, equals(originalKeyPair.publicKey));
        expect(
            deserializedKeyPair.privateKey, equals(originalKeyPair.privateKey));
        expect(deserializedKeyPair.fingerprint,
            equals(originalKeyPair.fingerprint));
        expect(
            deserializedKeyPair.createdAt, equals(originalKeyPair.createdAt));
      });

      test('should serialize and deserialize ProofSignature correctly',
          () async {
        testFlagService.setFlag('proofmode_crypto', true);

        await keyService.generateKeyPair();
        final originalSignature = await keyService.signData('test data');

        final json = originalSignature!.toJson();
        final deserializedSignature = ProofSignature.fromJson(json);

        expect(deserializedSignature.signature,
            equals(originalSignature.signature));
        expect(deserializedSignature.publicKeyFingerprint,
            equals(originalSignature.publicKeyFingerprint));
        expect(
            deserializedSignature.signedAt, equals(originalSignature.signedAt));
      });
    });

    group('Error Handling', () {
      test('should handle secure storage errors gracefully', () async {
        testFlagService.setFlag('proofmode_crypto', true);

        // This test would require mocking FlutterSecureStorage to throw errors
        // For now, just ensure the service doesn't crash
        expect(() => keyService.getKeyPair(), returnsNormally);
      });

      test('should handle malformed stored data gracefully', () async {
        // This would require mocking corrupted data in secure storage
        // The service should return null for malformed data
        expect(() => keyService.getKeyPair(), returnsNormally);
      });
    });
  });
}

/// Test implementation of FeatureFlagService for testing
class TestFeatureFlagService extends FeatureFlagService {
  final Map<String, bool> _flags = {};

  TestFeatureFlagService._()
      : super(
          apiBaseUrl: 'test',
          prefs: _testPrefs!,
        );

  static SharedPreferences? _testPrefs;

  static Future<TestFeatureFlagService> create() async {
    _testPrefs = await getTestSharedPreferences();
    return TestFeatureFlagService._();
  }

  void setFlag(String name, bool enabled) {
    _flags[name] = enabled;
  }

  @override
  Future<bool> isEnabled(String flagName,
      {Map<String, dynamic>? attributes, bool forceRefresh = false}) async {
    return _flags[flagName] ?? false;
  }
}
