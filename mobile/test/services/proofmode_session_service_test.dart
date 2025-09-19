// ABOUTME: Comprehensive unit tests for ProofMode session management service
// ABOUTME: Tests session lifecycle, segment recording, and proof manifest generation

import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/services/proofmode_session_service.dart';
import 'package:openvine/services/proofmode_key_service.dart';
import 'package:openvine/services/proofmode_attestation_service.dart';
import 'package:openvine/services/proofmode_config.dart';
import 'package:openvine/services/feature_flag_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/test_helpers.dart';
import 'dart:typed_data';

void main() {
  group('ProofModeSessionService', () {
    late ProofModeSessionService sessionService;
    late TestProofModeKeyService testKeyService;
    late TestProofModeAttestationService testAttestationService;
    late TestFeatureFlagService testFlagService;

    setUpAll(() async {
      await setupTestEnvironment();
    });

    setUp(() async {
      testKeyService = TestProofModeKeyService();
      testAttestationService = TestProofModeAttestationService();
      testFlagService = await TestFeatureFlagService.create();

      sessionService =
          ProofModeSessionService(testKeyService, testAttestationService);
      ProofModeConfig.initialize(testFlagService);
    });

    tearDown(() async {
      await sessionService.cancelSession();
    });

    group('Session Management', () {
      test('should start session when capture enabled', () async {
        testFlagService.setFlag('proofmode_capture', true);

        final sessionId = await sessionService.startSession();

        expect(sessionId, isNotNull);
        expect(sessionId!.startsWith('session_'), isTrue);
        expect(sessionService.hasActiveSession, isTrue);
        expect(sessionService.currentSessionId, equals(sessionId));
      });

      test('should not start session when capture disabled', () async {
        testFlagService.setFlag('proofmode_capture', false);

        final sessionId = await sessionService.startSession();

        expect(sessionId, isNull);
        expect(sessionService.hasActiveSession, isFalse);
        expect(sessionService.currentSessionId, isNull);
      });

      test('should generate unique session IDs', () async {
        testFlagService.setFlag('proofmode_capture', true);

        final sessionId1 = await sessionService.startSession();
        await sessionService.cancelSession();
        final sessionId2 = await sessionService.startSession();

        expect(sessionId1, isNot(equals(sessionId2)));
      });

      test('should include device attestation in session', () async {
        testFlagService.setFlag('proofmode_capture', true);
        testAttestationService.setMockAttestation(DeviceAttestation(
          token: 'test_token',
          platform: 'test',
          deviceId: 'test_device',
          isHardwareBacked: true,
          createdAt: DateTime.now(),
        ));

        await sessionService.startSession();

        expect(testAttestationService.attestationRequested, isTrue);
      });

      test('should cancel session successfully', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        expect(sessionService.hasActiveSession, isTrue);

        await sessionService.cancelSession();
        expect(sessionService.hasActiveSession, isFalse);
        expect(sessionService.currentSessionId, isNull);
      });
    });

    group('Recording Segments', () {
      test('should start recording segment in active session', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        await sessionService.startRecordingSegment();

        expect(sessionService.isRecording, isTrue);
      });

      test('should not start recording without active session', () async {
        await sessionService.startRecordingSegment();

        expect(sessionService.isRecording, isFalse);
      });

      test('should stop recording segment successfully', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        await sessionService.startRecordingSegment();
        expect(sessionService.isRecording, isTrue);

        await sessionService.stopRecordingSegment();
        expect(sessionService.isRecording, isFalse);
      });

      test('should handle multiple recording segments', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();

        // First segment
        await sessionService.startRecordingSegment();
        await sessionService.addFrameHash(Uint8List.fromList([1, 2, 3]));
        await sessionService.stopRecordingSegment();

        // Second segment
        await sessionService.startRecordingSegment();
        await sessionService.addFrameHash(Uint8List.fromList([4, 5, 6]));
        await sessionService.stopRecordingSegment();

        final manifest =
            await sessionService.finalizeSession('test_video_hash');
        expect(manifest!.segments.length, equals(2));
      });

      test('should add frame hashes during recording', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        await sessionService.startRecordingSegment();

        final frameData1 = Uint8List.fromList([1, 2, 3, 4]);
        final frameData2 = Uint8List.fromList([5, 6, 7, 8]);

        await sessionService.addFrameHash(frameData1);
        await sessionService.addFrameHash(frameData2);

        await sessionService.stopRecordingSegment();
        final manifest =
            await sessionService.finalizeSession('test_video_hash');

        expect(manifest!.segments.length, equals(1));
        expect(manifest.segments[0].frameHashes.length, equals(2));
        expect(manifest.segments[0].frameHashes, isNot(isEmpty));
      });

      test('should not add frame hashes when not recording', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();

        final frameData = Uint8List.fromList([1, 2, 3, 4]);
        await sessionService.addFrameHash(frameData);

        final manifest =
            await sessionService.finalizeSession('test_video_hash');
        expect(manifest!.segments, isEmpty);
      });
    });

    group('User Interactions', () {
      test('should record user interactions', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();

        await sessionService.recordInteraction('start', 0.5, 0.5);
        await sessionService.recordInteraction('touch', 0.3, 0.7,
            pressure: 0.8);
        await sessionService.recordInteraction('stop', 0.5, 0.5);

        final manifest =
            await sessionService.finalizeSession('test_video_hash');

        expect(manifest!.interactions.length, equals(3));
        expect(manifest.interactions[0].interactionType, equals('start'));
        expect(manifest.interactions[1].interactionType, equals('touch'));
        expect(manifest.interactions[1].pressure, equals(0.8));
        expect(manifest.interactions[2].interactionType, equals('stop'));
      });

      test('should not record interactions without active session', () async {
        await sessionService.recordInteraction('touch', 0.5, 0.5);

        // Should not throw, but interaction is ignored
        expect(() => sessionService.recordInteraction('touch', 0.5, 0.5),
            returnsNormally);
      });

      test('should record coordinates correctly', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        await sessionService.recordInteraction('touch', 0.123, 0.456);

        final manifest =
            await sessionService.finalizeSession('test_video_hash');

        expect(manifest!.interactions.length, equals(1));
        expect(manifest.interactions[0].coordinates['x'], equals(0.123));
        expect(manifest.interactions[0].coordinates['y'], equals(0.456));
      });
    });

    group('Session Finalization', () {
      test('should finalize session and generate proof manifest', () async {
        testFlagService.setFlag('proofmode_capture', true);
        testKeyService.setMockSignature(ProofSignature(
          signature: 'test_signature',
          publicKeyFingerprint: 'test_fingerprint',
          signedAt: DateTime.now(),
        ));

        await sessionService.startSession();
        await sessionService.recordInteraction('start', 0.5, 0.5);

        await sessionService.startRecordingSegment();
        await sessionService.addFrameHash(Uint8List.fromList([1, 2, 3]));
        await sessionService.stopRecordingSegment();

        await sessionService.recordInteraction('stop', 0.5, 0.5);

        final manifest =
            await sessionService.finalizeSession('final_video_hash');

        expect(manifest, isNotNull);
        expect(manifest!.sessionId, isNotNull);
        expect(manifest.challengeNonce, isNotNull);
        expect(manifest.finalVideoHash, equals('final_video_hash'));
        expect(manifest.segments.length, equals(1));
        expect(manifest.interactions.length, equals(2));
        expect(manifest.pgpSignature, isNotNull);
        expect(manifest.pgpSignature!.signature, equals('test_signature'));
      });

      test('should calculate session durations correctly', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();

        await sessionService.startRecordingSegment();
        await Future.delayed(Duration(milliseconds: 100));
        await sessionService.stopRecordingSegment();

        await Future.delayed(Duration(milliseconds: 50));

        await sessionService.startRecordingSegment();
        await Future.delayed(Duration(milliseconds: 100));
        await sessionService.stopRecordingSegment();

        final manifest = await sessionService.finalizeSession('test_hash');

        expect(manifest!.totalDuration.inMilliseconds, greaterThan(200));
        expect(manifest.recordingDuration.inMilliseconds, greaterThan(150));
        expect(manifest.recordingDuration, lessThan(manifest.totalDuration));
      });

      test('should handle finalization without recording segments', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        await sessionService.recordInteraction('cancel', 0.5, 0.5);

        final manifest = await sessionService.finalizeSession('test_hash');

        expect(manifest, isNotNull);
        expect(manifest!.segments, isEmpty);
        expect(manifest.interactions.length, equals(1));
        expect(manifest.recordingDuration, equals(Duration.zero));
      });

      test('should return null when finalizing without active session',
          () async {
        final manifest = await sessionService.finalizeSession('test_hash');
        expect(manifest, isNull);
      });

      test('should clear session after finalization', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        expect(sessionService.hasActiveSession, isTrue);

        await sessionService.finalizeSession('test_hash');
        expect(sessionService.hasActiveSession, isFalse);
        expect(sessionService.currentSessionId, isNull);
      });
    });

    group('JSON Serialization', () {
      test('should serialize and deserialize ProofManifest correctly',
          () async {
        testFlagService.setFlag('proofmode_capture', true);
        testKeyService.setMockSignature(ProofSignature(
          signature: 'test_sig',
          publicKeyFingerprint: 'test_fp',
          signedAt: DateTime.now(),
        ));

        await sessionService.startSession();
        await sessionService.startRecordingSegment();
        await sessionService.addFrameHash(Uint8List.fromList([1, 2, 3]));
        await sessionService.stopRecordingSegment();
        await sessionService.recordInteraction('test', 0.1, 0.2, pressure: 0.5);

        final originalManifest =
            await sessionService.finalizeSession('test_hash');

        final json = originalManifest!.toJson();
        final deserializedManifest = ProofManifest.fromJson(json);

        expect(
            deserializedManifest.sessionId, equals(originalManifest.sessionId));
        expect(deserializedManifest.challengeNonce,
            equals(originalManifest.challengeNonce));
        expect(deserializedManifest.finalVideoHash,
            equals(originalManifest.finalVideoHash));
        expect(deserializedManifest.segments.length,
            equals(originalManifest.segments.length));
        expect(deserializedManifest.interactions.length,
            equals(originalManifest.interactions.length));
      });

      test('should serialize segment data correctly', () async {
        testFlagService.setFlag('proofmode_capture', true);

        await sessionService.startSession();
        await sessionService.startRecordingSegment();
        await sessionService.addFrameHash(Uint8List.fromList([1, 2, 3]));
        await sessionService.addFrameHash(Uint8List.fromList([4, 5, 6]));
        await sessionService.stopRecordingSegment();

        final manifest = await sessionService.finalizeSession('test_hash');
        final segment = manifest!.segments[0];

        final json = segment.toJson();
        final deserializedSegment = RecordingSegment.fromJson(json);

        expect(deserializedSegment.segmentId, equals(segment.segmentId));
        expect(deserializedSegment.startTime, equals(segment.startTime));
        expect(deserializedSegment.endTime, equals(segment.endTime));
        expect(deserializedSegment.frameHashes, equals(segment.frameHashes));
        expect(deserializedSegment.duration, equals(segment.duration));
      });
    });

    group('Error Handling', () {
      test('should handle key service errors gracefully', () async {
        testFlagService.setFlag('proofmode_capture', true);
        testKeyService.setShouldThrowError(true);

        await sessionService.startSession();
        final manifest = await sessionService.finalizeSession('test_hash');

        // Should complete without throwing, but without signature
        expect(manifest, isNotNull);
        expect(manifest!.pgpSignature, isNull);
      });

      test('should handle attestation service errors gracefully', () async {
        testFlagService.setFlag('proofmode_capture', true);
        testAttestationService.setShouldThrowError(true);

        final sessionId = await sessionService.startSession();

        // Should still start session even if attestation fails
        expect(sessionId, isNotNull);
        expect(sessionService.hasActiveSession, isTrue);
      });
    });
  });
}

/// Test implementation of ProofModeKeyService
class TestProofModeKeyService extends ProofModeKeyService {
  ProofSignature? _mockSignature;
  bool _shouldThrowError = false;

  void setMockSignature(ProofSignature signature) {
    _mockSignature = signature;
  }

  void setShouldThrowError(bool shouldThrow) {
    _shouldThrowError = shouldThrow;
  }

  @override
  Future<ProofSignature?> signData(String data) async {
    if (_shouldThrowError) {
      throw Exception('Test key service error');
    }
    return _mockSignature;
  }
}

/// Test implementation of ProofModeAttestationService
class TestProofModeAttestationService extends ProofModeAttestationService {
  DeviceAttestation? _mockAttestation;
  bool _shouldThrowError = false;
  bool attestationRequested = false;

  void setMockAttestation(DeviceAttestation attestation) {
    _mockAttestation = attestation;
  }

  void setShouldThrowError(bool shouldThrow) {
    _shouldThrowError = shouldThrow;
  }

  @override
  Future<DeviceAttestation?> generateAttestation(String challenge) async {
    attestationRequested = true;
    if (_shouldThrowError) {
      throw Exception('Test attestation service error');
    }
    return _mockAttestation;
  }
}

/// Test implementation of FeatureFlagService
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
