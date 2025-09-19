// ABOUTME: Direct video upload service for CF Workers without external dependencies
// ABOUTME: Uploads videos directly to Cloudflare Workers → R2 storage with CDN serving

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// import 'package:crypto/crypto.dart'; // Not needed - no SHA256 for new recordings
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:openvine/config/app_config.dart';
import 'package:openvine/services/nip98_auth_service.dart';
import 'package:openvine/services/video_thumbnail_service.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Result of a direct upload operation
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class DirectUploadResult {
  const DirectUploadResult({
    required this.success,
    this.videoId,
    this.cdnUrl,
    this.thumbnailUrl,
    this.errorMessage,
    this.metadata,
  });

  factory DirectUploadResult.success({
    required String videoId,
    required String cdnUrl,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
  }) =>
      DirectUploadResult(
        success: true,
        videoId: videoId,
        cdnUrl: cdnUrl,
        thumbnailUrl: thumbnailUrl,
        metadata: metadata,
      );

  factory DirectUploadResult.failure(String errorMessage) => DirectUploadResult(
        success: false,
        errorMessage: errorMessage,
      );
  final bool success;
  final String? videoId;
  final String? cdnUrl;
  final String? thumbnailUrl;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
}

/// Service for uploading videos and images directly to CF Workers
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class DirectUploadService {
  DirectUploadService({
    Nip98AuthService? authService,
    http.Client? httpClient,
  })  : _authService = authService,
        _httpClient = httpClient ?? http.Client();

  static String get _baseUrl => AppConfig.backendBaseUrl;

  final Map<String, StreamController<double>> _progressControllers = {};
  final Map<String, StreamSubscription<double>> _progressSubscriptions = {};
  final Nip98AuthService? _authService;
  final http.Client _httpClient;

  /// Upload a video file directly to CF Workers with progress tracking
  Future<DirectUploadResult> uploadVideo({
    required File videoFile,
    required String nostrPubkey,
    String? title,
    String? description,
    List<String>? hashtags,
    void Function(double progress)? onProgress,
  }) async {
    Log.info('🚀 === DIRECT UPLOAD SERVICE STARTED ===',
        name: 'DirectUploadService', category: LogCategory.system);
    Log.info(
        '📱 Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        name: 'DirectUploadService',
        category: LogCategory.system);
    Log.info('📁 Video path: ${videoFile.path}',
        name: 'DirectUploadService', category: LogCategory.system);
    Log.info('📊 File exists: ${videoFile.existsSync()}',
        name: 'DirectUploadService', category: LogCategory.system);
    if (videoFile.existsSync()) {
      Log.info(
          '📊 File size: ${videoFile.lengthSync()} bytes (${(videoFile.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)',
          name: 'DirectUploadService',
          category: LogCategory.system);
      // Check if file is readable
      try {
        final testRead = videoFile.openRead();
        await testRead.first.timeout(Duration(seconds: 1)).catchError((e) {
          Log.warning('⚠️ File might not be readable: $e',
              name: 'DirectUploadService', category: LogCategory.system);
          return Uint8List(0);
        });
        Log.info('✅ File is readable',
            name: 'DirectUploadService', category: LogCategory.system);
      } catch (e) {
        Log.error('❌ Cannot read file: $e',
            name: 'DirectUploadService', category: LogCategory.system);
        return DirectUploadResult.failure('Cannot read video file: $e');
      }
    } else {
      Log.error('❌ VIDEO FILE DOES NOT EXIST!',
          name: 'DirectUploadService', category: LogCategory.system);
      return DirectUploadResult.failure(
          'Video file does not exist at path: ${videoFile.path}');
    }

    // First check backend connectivity
    Log.info('🏥 Checking backend health...',
        name: 'DirectUploadService', category: LogCategory.system);
    final isHealthy = await _checkBackendHealth();
    if (!isHealthy) {
      Log.error('❌ Backend is not accessible, aborting upload',
          name: 'DirectUploadService', category: LogCategory.system);
      return DirectUploadResult.failure(
          'Backend service is not accessible. Please check your internet connection.');
    }
    Log.info('✅ Backend is healthy, proceeding with upload',
        name: 'DirectUploadService', category: LogCategory.system);

    String? videoId;

    try {
      // Generate a temporary ID for progress tracking
      videoId = DateTime.now().millisecondsSinceEpoch.toString();

      // Setup progress tracking
      final progressController = StreamController<double>.broadcast();
      _progressControllers[videoId] = progressController;

      if (onProgress != null) {
        final subscription = progressController.stream.listen(onProgress);
        _progressSubscriptions[videoId] = subscription;
      }

      // Skip SHA256 calculation - these are always new recordings
      progressController.add(0.05); // Jump to 5%
      Log.debug('📱 Processing new recording for upload',
          name: 'DirectUploadService', category: LogCategory.system);

      // Step 2: Generate thumbnail before upload
      progressController.add(0.08); // 8% for thumbnail generation
      Log.debug('📱 Generating video thumbnail...',
          name: 'DirectUploadService', category: LogCategory.system);

      Uint8List? thumbnailBytes;
      try {
        thumbnailBytes = await VideoThumbnailService.extractThumbnailBytes(
          videoPath: videoFile.path,
          timeMs: 500, // Extract at 500ms
          quality: 80,
        );

        if (thumbnailBytes != null) {
          Log.info(
              'Thumbnail generated: ${(thumbnailBytes.length / 1024).toStringAsFixed(2)}KB',
              name: 'DirectUploadService',
              category: LogCategory.system);
        } else {
          Log.error('Failed to generate thumbnail, continuing without it',
              name: 'DirectUploadService', category: LogCategory.system);
        }
      } catch (e) {
        Log.error(
            'Thumbnail generation error: $e, continuing without thumbnail',
            name: 'DirectUploadService',
            category: LogCategory.system);
      }

      // Create multipart request for direct CF Workers upload
      final url = '$_baseUrl/api/upload';
      final uri = Uri.parse(url);

      final request = http.MultipartRequest('POST', uri);

      // Add authorization headers
      final headers = await _getAuthHeaders(url);
      request.headers.addAll(headers);

      // Add required fields
      request.fields['pubkey'] = nostrPubkey;

      // Add video file with progress tracking
      final fileLength = await videoFile.length();
      final stream = videoFile.openRead();

      // Create a progress-tracking stream
      var bytesUploaded = 0;
      var lastProgressLog = 0;
      final progressStream = stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesUploaded += data.length;
            final progress = bytesUploaded / fileLength;
            progressController.add(progress * 0.9); // 0-90% for upload

            // Log progress every 10%
            final progressPercent = (progress * 100).round();
            if (progressPercent >= lastProgressLog + 10) {
              lastProgressLog = progressPercent;
              Log.info(
                  '📊 Upload progress: $progressPercent% ($bytesUploaded / $fileLength bytes)',
                  name: 'DirectUploadService',
                  category: LogCategory.system);
            }

            sink.add(data);
          },
        ),
      );

      final filename = videoFile.path.split('/').last;
      final contentType = _getContentType(filename);

      final multipartFile = http.MultipartFile(
        'file',
        progressStream,
        fileLength,
        filename: filename,
        contentType: contentType,
      );
      request.files.add(multipartFile);

      // Add thumbnail to the same request if available
      if (thumbnailBytes != null) {
        final thumbnailFile = http.MultipartFile.fromBytes(
          'thumbnail',
          thumbnailBytes,
          filename: 'thumbnail.jpg',
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(thumbnailFile);
        Log.verbose('Added thumbnail to upload request',
            name: 'DirectUploadService', category: LogCategory.system);
      }

      // Add optional metadata fields
      if (title != null) request.fields['title'] = title;
      if (description != null) request.fields['description'] = description;
      if (hashtags != null && hashtags.isNotEmpty) {
        request.fields['hashtags'] = hashtags.join(',');
      }

      // Send request
      progressController.add(0.10); // 10% - Starting main upload

      Log.info('📤 Sending upload request to: $url',
          name: 'DirectUploadService', category: LogCategory.system);
      Log.info('📦 Request method: ${request.method}',
          name: 'DirectUploadService', category: LogCategory.system);
      Log.info('📦 Request files: ${request.files.length} files',
          name: 'DirectUploadService', category: LogCategory.system);
      for (var file in request.files) {
        Log.info(
            '  - Field: ${file.field}, Filename: ${file.filename}, Length: ${file.length} bytes',
            name: 'DirectUploadService',
            category: LogCategory.system);
      }
      Log.debug('Request headers: ${request.headers}',
          name: 'DirectUploadService', category: LogCategory.system);
      Log.debug('Request fields: ${request.fields}',
          name: 'DirectUploadService', category: LogCategory.system);

      http.StreamedResponse streamedResponse;
      try {
        Log.info('🔄 Attempting to send HTTP request...',
            name: 'DirectUploadService', category: LogCategory.system);
        streamedResponse = await _httpClient.send(request).timeout(
          const Duration(minutes: 5),
          onTimeout: () {
            Log.error('⏱️ Upload timed out after 5 minutes',
                name: 'DirectUploadService', category: LogCategory.system);
            throw TimeoutException('Upload timed out after 5 minutes');
          },
        );
        Log.info('✅ HTTP request sent successfully',
            name: 'DirectUploadService', category: LogCategory.system);
      } catch (e, stack) {
        Log.error('❌ Failed to send HTTP request: $e',
            name: 'DirectUploadService', category: LogCategory.system);
        Log.error('Stack trace: $stack',
            name: 'DirectUploadService', category: LogCategory.system);

        if (e is SocketException) {
          Log.error(
              '🌐 Network error details: ${e.message}, OSError: ${e.osError}',
              name: 'DirectUploadService',
              category: LogCategory.system);
          throw Exception('Network connection failed: ${e.message}');
        } else if (e is TimeoutException) {
          Log.error('⏱️ Upload timeout: ${e.message}',
              name: 'DirectUploadService', category: LogCategory.system);
          throw Exception('Upload timed out: ${e.message}');
        } else {
          Log.error('🚨 Request send error type: ${e.runtimeType}',
              name: 'DirectUploadService', category: LogCategory.system);
          rethrow;
        }
      }

      Log.info('📡 Upload request sent, status: ${streamedResponse.statusCode}',
          name: 'DirectUploadService', category: LogCategory.system);

      progressController.add(0.95); // Upload complete, processing response

      final response = await http.Response.fromStream(streamedResponse);

      Log.debug('📥 Response body: ${response.body}',
          name: 'DirectUploadService', category: LogCategory.system);

      progressController.add(1); // Complete

      // Cleanup progress controller and subscription
      _progressControllers.remove(videoId);
      final subscription = _progressSubscriptions.remove(videoId);
      await subscription?.cancel();
      await progressController.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Log.info('Direct upload successful',
            name: 'DirectUploadService', category: LogCategory.system);
        Log.debug('📱 Response: $data',
            name: 'DirectUploadService', category: LogCategory.system);

        // Updated NIP-96 response structure
        if (data['status'] == 'success') {
          // Extract video ID from URL if not provided separately
          final cdnUrl = data['download_url'] ?? data['url'];
          String? videoId = data['video_id'];

          // Extract video ID from CDN URL if not provided
          if (videoId == null && cdnUrl != null) {
            final uri = Uri.parse(cdnUrl);
            final pathSegments = uri.pathSegments;
            if (pathSegments.isNotEmpty) {
              videoId = pathSegments.last;
            }
          }

          final thumbnailUrl = data['thumbnail_url'] ?? data['thumb_url'];
          Log.info('📸 Thumbnail URL from backend: $thumbnailUrl',
              name: 'DirectUploadService', category: LogCategory.system);

          return DirectUploadResult.success(
            videoId: videoId ?? 'unknown',
            cdnUrl: cdnUrl,
            thumbnailUrl: thumbnailUrl, // Get thumbnail URL from response
            metadata: {
              'sha256': data['sha256'],
              'size': data['size'],
              'type': data['type'],
              'dimensions': data['dimensions'],
              'url': data['url'],
              'thumbnail_url': thumbnailUrl,
            },
          );
        } else {
          final errorMsg = data['message'] ?? data['error'] ?? 'Upload failed';
          Log.error('$errorMsg',
              name: 'DirectUploadService', category: LogCategory.system);
          return DirectUploadResult.failure(errorMsg);
        }
      } else {
        final errorBody = response.body;
        Log.error(
            'Upload failed with status ${response.statusCode}: $errorBody',
            name: 'DirectUploadService',
            category: LogCategory.system);
        try {
          final errorData = jsonDecode(errorBody);
          final errorMsg =
              'Upload failed: ${errorData['message'] ?? errorData['error'] ?? 'Unknown error'}';
          return DirectUploadResult.failure(errorMsg);
        } catch (_) {
          return DirectUploadResult.failure(
              'Upload failed with status ${response.statusCode}');
        }
      }
    } catch (e, stackTrace) {
      Log.error('🚨 Upload error: $e',
          name: 'DirectUploadService', category: LogCategory.system);
      Log.error('Error type: ${e.runtimeType}',
          name: 'DirectUploadService', category: LogCategory.system);
      Log.error('Stack trace: $stackTrace',
          name: 'DirectUploadService', category: LogCategory.system);

      // Clean up progress tracking on error
      if (videoId != null) {
        final subscription = _progressSubscriptions.remove(videoId);
        final controller = _progressControllers.remove(videoId);
        await subscription?.cancel();
        await controller?.close();
      }

      // Build detailed error message for user display
      String detailedError = 'Upload failed: ${e.toString()}';

      // Provide user-friendly error messages based on error type
      if (e is SocketException) {
        detailedError = '🌐 Network Error: ${e.message}';
        if (e.osError != null) {
          detailedError += '\nOS Error: ${e.osError}';
        }
      } else if (e is TimeoutException) {
        detailedError =
            '⏱️ Upload timed out\nCheck your connection and try again';
      } else if (e.toString().contains('400')) {
        detailedError =
            '❌ Server rejected upload (400)\nCheck file format/size';
      } else if (e.toString().contains('401')) {
        detailedError = '🔐 Authentication failed\nTry signing in again';
      } else if (e.toString().contains('413')) {
        detailedError = '📦 File too large\nMax size exceeded';
      } else if (e.toString().contains('500')) {
        detailedError = '⚠️ Server error\nPlease try again later';
      } else if (e.toString().contains('Network connection failed')) {
        detailedError = e.toString(); // Already formatted
      }

      return DirectUploadResult.failure(detailedError);
    }
  }

  /// Get authorization headers for backend requests
  Future<Map<String, String>> _getAuthHeaders(String url) async {
    Log.debug('🔐 Creating auth headers for URL: $url',
        name: 'DirectUploadService', category: LogCategory.system);

    final headers = <String, String>{
      'Accept': 'application/json',
    };

    // Add NIP-98 authentication if available
    if (_authService?.canCreateTokens == true) {
      Log.debug('AuthService available, creating NIP-98 token...',
          name: 'DirectUploadService', category: LogCategory.system);
      try {
        final authToken = await _authService!.createAuthToken(
          url: url,
          method: HttpMethod.post,
        );

        if (authToken != null) {
          headers['Authorization'] = authToken.authorizationHeader;
          Log.debug('✅ Added NIP-98 auth to upload request',
              name: 'DirectUploadService', category: LogCategory.system);
        } else {
          Log.error('❌ Failed to create NIP-98 auth token for upload',
              name: 'DirectUploadService', category: LogCategory.system);
        }
      } catch (e) {
        Log.error('❌ Error creating auth token: $e',
            name: 'DirectUploadService', category: LogCategory.system);
      }
    } else {
      Log.warning('⚠️ No authentication service available for upload',
          name: 'DirectUploadService', category: LogCategory.system);
    }

    return headers;
  }

  /// Cancel an ongoing upload
  Future<void> cancelUpload(String videoId) async {
    final controller = _progressControllers.remove(videoId);
    final subscription = _progressSubscriptions.remove(videoId);

    if (controller != null || subscription != null) {
      await subscription?.cancel();
      await controller?.close();
      Log.debug('Upload cancelled: $videoId',
          name: 'DirectUploadService', category: LogCategory.system);
    }
  }

  /// Get upload progress stream for a specific upload
  Stream<double>? getProgressStream(String videoId) =>
      _progressControllers[videoId]?.stream;

  /// Check if an upload is currently in progress
  bool isUploading(String videoId) => _progressControllers.containsKey(videoId);

  /// Dispose of resources (first dispose method - use the second one below instead)

  /// Check backend connectivity and health
  Future<bool> _checkBackendHealth() async {
    try {
      // Use NIP-96 info endpoint to check backend availability
      // since /health endpoint doesn't exist
      final nip96Url = AppConfig.nip96InfoUrl;
      Log.info('🏥 Checking backend availability at: $nip96Url',
          name: 'DirectUploadService', category: LogCategory.system);

      final response = await _httpClient.get(Uri.parse(nip96Url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Backend check timed out');
        },
      );

      if (response.statusCode == 200) {
        Log.info('✅ Backend is available and responding',
            name: 'DirectUploadService', category: LogCategory.system);
        return true;
      } else {
        Log.error(
            '❌ Backend check failed: ${response.statusCode} - ${response.body}',
            name: 'DirectUploadService',
            category: LogCategory.system);
        return false;
      }
    } catch (e) {
      Log.error('❌ Backend connectivity error: $e',
          name: 'DirectUploadService', category: LogCategory.system);
      return false;
    }
  }

  /// Upload a profile picture image directly to CF Workers
  Future<DirectUploadResult> uploadProfilePicture({
    required File imageFile,
    required String nostrPubkey,
    void Function(double progress)? onProgress,
  }) async {
    Log.debug('Starting profile picture upload for: ${imageFile.path}',
        name: 'DirectUploadService', category: LogCategory.system);

    String? uploadId;

    try {
      // Generate a temporary ID for progress tracking
      uploadId = DateTime.now().millisecondsSinceEpoch.toString();

      // Setup progress tracking
      final progressController = StreamController<double>.broadcast();
      _progressControllers[uploadId] = progressController;

      if (onProgress != null) {
        final subscription = progressController.stream.listen(onProgress);
        _progressSubscriptions[uploadId] = subscription;
      }

      // Create multipart request for image upload (using same endpoint as videos)
      final url = '$_baseUrl/api/upload';
      final uri = Uri.parse(url);

      final request = http.MultipartRequest('POST', uri);

      // Add authorization headers
      final headers = await _getAuthHeaders(url);
      request.headers.addAll(headers);

      // Add image file with progress tracking
      final fileLength = await imageFile.length();
      final stream = imageFile.openRead();

      // Create a progress-tracking stream
      var bytesUploaded = 0;
      var lastProgressLog = 0;
      final progressStream = stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesUploaded += data.length;
            final progress = bytesUploaded / fileLength;
            progressController.add(progress * 0.9); // 0-90% for upload

            // Log progress every 10%
            final progressPercent = (progress * 100).round();
            if (progressPercent >= lastProgressLog + 10) {
              lastProgressLog = progressPercent;
              Log.info(
                  '📊 Upload progress: $progressPercent% ($bytesUploaded / $fileLength bytes)',
                  name: 'DirectUploadService',
                  category: LogCategory.system);
            }

            sink.add(data);
          },
        ),
      );

      final filename = imageFile.path.split('/').last;
      final contentType = _getImageContentType(filename);

      final multipartFile = http.MultipartFile(
        'file',
        progressStream,
        fileLength,
        filename: filename,
        contentType: contentType,
      );
      request.files.add(multipartFile);

      // Add metadata
      request.fields['type'] = 'profile_picture';
      request.fields['pubkey'] = nostrPubkey;

      // Send request
      progressController.add(0.10); // 10% - Starting upload

      final streamedResponse = await _httpClient.send(request);

      progressController.add(0.95); // Upload complete, processing response

      final response = await http.Response.fromStream(streamedResponse);

      progressController.add(1); // Complete

      // Cleanup progress controller and subscription
      _progressControllers.remove(uploadId);
      final subscription = _progressSubscriptions.remove(uploadId);
      await subscription?.cancel();
      await progressController.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Log.info('Profile picture upload successful',
            name: 'DirectUploadService', category: LogCategory.system);
        Log.debug('📱 Response: $data',
            name: 'DirectUploadService', category: LogCategory.system);

        if (data['status'] == 'success') {
          final cdnUrl = data['url'] ?? data['download_url'];

          return DirectUploadResult.success(
            videoId: uploadId,
            cdnUrl: cdnUrl,
            metadata: data,
          );
        } else {
          throw DirectUploadException(
            'Upload failed: ${data['message'] ?? 'Unknown error'}',
            code: 'UPLOAD_FAILED',
          );
        }
      } else {
        throw DirectUploadException(
          'HTTP ${response.statusCode}: ${response.body}',
          code: 'HTTP_ERROR_${response.statusCode}',
        );
      }
    } catch (e, stack) {
      Log.error('Profile picture upload error: $e',
          name: 'DirectUploadService', category: LogCategory.system);
      Log.verbose('Stack trace: $stack',
          name: 'DirectUploadService', category: LogCategory.system);

      // Cleanup on error
      if (uploadId != null) {
        _progressControllers.remove(uploadId);
        final subscription = _progressSubscriptions.remove(uploadId);
        await subscription?.cancel();
      }

      if (e is DirectUploadException) {
        return DirectUploadResult.failure(e.message);
      }

      return DirectUploadResult.failure(e.toString());
    }
  }

  /// Get current uploads in progress
  List<String> get activeUploads => _progressControllers.keys.toList();

  /// Determine content type based on file extension
  MediaType _getContentType(String filename) {
    final extension = filename.toLowerCase().split('.').last;

    switch (extension) {
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'avi':
        return MediaType('video', 'x-msvideo');
      case 'mkv':
        return MediaType('video', 'x-matroska');
      case 'webm':
        return MediaType('video', 'webm');
      case 'm4v':
        return MediaType('video', 'x-m4v');
      default:
        // Default to mp4 for unknown video files
        Log.warning(
            'Unknown video file extension: $extension, defaulting to mp4',
            name: 'DirectUploadService',
            category: LogCategory.system);
        return MediaType('video', 'mp4');
    }
  }

  /// Determine image content type based on file extension
  MediaType _getImageContentType(String filename) {
    final extension = filename.toLowerCase().split('.').last;

    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
      case 'heif':
        return MediaType('image', 'heic');
      default:
        // Default to jpeg for unknown image files
        Log.warning(
            'Unknown image file extension: $extension, defaulting to jpeg',
            name: 'DirectUploadService',
            category: LogCategory.system);
        return MediaType('image', 'jpeg');
    }
  }

  // SHA256 and deduplication methods removed - not needed for new recordings

  void dispose() {
    // Cancel all active uploads and subscriptions
    for (final subscription in _progressSubscriptions.values) {
      subscription.cancel();
    }
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressSubscriptions.clear();
    _progressControllers.clear();
  }
}

/// Exception thrown by DirectUploadService
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class DirectUploadException implements Exception {
  const DirectUploadException(
    this.message, {
    this.code,
    this.originalError,
  });
  final String message;
  final String? code;
  final dynamic originalError;

  @override
  String toString() => 'DirectUploadException: $message';
}
