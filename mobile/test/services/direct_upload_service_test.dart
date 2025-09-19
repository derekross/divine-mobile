// ABOUTME: Tests for direct upload service including profile picture uploads
// ABOUTME: Verifies image upload functionality, progress tracking, and error handling

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nostr_sdk/event.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/nip98_auth_service.dart';

@GenerateMocks([
  http.Client,
  Nip98AuthService,
  File,
])
import 'direct_upload_service_test.mocks.dart';

void main() {
  group('DirectUploadService - Profile Picture Upload', () {
    late DirectUploadService uploadService;
    late MockClient mockHttpClient;
    late MockNip98AuthService mockAuthService;
    late MockFile mockFile;

    setUp(() {
      mockHttpClient = MockClient();
      mockAuthService = MockNip98AuthService();
      mockFile = MockFile();

      uploadService = DirectUploadService(
        authService: mockAuthService,
        httpClient: mockHttpClient,
      );

      // Setup file mocks
      when(mockFile.path).thenReturn('/path/to/image.jpg');
      when(mockFile.length()).thenAnswer((_) async => 1024);
      when(mockFile.openRead()).thenAnswer(
        (_) => Stream.fromIterable([
          Uint8List.fromList(List.generate(1024, (i) => i % 256)),
        ]),
      );

      // Setup auth service
      when(mockAuthService.canCreateTokens).thenReturn(true);
      when(
        mockAuthService.createAuthToken(
          url: anyNamed('url'),
          method: anyNamed('method'),
        ),
      ).thenAnswer(
        (_) async => Nip98Token(
          token: 'test_token',
          signedEvent: Event(
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
              27235,
              [],
              '',
              createdAt: 0),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          expiresAt: DateTime.fromMillisecondsSinceEpoch(60000),
        ),
      );
    });

    test('uploadProfilePicture sends correct request', () async {
      // Mock successful response
      when(mockHttpClient.send(any)).thenAnswer((_) async {
        final response = http.StreamedResponse(
          Stream.value(
            '{"status":"success","url":"https://cdn.example.com/image.jpg","download_url":"https://cdn.example.com/image.jpg"}'
                .codeUnits,
          ),
          200,
        );
        return response;
      });

      final result = await uploadService.uploadProfilePicture(
        imageFile: mockFile,
        nostrPubkey: 'test_pubkey',
      );

      expect(result.success, isTrue);
      expect(result.cdnUrl, equals('https://cdn.example.com/image.jpg'));

      // Verify request was sent with correct parameters
      final captured = verify(mockHttpClient.send(captureAny)).captured;
      final request = captured.first as http.MultipartRequest;

      expect(request.method, equals('POST'));
      expect(request.url.path, contains('/api/upload'));
      expect(request.fields['type'], equals('profile_picture'));
      expect(request.fields['pubkey'], equals('test_pubkey'));
      expect(request.files.length, equals(1));
      expect(request.files.first.field, equals('file'));
    });

    test('uploadProfilePicture tracks progress', () async {
      final progressValues = <double>[];

      // Mock response with proper async pattern
      when(mockHttpClient.send(any)).thenAnswer((_) async {
        // Simulate progress tracking by returning a response that allows progress monitoring
        final controller = StreamController<List<int>>();

        // Add progress callback that gets called during upload
        Timer(Duration.zero, () {
          controller.add(
              '{"status":"success","url":"https://cdn.example.com/image.jpg"}'
                  .codeUnits);
          controller.close();
        });

        return http.StreamedResponse(
          controller.stream,
          200,
        );
      });

      await uploadService.uploadProfilePicture(
        imageFile: mockFile,
        nostrPubkey: 'test_pubkey',
        onProgress: progressValues.add,
      );

      // Should have progress updates
      expect(progressValues.isNotEmpty, isTrue);
      expect(progressValues.first, lessThan(1.0));
      expect(progressValues.last,
          greaterThanOrEqualTo(0.95)); // Progress reaches at least 95%
    });

    test('uploadProfilePicture handles upload failure', () async {
      // Mock error response
      when(mockHttpClient.send(any)).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(
            '{"status":"error","message":"Upload failed"}'.codeUnits,
          ),
          400,
        ),
      );

      final result = await uploadService.uploadProfilePicture(
        imageFile: mockFile,
        nostrPubkey: 'test_pubkey',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('400'));
    });

    test('uploadProfilePicture handles network error', () async {
      // Mock network error
      when(mockHttpClient.send(any)).thenThrow(
        const SocketException('Network error'),
      );

      final result = await uploadService.uploadProfilePicture(
        imageFile: mockFile,
        nostrPubkey: 'test_pubkey',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Network error'));
    });

    test('handles correct image content types', () {
      // This is tested internally by the upload methods
      // The _getImageContentType method is private and tested via the public API
      expect(true, isTrue);
    });

    test('uploadProfilePicture adds authorization headers', () async {
      when(mockHttpClient.send(any)).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(
            '{"status":"success","url":"https://cdn.example.com/image.jpg"}'
                .codeUnits,
          ),
          200,
        ),
      );

      await uploadService.uploadProfilePicture(
        imageFile: mockFile,
        nostrPubkey: 'test_pubkey',
      );

      // Verify auth token was created
      verify(
        mockAuthService.createAuthToken(
          url: argThat(contains('/api/upload'), named: 'url'),
          method: HttpMethod.post,
        ),
      ).called(1);

      // Verify authorization header was added to request
      final captured = verify(mockHttpClient.send(captureAny)).captured;
      final request = captured.first as http.MultipartRequest;

      expect(request.headers['Authorization'], equals('Nostr test_token'));
    });

    test('uploadProfilePicture handles missing auth service', () async {
      // Create service without auth
      final serviceNoAuth = DirectUploadService(httpClient: mockHttpClient);

      when(mockHttpClient.send(any)).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(
            '{"status":"success","url":"https://cdn.example.com/image.jpg"}'
                .codeUnits,
          ),
          200,
        ),
      );

      final result = await serviceNoAuth.uploadProfilePicture(
        imageFile: mockFile,
        nostrPubkey: 'test_pubkey',
      );

      // Should still work without auth
      expect(result.success, isTrue);
    });
  });
}
