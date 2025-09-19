// ABOUTME: Service for migrating videos to Cloudflare Stream via migration API
// ABOUTME: Handles video uploads to CF Stream with BigQuery enrichment and blurhash generation

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Result of a Cloudflare Stream migration operation
class CloudflareStreamResult {
  const CloudflareStreamResult({
    required this.success,
    this.streamUid,
    this.hlsUrl,
    this.mp4Url,
    this.dashUrl,
    this.thumbnailUrl,
    this.animatedThumbnailUrl,
    this.blurhash,
    this.errorMessage,
    this.metadata,
  });

  factory CloudflareStreamResult.success({
    required String streamUid,
    required String hlsUrl,
    required String mp4Url,
    String? dashUrl,
    required String thumbnailUrl,
    required String animatedThumbnailUrl,
    String? blurhash,
    Map<String, dynamic>? metadata,
  }) =>
      CloudflareStreamResult(
        success: true,
        streamUid: streamUid,
        hlsUrl: hlsUrl,
        mp4Url: mp4Url,
        dashUrl: dashUrl,
        thumbnailUrl: thumbnailUrl,
        animatedThumbnailUrl: animatedThumbnailUrl,
        blurhash: blurhash,
        metadata: metadata,
      );

  factory CloudflareStreamResult.failure(String errorMessage) =>
      CloudflareStreamResult(
        success: false,
        errorMessage: errorMessage,
      );

  final bool success;
  final String? streamUid;
  final String? hlsUrl;
  final String? mp4Url;
  final String? dashUrl;
  final String? thumbnailUrl;
  final String? animatedThumbnailUrl;
  final String? blurhash;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
}

/// Service for uploading videos to Cloudflare Stream
class CloudflareStreamService {
  CloudflareStreamService({
    required this.authService,
    http.Client? httpClient,
    String? migrationApiUrl,
    String? bearerToken,
  })  : _httpClient = httpClient ?? http.Client(),
        _migrationApiUrl = migrationApiUrl ??
            'https://cf-stream-service-prod.protestnet.workers.dev',
        _bearerToken = bearerToken ??
            const String.fromEnvironment('CF_STREAM_TOKEN');

  final AuthService authService;
  final http.Client _httpClient;
  final String _migrationApiUrl;
  final String _bearerToken;

  // Rate limiting
  static const int _maxRetries = 5;
  static const int _baseDelayMs = 2000;
  final Map<String, DateTime> _lastRequestTime = {};

  /// Migrate a video to Cloudflare Stream
  Future<CloudflareStreamResult> migrateToStream({
    required File videoFile,
    required String vineId,
    String? title,
    String? description,
    List<String>? hashtags,
    bool enrichWithBigQuery = false,
    bool generateBlurhash = false,
    void Function(double progress)? onProgress,
  }) async {
    Log.info('🎬 Starting Cloudflare Stream migration for vine: $vineId',
        name: 'CloudflareStreamService', category: LogCategory.video);

    try {
      // Check file exists and is readable
      if (!await videoFile.exists()) {
        return CloudflareStreamResult.failure('Video file does not exist');
      }

      final fileSize = await videoFile.length();
      Log.info('📁 Video file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
          name: 'CloudflareStreamService', category: LogCategory.video);

      // Rate limiting check
      await _enforceRateLimit(vineId);

      // Prepare the upload
      onProgress?.call(0.1);

      // Call migration API with retries
      final migrationResult = await _callMigrationApiWithRetry(
        vineId: vineId,
        videoFile: videoFile,
        title: title,
        description: description,
        hashtags: hashtags,
        enrichWithBigQuery: enrichWithBigQuery,
        onProgress: onProgress,
      );

      if (!migrationResult['success']) {
        return CloudflareStreamResult.failure(
          migrationResult['error'] ?? 'Migration failed',
        );
      }

      // Extract URLs from response
      final streamUid = migrationResult['stream_uid'] as String;
      final cdnBase = 'https://cdn.divine.video/$streamUid';

      final hlsUrl = '$cdnBase/manifest/video.m3u8';
      final mp4Url = '$cdnBase/downloads/default.mp4';
      final dashUrl = '$cdnBase/manifest/video.mpd';
      final thumbnailUrl = '$cdnBase/thumbnails/thumbnail.jpg';
      final animatedThumbnailUrl = '$cdnBase/thumbnails/thumbnail.gif';

      onProgress?.call(0.8);

      // Generate blurhash if requested
      String? blurhash;
      if (generateBlurhash) {
        blurhash = await _generateBlurhash(thumbnailUrl);
      }

      onProgress?.call(1.0);

      Log.info('✅ Migration successful! Stream UID: $streamUid',
          name: 'CloudflareStreamService', category: LogCategory.video);

      return CloudflareStreamResult.success(
        streamUid: streamUid,
        hlsUrl: hlsUrl,
        mp4Url: mp4Url,
        dashUrl: dashUrl,
        thumbnailUrl: thumbnailUrl,
        animatedThumbnailUrl: animatedThumbnailUrl,
        blurhash: blurhash,
        metadata: migrationResult['metadata'] as Map<String, dynamic>?,
      );
    } catch (e) {
      Log.error('❌ Stream migration failed: $e',
          name: 'CloudflareStreamService', category: LogCategory.video);
      return CloudflareStreamResult.failure('Migration error: $e');
    }
  }

  /// Call migration API with retry logic
  Future<Map<String, dynamic>> _callMigrationApiWithRetry({
    required String vineId,
    required File videoFile,
    String? title,
    String? description,
    List<String>? hashtags,
    bool enrichWithBigQuery = false,
    void Function(double progress)? onProgress,
  }) async {
    int retryCount = 0;
    int delayMs = _baseDelayMs;

    while (retryCount <= _maxRetries) {
      try {
        // Read video file
        final videoBytes = await videoFile.readAsBytes();

        // Create multipart request
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_migrationApiUrl/v1/openvine/migrate'),
        );

        // Add authorization
        if (_bearerToken.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $_bearerToken';
        }

        // Add fields
        request.fields['vine_id'] = vineId;
        request.fields['openvine_id'] = vineId; // Use same ID for now
        if (title != null) request.fields['title'] = title;
        if (description != null) request.fields['description'] = description;
        if (hashtags != null) {
          request.fields['hashtags'] = hashtags.join(',');
        }
        request.fields['enrich_bigquery'] = enrichWithBigQuery.toString();

        // Add video file
        request.files.add(http.MultipartFile.fromBytes(
          'video',
          videoBytes,
          filename: 'vine_$vineId.mp4',
        ));

        onProgress?.call(0.3 + (0.4 * (retryCount / _maxRetries)));

        // Send request
        final streamedResponse = await _httpClient.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          return {
            'success': true,
            'stream_uid': data['stream_uid'],
            'metadata': data['metadata'],
          };
        }

        // Handle rate limiting
        if (response.statusCode == 429) {
          if (retryCount < _maxRetries) {
            Log.warning('⏳ Rate limited, retrying in ${delayMs}ms...',
                name: 'CloudflareStreamService', category: LogCategory.video);
            await Future.delayed(Duration(milliseconds: delayMs));
            delayMs = min(delayMs * 2, 32000); // Exponential backoff
            retryCount++;
            continue;
          }
        }

        // Handle other errors
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      } on SocketException catch (e) {
        if (retryCount < _maxRetries) {
          Log.warning('🔄 Network error, retrying... ($e)',
              name: 'CloudflareStreamService', category: LogCategory.video);
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs = min(delayMs * 2, 32000);
          retryCount++;
          continue;
        }
        return {'success': false, 'error': 'Network error: $e'};
      } catch (e) {
        if (retryCount < _maxRetries && _isRetryableError(e)) {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs = min(delayMs * 2, 32000);
          retryCount++;
          continue;
        }
        return {'success': false, 'error': 'Unexpected error: $e'};
      }
    }

    return {'success': false, 'error': 'Max retries exceeded'};
  }

  /// Generate blurhash from thumbnail URL
  Future<String?> _generateBlurhash(String thumbnailUrl) async {
    try {
      Log.info('🎨 Generating blurhash from thumbnail',
          name: 'CloudflareStreamService', category: LogCategory.video);

      // Download thumbnail
      final response = await _httpClient.get(Uri.parse(thumbnailUrl));
      if (response.statusCode != 200) {
        Log.warning('Failed to download thumbnail for blurhash',
            name: 'CloudflareStreamService', category: LogCategory.video);
        return null;
      }

      // Decode image
      final image = img.decodeImage(response.bodyBytes);
      if (image == null) {
        Log.warning('Failed to decode thumbnail image',
            name: 'CloudflareStreamService', category: LogCategory.video);
        return null;
      }

      // Resize to 32x32 for blurhash
      final resized = img.copyResize(image, width: 32, height: 32);

      // Generate blurhash with 4x3 components
      // BlurHash.encode expects an image from the image package
      final hash = BlurHash.encode(
        resized,
        numCompX: 4,
        numCompY: 3,
      );

      Log.info('✅ Blurhash generated: ${hash.hash}',
          name: 'CloudflareStreamService', category: LogCategory.video);

      return hash.hash;
    } catch (e) {
      Log.error('Failed to generate blurhash: $e',
          name: 'CloudflareStreamService', category: LogCategory.video);
      return null;
    }
  }

  /// Enforce rate limiting
  Future<void> _enforceRateLimit(String id) async {
    final now = DateTime.now();
    final lastRequest = _lastRequestTime[id];

    if (lastRequest != null) {
      final timeSinceLastRequest = now.difference(lastRequest);
      if (timeSinceLastRequest.inMilliseconds < 1000) {
        // Wait at least 1 second between requests
        await Future.delayed(
          Duration(milliseconds: 1000 - timeSinceLastRequest.inMilliseconds),
        );
      }
    }

    _lastRequestTime[id] = DateTime.now();
  }

  /// Check if error is retryable
  bool _isRetryableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('socket');
  }
}