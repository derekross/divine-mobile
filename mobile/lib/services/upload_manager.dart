// ABOUTME: Service for managing video upload state and local persistence
// ABOUTME: Handles upload queue, retries, and coordination between UI and Cloudinary service

import 'dart:async';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/services/circuit_breaker_service.dart';
import 'package:openvine/services/blossom_upload_service.dart';
import 'package:openvine/services/cloudflare_stream_service.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/upload_initialization_helper.dart';
import 'package:openvine/utils/async_utils.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Upload retry configuration
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class UploadRetryConfig {
  const UploadRetryConfig({
    this.maxRetries = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
    this.networkTimeout = const Duration(minutes: 10),
  });
  final int maxRetries;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final Duration networkTimeout;
}

/// Upload performance metrics
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class UploadMetrics {
  const UploadMetrics({
    required this.uploadId,
    required this.startTime,
    required this.retryCount,
    required this.fileSizeMB,
    required this.wasSuccessful,
    this.endTime,
    this.uploadDuration,
    this.throughputMBps,
    this.errorCategory,
  });
  final String uploadId;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? uploadDuration;
  final int retryCount;
  final double fileSizeMB;
  final double? throughputMBps;
  final String? errorCategory;
  final bool wasSuccessful;
}

/// Upload target options
enum UploadTarget {
  openvineBackend, // Default - api.openvine.co
  blossomServer,   // User-configured Blossom server
  cloudflareStream, // Direct to Cloudflare Stream
}

/// Manages video uploads and their persistent state with enhanced reliability
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class UploadManager {
  UploadManager({
    required DirectUploadService uploadService,
    BlossomUploadService? blossomService,
    CloudflareStreamService? streamService,
    VideoCircuitBreaker? circuitBreaker,
    UploadRetryConfig? retryConfig,
  })  : _uploadService = uploadService,
        _blossomService = blossomService,
        _streamService = streamService,
        _circuitBreaker = circuitBreaker ?? VideoCircuitBreaker(),
        _retryConfig = retryConfig ?? const UploadRetryConfig();
  // Removed unused _uploadsBoxName constant
  static const String _uploadTargetKey = 'upload_target';

  // Core services
  Box<PendingUpload>? _uploadsBox;
  final DirectUploadService _uploadService;
  final BlossomUploadService? _blossomService;
  final CloudflareStreamService? _streamService;
  final VideoCircuitBreaker _circuitBreaker;
  final UploadRetryConfig _retryConfig;

  // State tracking
  final Map<String, StreamSubscription<double>> _progressSubscriptions = {};
  final Map<String, UploadMetrics> _uploadMetrics = {};
  final Map<String, Timer> _retryTimers = {};

  bool _isInitialized = false;

  /// Check if the upload manager is initialized
  bool get isInitialized => _isInitialized && _uploadsBox != null;

  /// Get the current upload target
  Future<UploadTarget> getUploadTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final targetIndex = prefs.getInt(_uploadTargetKey) ?? 0;
    return UploadTarget.values[targetIndex];
  }

  /// Set the upload target
  Future<void> setUploadTarget(UploadTarget target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_uploadTargetKey, target.index);
    Log.info('Upload target set to: ${target.name}',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Check if Cloudflare Stream is available
  bool get isCloudflareStreamAvailable => _streamService != null;

  /// Check if Blossom is available and configured
  Future<bool> isBlossomAvailable() async {
    if (_blossomService == null) return false;
    return await _blossomService!.isBlossomEnabled();
  }

  /// Initialize the upload manager and load persisted uploads
  /// Uses robust initialization with retry logic and recovery strategies
  Future<void> initialize() async {
    if (_isInitialized && _uploadsBox != null && _uploadsBox!.isOpen) {
      Log.info('UploadManager already initialized',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    Log.info('🚀 Initializing UploadManager with robust retry logic',
        name: 'UploadManager', category: LogCategory.video);

    try {
      // Use the robust initialization helper
      _uploadsBox = await UploadInitializationHelper.initializeUploadsBox(
        forceReinit: !_isInitialized,
      );

      if (_uploadsBox == null || !_uploadsBox!.isOpen) {
        throw Exception(
            'Failed to initialize uploads box after all recovery attempts');
      }

      _isInitialized = true;

      Log.info(
          '✅ UploadManager initialized successfully with ${_uploadsBox!.length} existing uploads',
          name: 'UploadManager',
          category: LogCategory.video);

      // Clean up any problematic uploads first
      await cleanupProblematicUploads();

      // Resume any interrupted uploads
      await _resumeInterruptedUploads();
    } catch (e, stackTrace) {
      _isInitialized = false;
      _uploadsBox = null;

      // Log the error but don't rethrow immediately - the helper already retried
      Log.error('❌ Failed to initialize UploadManager after all retries: $e',
          name: 'UploadManager', category: LogCategory.video);
      Log.verbose('📱 Stack trace: $stackTrace',
          name: 'UploadManager', category: LogCategory.video);

      // Store the error for later retry
      _initializationError = e;

      // Don't rethrow - allow the app to continue and retry on demand
      // rethrow;
    }
  }

  // Store initialization error for potential retry
  dynamic _initializationError;

  /// Get all pending uploads
  List<PendingUpload> get pendingUploads {
    if (_uploadsBox == null) return [];
    return _uploadsBox!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Newest first
  }

  /// Get uploads by status
  List<PendingUpload> getUploadsByStatus(UploadStatus status) =>
      pendingUploads.where((upload) => upload.status == status).toList();

  /// Get a specific upload by ID
  PendingUpload? getUpload(String id) => _uploadsBox?.get(id);

  /// Get an upload by file path
  PendingUpload? getUploadByFilePath(String filePath) {
    try {
      return pendingUploads.firstWhere(
        (upload) => upload.localVideoPath == filePath,
      );
    } catch (e) {
      return null;
    }
  }

  /// Update an upload's status to published with Nostr event ID
  Future<void> markUploadPublished(String uploadId, String nostrEventId) async {
    final upload = getUpload(uploadId);
    if (upload != null) {
      final updatedUpload = upload.copyWith(
        status: UploadStatus.published,
        nostrEventId: nostrEventId,
        completedAt: DateTime.now(),
      );

      await _updateUpload(updatedUpload);
      Log.info('Upload marked as published: $uploadId -> $nostrEventId',
          name: 'UploadManager', category: LogCategory.video);
    } else {
      Log.warning('Could not find upload to mark as published: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
    }
  }

  /// Update an upload's status to ready for publishing
  Future<void> markUploadReadyToPublish(
      String uploadId, String cloudinaryPublicId) async {
    final upload = getUpload(uploadId);
    if (upload != null) {
      final updatedUpload = upload.copyWith(
        status: UploadStatus.readyToPublish,
        cloudinaryPublicId: cloudinaryPublicId,
      );

      await _updateUpload(updatedUpload);
      Log.debug('Upload marked as ready to publish: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
    }
  }

  /// Get uploads that are ready for background processing
  List<PendingUpload> get uploadsReadyForProcessing =>
      getUploadsByStatus(UploadStatus.processing);

  /// Start a new video upload
  Future<PendingUpload> startUpload({
    required File videoFile,
    required String nostrPubkey,
    String? thumbnailPath,
    String? title,
    String? description,
    List<String>? hashtags,
    int? videoWidth,
    int? videoHeight,
    Duration? videoDuration,
  }) async {
    Log.info('🚀 === STARTING UPLOAD ===',
        name: 'UploadManager', category: LogCategory.video);

    // Ensure initialization with robust retry
    if (!isInitialized || _uploadsBox == null || !_uploadsBox!.isOpen) {
      Log.warning(
          'UploadManager not ready, attempting robust initialization...',
          name: 'UploadManager',
          category: LogCategory.video);

      try {
        // Use the robust helper directly for immediate retry
        _uploadsBox = await UploadInitializationHelper.initializeUploadsBox(
          forceReinit: true,
        );

        if (_uploadsBox != null && _uploadsBox!.isOpen) {
          _isInitialized = true;
          _initializationError = null;
          Log.info('✅ Robust initialization successful',
              name: 'UploadManager', category: LogCategory.video);
        } else {
          throw Exception('Box initialization returned null or closed box');
        }
      } catch (e) {
        Log.error('❌ Robust initialization failed: $e',
            name: 'UploadManager', category: LogCategory.video);

        // Check if circuit breaker is active
        final debugState = UploadInitializationHelper.getDebugState();
        if (debugState['circuitBreakerActive'] == true) {
          throw Exception(
              'Upload service temporarily unavailable - too many failures. Please try again later.');
        }

        throw Exception(
            'Failed to initialize upload storage after multiple retries: $e');
      }
    }

    Log.info('📁 Video path: ${videoFile.path}',
        name: 'UploadManager', category: LogCategory.video);
    Log.info('📊 File exists: ${videoFile.existsSync()}',
        name: 'UploadManager', category: LogCategory.video);
    if (videoFile.existsSync()) {
      Log.info('📊 File size: ${videoFile.lengthSync()} bytes',
          name: 'UploadManager', category: LogCategory.video);
    }
    Log.info(
        '👤 Nostr pubkey: ${nostrPubkey.length > 8 ? '${nostrPubkey.substring(0, 8)}...' : nostrPubkey}',
        name: 'UploadManager',
        category: LogCategory.video);
    Log.info('📝 Title: $title',
        name: 'UploadManager', category: LogCategory.video);
    Log.info('🏷️ Hashtags: $hashtags',
        name: 'UploadManager', category: LogCategory.video);

    // Create pending upload record
    Log.info('📦 Creating PendingUpload record...',
        name: 'UploadManager', category: LogCategory.video);
    final upload = PendingUpload.create(
      localVideoPath: videoFile.path,
      nostrPubkey: nostrPubkey,
      thumbnailPath: thumbnailPath,
      title: title,
      description: description,
      hashtags: hashtags,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      videoDuration: videoDuration,
    );
    Log.info('✅ Created upload with ID: ${upload.id}',
        name: 'UploadManager', category: LogCategory.video);

    // Save to local storage
    Log.info('💾 Saving upload to local storage...',
        name: 'UploadManager', category: LogCategory.video);
    await _saveUpload(upload);
    Log.info('✅ Upload saved to storage',
        name: 'UploadManager', category: LogCategory.video);

    // Start the upload process
    Log.info('🔄 Starting background upload process...',
        name: 'UploadManager', category: LogCategory.video);

    // Start upload in background but catch any immediate errors
    _performUpload(upload).catchError((error) {
      Log.error('❌ Background upload failed to start: $error',
          name: 'UploadManager', category: LogCategory.video);
    });

    Log.info('✅ Upload initiated with ID: ${upload.id}',
        name: 'UploadManager', category: LogCategory.video);
    return upload;
  }

  /// Perform upload with circuit breaker and retry logic
  Future<void> _performUpload(PendingUpload upload) async {
    Log.info('🏃 === PERFORM UPLOAD STARTED ===',
        name: 'UploadManager', category: LogCategory.video);
    Log.info('🆔 Upload ID: ${upload.id}',
        name: 'UploadManager', category: LogCategory.video);

    final startTime = DateTime.now();
    final videoFile = File(upload.localVideoPath);

    Log.info('📁 Checking video file: ${upload.localVideoPath}',
        name: 'UploadManager', category: LogCategory.video);
    Log.info('📊 File exists: ${videoFile.existsSync()}',
        name: 'UploadManager', category: LogCategory.video);

    if (!videoFile.existsSync()) {
      Log.error('❌ VIDEO FILE DOES NOT EXIST!',
          name: 'UploadManager', category: LogCategory.video);
      await _handleUploadFailure(upload, Exception('Video file not found'));
      return;
    }

    // Initialize metrics
    final fileSizeMB = videoFile.lengthSync() / (1024 * 1024);
    Log.info('📊 File size: ${fileSizeMB.toStringAsFixed(2)} MB',
        name: 'UploadManager', category: LogCategory.video);

    _uploadMetrics[upload.id] = UploadMetrics(
      uploadId: upload.id,
      startTime: startTime,
      retryCount: upload.retryCount ?? 0,
      fileSizeMB: fileSizeMB,
      wasSuccessful: false,
    );

    try {
      Log.info('🔁 Starting upload with retry logic...',
          name: 'UploadManager', category: LogCategory.video);
      await _performUploadWithRetry(upload, videoFile);
    } catch (e) {
      Log.error('❌ Upload failed: $e',
          name: 'UploadManager', category: LogCategory.video);
      await _handleUploadFailure(upload, e);
    }
  }

  /// Perform upload with exponential backoff retry using proper async patterns
  Future<void> _performUploadWithRetry(
      PendingUpload upload, File videoFile) async {
    try {
      await AsyncUtils.retryWithBackoff(
        operation: () async {
          // Check circuit breaker state
          if (!_circuitBreaker.allowRequests) {
            throw Exception('Circuit breaker is open - service unavailable');
          }

          // Update status based on current retry count
          final currentRetry = upload.retryCount ?? 0;
          Log.warning(
              'Upload attempt ${currentRetry + 1}/${_retryConfig.maxRetries + 1} for ${upload.id}',
              name: 'UploadManager',
              category: LogCategory.video);

          await _updateUpload(
            upload.copyWith(
              status: currentRetry == 0
                  ? UploadStatus.uploading
                  : UploadStatus.retrying,
              retryCount: currentRetry,
            ),
          );

          // Validate file still exists
          if (!videoFile.existsSync()) {
            throw Exception('Video file not found: ${upload.localVideoPath}');
          }

          // Execute upload with timeout
          final result = await _executeUploadWithTimeout(upload, videoFile);

          // Success - record metrics and complete
          await _handleUploadSuccess(upload, result);
          _circuitBreaker.recordSuccess(upload.localVideoPath);
        },
        maxRetries: _retryConfig.maxRetries,
        baseDelay: _retryConfig.initialDelay,
        maxDelay: _retryConfig.maxDelay,
        backoffMultiplier: _retryConfig.backoffMultiplier,
        retryWhen: (error) {
          _circuitBreaker.recordFailure(
              upload.localVideoPath, error.toString());
          return _isRetriableError(error);
        },
        debugName: 'Upload-${upload.id}',
      );
    } catch (e) {
      Log.error('Upload failed after all retries: $e',
          name: 'UploadManager', category: LogCategory.video);
      rethrow;
    }
  }

  /// Execute upload with timeout and progress tracking
  Future<dynamic> _executeUploadWithTimeout(
      PendingUpload upload, File videoFile) async {
    Log.info('📤 === EXECUTING UPLOAD ===',
        name: 'UploadManager', category: LogCategory.video);
    Log.info('📁 Video: ${videoFile.path}',
        name: 'UploadManager', category: LogCategory.video);
    Log.info(
        '👤 Pubkey: ${upload.nostrPubkey.length > 8 ? '${upload.nostrPubkey.substring(0, 8)}...' : upload.nostrPubkey}',
        name: 'UploadManager',
        category: LogCategory.video);
    Log.info('📝 Title: ${upload.title}',
        name: 'UploadManager', category: LogCategory.video);
    Log.info('⏱️ Timeout: ${_retryConfig.networkTimeout.inMinutes} minutes',
        name: 'UploadManager', category: LogCategory.video);

    try {
      // Choose upload service based on configured target
      final uploadTarget = await getUploadTarget();
      dynamic result;

      switch (uploadTarget) {
        case UploadTarget.cloudflareStream:
          if (_streamService != null) {
            Log.info('🎬 Using Cloudflare Stream service',
                name: 'UploadManager', category: LogCategory.video);

            // Generate a unique Vine ID for this upload
            final vineId = 'vine_${upload.id}_${DateTime.now().millisecondsSinceEpoch}';

            final streamResult = await _streamService!.migrateToStream(
              videoFile: videoFile,
              vineId: vineId,
              title: upload.title,
              description: upload.description,
              hashtags: upload.hashtags,
              generateBlurhash: true,
              onProgress: (progress) {
                Log.info(
                    '📊 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
                    name: 'UploadManager',
                    category: LogCategory.video);
                _updateUploadProgress(upload.id, progress);
              },
            ).timeout(
              _retryConfig.networkTimeout,
              onTimeout: () {
                Log.error('⏱️ Upload timed out!',
                    name: 'UploadManager', category: LogCategory.video);
                throw TimeoutException(
                    'Upload timed out after ${_retryConfig.networkTimeout.inMinutes} minutes');
              },
            );

            // Convert CloudflareStreamResult to DirectUploadResult format
            result = DirectUploadResult.success(
              videoId: streamResult.streamUid ?? vineId,
              cdnUrl: streamResult.hlsUrl ?? '',
              thumbnailUrl: streamResult.thumbnailUrl,
              metadata: {
                ...?streamResult.metadata,
                'mp4Url': streamResult.mp4Url,
                'dashUrl': streamResult.dashUrl,
                'animatedThumbnailUrl': streamResult.animatedThumbnailUrl,
                'blurhash': streamResult.blurhash,
              },
            );
          } else {
            Log.warning('Cloudflare Stream not available, falling back to backend',
                name: 'UploadManager', category: LogCategory.video);
            result = await _uploadToBackend(upload, videoFile);
          }
          break;

        case UploadTarget.blossomServer:
          if (_blossomService != null) {
            final isBlossomEnabled = await _blossomService!.isBlossomEnabled();
            if (isBlossomEnabled) {
              final blossomServer = await _blossomService!.getBlossomServer();
              if (blossomServer != null && blossomServer.isNotEmpty) {
                Log.info('🌸 Using Blossom upload service to: $blossomServer',
                    name: 'UploadManager', category: LogCategory.video);
                result = await _blossomService!.uploadVideo(
                  videoFile: videoFile,
                  nostrPubkey: upload.nostrPubkey,
                  title: upload.title ?? '',
                  description: upload.description,
                  hashtags: upload.hashtags,
                  onProgress: (progress) {
                    Log.info(
                        '📊 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
                        name: 'UploadManager',
                        category: LogCategory.video);
                    _updateUploadProgress(upload.id, progress);
                  },
                ).timeout(
                  _retryConfig.networkTimeout,
                  onTimeout: () {
                    Log.error('⏱️ Upload timed out!',
                        name: 'UploadManager', category: LogCategory.video);
                    throw TimeoutException(
                        'Upload timed out after ${_retryConfig.networkTimeout.inMinutes} minutes');
                  },
                );
              } else {
                Log.warning('⚠️ Blossom enabled but no server configured, using backend',
                    name: 'UploadManager', category: LogCategory.video);
                result = await _uploadToBackend(upload, videoFile);
              }
            } else {
              Log.info('☁️ Blossom disabled, using backend',
                  name: 'UploadManager', category: LogCategory.video);
              result = await _uploadToBackend(upload, videoFile);
            }
          } else {
            Log.warning('Blossom service not available, using backend',
                name: 'UploadManager', category: LogCategory.video);
            result = await _uploadToBackend(upload, videoFile);
          }
          break;

        case UploadTarget.openvineBackend:
          result = await _uploadToBackend(upload, videoFile);
          break;
      }

      Log.info('✅ Upload execution completed',
          name: 'UploadManager', category: LogCategory.video);
      return result;
    } catch (e) {
      Log.error('❌ Upload execution failed: $e',
          name: 'UploadManager', category: LogCategory.video);
      rethrow;
    }
  }

  /// Handle successful upload
  Future<void> _handleUploadSuccess(
      PendingUpload upload, dynamic result) async {
    final endTime = DateTime.now();
    final metrics = _uploadMetrics[upload.id];

    if (result.success == true) {
      // Create updated upload with success metadata
      final updatedUpload = _createSuccessfulUpload(upload, result);
      await _updateUpload(updatedUpload);

      // Record successful metrics
      if (metrics != null) {
        final updatedMetrics =
            _createSuccessMetrics(metrics, endTime, upload.retryCount ?? 0);
        _uploadMetrics[upload.id] = updatedMetrics;

        // Log success with formatted output
        _logUploadSuccess(result, updatedMetrics);
      }

      // Notify that upload is ready for immediate publishing
    } else {
      throw Exception(
          result.errorMessage ?? 'Upload failed with unknown error');
    }
  }

  /// Handle upload failure
  Future<void> _handleUploadFailure(PendingUpload upload, dynamic error) async {
    final endTime = DateTime.now();
    final metrics = _uploadMetrics[upload.id];
    final errorCategory = _categorizeError(error);

    Log.error('Upload failed for ${upload.id}: $error',
        name: 'UploadManager', category: LogCategory.video);
    Log.error('Error category: $errorCategory',
        name: 'UploadManager', category: LogCategory.video);

    await _updateUpload(
      upload.copyWith(
        status: UploadStatus.failed,
        errorMessage: error.toString(),
        retryCount: upload.retryCount ?? 0,
      ),
    );

    // Record failure metrics
    if (metrics != null) {
      _uploadMetrics[upload.id] = UploadMetrics(
        uploadId: upload.id,
        startTime: metrics.startTime,
        endTime: endTime,
        uploadDuration: endTime.difference(metrics.startTime),
        retryCount: upload.retryCount ?? 0,
        fileSizeMB: metrics.fileSizeMB,
        errorCategory: errorCategory,
        wasSuccessful: false,
      );
    }
  }

  /// Check if error is retriable
  bool _isRetriableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Network and timeout errors are retriable
    if (errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('socket')) {
      return true;
    }

    // Server errors (5xx) are retriable
    if (errorStr.contains('500') ||
        errorStr.contains('502') ||
        errorStr.contains('503') ||
        errorStr.contains('504')) {
      return true;
    }

    // Client errors (4xx) are generally not retriable
    if (errorStr.contains('400') ||
        errorStr.contains('401') ||
        errorStr.contains('403') ||
        errorStr.contains('404')) {
      return false;
    }

    // File not found errors are not retriable
    if (errorStr.contains('file not found') ||
        errorStr.contains('does not exist')) {
      return false;
    }

    // Unknown errors are retriable by default
    return true;
  }

  /// Categorize error for monitoring
  String _categorizeError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('timeout')) return 'TIMEOUT';
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'NETWORK';
    }
    if (errorStr.contains('file not found')) return 'FILE_NOT_FOUND';
    if (errorStr.contains('memory')) return 'MEMORY';
    if (errorStr.contains('permission')) return 'PERMISSION';
    if (errorStr.contains('auth')) return 'AUTHENTICATION';
    if (errorStr.contains('5')) return 'SERVER_ERROR';
    if (errorStr.contains('4')) return 'CLIENT_ERROR';

    return 'UNKNOWN';
  }

  /// Update upload progress
  void _updateUploadProgress(String uploadId, double progress) {
    final upload = getUpload(uploadId);
    if (upload != null && upload.status == UploadStatus.uploading) {
      _updateUpload(upload.copyWith(uploadProgress: progress));
    }
  }

  /// Pause an active upload
  Future<void> pauseUpload(String uploadId) async {
    final upload = getUpload(uploadId);
    if (upload == null) {
      Log.error('Upload not found for pause: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    if (upload.status != UploadStatus.uploading) {
      Log.error('Upload is not currently uploading: ${upload.status}',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    Log.debug('Pausing upload: $uploadId',
        name: 'UploadManager', category: LogCategory.video);

    // Cancel the active upload (similar to cancelUpload but non-destructive)
    if (upload.cloudinaryPublicId != null) {
      await _uploadService.cancelUpload(upload.cloudinaryPublicId!);
    }

    // Update status to paused instead of failed
    final pausedUpload = upload.copyWith(
      status: UploadStatus.paused,
      // Keep current progress and don't set error message
    );

    await _updateUpload(pausedUpload);

    // Cancel progress subscription
    _progressSubscriptions[uploadId]?.cancel();
    _progressSubscriptions.remove(uploadId);

    Log.info('Upload paused: $uploadId',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Resume a paused upload
  Future<void> resumeUpload(String uploadId) async {
    final upload = getUpload(uploadId);
    if (upload == null) {
      Log.error('Upload not found for resume: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    if (upload.status != UploadStatus.paused) {
      Log.error('Upload is not paused: ${upload.status}',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    Log.debug('▶️ Resuming upload: $uploadId',
        name: 'UploadManager', category: LogCategory.video);

    // Reset to pending to restart upload from beginning
    final resumedUpload = upload.copyWith(
      status: UploadStatus.pending,
      uploadProgress: 0, // Reset progress since we're starting over
      errorMessage: null,
    );

    await _updateUpload(resumedUpload);

    // Start upload process again
    _performUpload(resumedUpload);

    Log.info('Upload resumed: $uploadId',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Retry a failed upload
  Future<void> retryUpload(String uploadId) async {
    final upload = getUpload(uploadId);
    if (upload == null) {
      Log.error('Upload not found for retry: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    if (!upload.canRetry) {
      Log.error(
          'Upload cannot be retried: $uploadId (retries: ${upload.retryCount})',
          name: 'UploadManager',
          category: LogCategory.video);
      return;
    }

    Log.warning('Retrying upload: $uploadId',
        name: 'UploadManager', category: LogCategory.video);

    // Reset status and error
    final resetUpload = upload.copyWith(
      status: UploadStatus.pending,
      errorMessage: null,
      uploadProgress: null,
    );

    await _updateUpload(resetUpload);

    // Start upload again
    _performUpload(resetUpload);
  }

  /// Cancel an upload (stops the upload but keeps it for retry)
  Future<void> cancelUpload(String uploadId) async {
    final upload = getUpload(uploadId);
    if (upload == null) return;

    Log.debug('Cancelling upload: $uploadId',
        name: 'UploadManager', category: LogCategory.video);

    // Cancel any active upload
    if (upload.cloudinaryPublicId != null) {
      await _uploadService.cancelUpload(upload.cloudinaryPublicId!);
    }

    // Update status to failed so it can be retried later
    final cancelledUpload = upload.copyWith(
      status: UploadStatus.failed,
      errorMessage: 'Upload cancelled by user',
      uploadProgress: null,
    );

    await _updateUpload(cancelledUpload);

    // Cancel progress subscription
    _progressSubscriptions[uploadId]?.cancel();
    _progressSubscriptions.remove(uploadId);

    Log.warning('Upload cancelled and available for retry: $uploadId',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Delete an upload permanently (removes from storage)
  Future<void> deleteUpload(String uploadId) async {
    final upload = getUpload(uploadId);
    if (upload == null) return;

    Log.debug('📱️ Deleting upload: $uploadId',
        name: 'UploadManager', category: LogCategory.video);

    // Cancel any active upload first
    if (upload.status == UploadStatus.uploading) {
      if (upload.cloudinaryPublicId != null) {
        await _uploadService.cancelUpload(upload.cloudinaryPublicId!);
      }
    }

    // Cancel progress subscription
    _progressSubscriptions[uploadId]?.cancel();
    _progressSubscriptions.remove(uploadId);

    // Remove from storage
    await _uploadsBox?.delete(uploadId);

    Log.info('Upload deleted permanently: $uploadId',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Remove completed or failed uploads
  Future<void> cleanupCompletedUploads() async {
    if (_uploadsBox == null) return;

    final completedUploads = pendingUploads
        .where((upload) => upload.isCompleted)
        .where((upload) => upload.completedAt != null)
        .where(
          (upload) => DateTime.now().difference(upload.completedAt!).inDays > 7,
        ) // Keep for 7 days
        .toList();

    for (final upload in completedUploads) {
      await _uploadsBox!.delete(upload.id);
      Log.debug('📱️ Cleaned up old upload: ${upload.id}',
          name: 'UploadManager', category: LogCategory.video);
    }

    if (completedUploads.isNotEmpty) {}
  }

  /// Resume any uploads that were interrupted
  Future<void> _resumeInterruptedUploads() async {
    final interruptedUploads = pendingUploads
        .where((upload) => upload.status == UploadStatus.uploading)
        .toList();

    for (final upload in interruptedUploads) {
      Log.debug('Resuming interrupted upload: ${upload.id}',
          name: 'UploadManager', category: LogCategory.video);

      // Reset to pending and restart
      final resetUpload = upload.copyWith(
        status: UploadStatus.pending,
        uploadProgress: null,
      );

      await _updateUpload(resetUpload);
      _performUpload(resetUpload);
    }
  }

  /// Save upload to local storage with robust retry logic
  Future<void> _saveUpload(PendingUpload upload) async {
    // First attempt with existing box
    if (_uploadsBox != null && _uploadsBox!.isOpen) {
      try {
        await _uploadsBox!.put(upload.id, upload);
        Log.info('✅ Upload saved to Hive box with ID: ${upload.id}',
            name: 'UploadManager', category: LogCategory.video);
        return;
      } catch (e) {
        Log.warning(
            'Failed to save with existing box: $e, attempting recovery...',
            name: 'UploadManager',
            category: LogCategory.video);
      }
    }

    // Box is null or save failed - use robust initialization
    Log.warning('Upload box not ready, using robust initialization...',
        name: 'UploadManager', category: LogCategory.video);

    try {
      _uploadsBox = await UploadInitializationHelper.initializeUploadsBox(
        forceReinit: true,
      );

      if (_uploadsBox == null || !_uploadsBox!.isOpen) {
        throw Exception('Failed to initialize box for saving upload');
      }

      _isInitialized = true;

      // Retry save with new box
      await _uploadsBox!.put(upload.id, upload);
      Log.info('✅ Upload saved after robust initialization: ${upload.id}',
          name: 'UploadManager', category: LogCategory.video);
    } catch (e) {
      Log.error('❌ Failed to save upload after all retries: $e',
          name: 'UploadManager', category: LogCategory.video);

      // As a last resort, queue the upload for later
      _queueUploadForLater(upload);

      throw Exception(
          'Unable to save upload: Storage initialization failed after multiple attempts');
    }
  }

  // Queue for uploads that couldn't be saved immediately
  final List<PendingUpload> _pendingSaveQueue = [];
  Timer? _saveQueueTimer;

  /// Queue upload for later save attempt
  void _queueUploadForLater(PendingUpload upload) {
    Log.warning('Queueing upload ${upload.id} for later save attempt',
        name: 'UploadManager', category: LogCategory.video);

    _pendingSaveQueue.add(upload);

    // Schedule retry in 5 seconds
    _saveQueueTimer?.cancel();
    _saveQueueTimer = Timer(const Duration(seconds: 5), _processSaveQueue);
  }

  /// Process queued uploads
  Future<void> _processSaveQueue() async {
    if (_pendingSaveQueue.isEmpty) return;

    Log.info('Processing ${_pendingSaveQueue.length} queued uploads',
        name: 'UploadManager', category: LogCategory.video);

    final queue = List<PendingUpload>.from(_pendingSaveQueue);
    _pendingSaveQueue.clear();

    for (final upload in queue) {
      try {
        await _saveUpload(upload);
        Log.info('Successfully saved queued upload: ${upload.id}',
            name: 'UploadManager', category: LogCategory.video);
      } catch (e) {
        Log.error('Failed to save queued upload ${upload.id}: $e',
            name: 'UploadManager', category: LogCategory.video);
        // Re-queue for another attempt
        _pendingSaveQueue.add(upload);
      }
    }

    // If there are still pending uploads, schedule another retry
    if (_pendingSaveQueue.isNotEmpty) {
      _saveQueueTimer = Timer(const Duration(seconds: 30), _processSaveQueue);
    }
  }

  /// Update existing upload
  Future<void> _updateUpload(PendingUpload upload) async {
    if (_uploadsBox == null) return;

    await _uploadsBox!.put(upload.id, upload);
  }

  /// Update upload status (public method for VideoEventPublisher)
  Future<void> updateUploadStatus(String uploadId, UploadStatus status,
      {String? nostrEventId}) async {
    final upload = getUpload(uploadId);
    if (upload == null) {
      Log.warning('Upload not found for status update: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    final updatedUpload = upload.copyWith(
      status: status,
      nostrEventId: nostrEventId ?? upload.nostrEventId,
      completedAt: status == UploadStatus.published
          ? DateTime.now()
          : upload.completedAt,
    );

    await _updateUpload(updatedUpload);
    Log.info('Updated upload status: $uploadId -> $status',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Update upload metadata (title, description, hashtags)
  Future<void> updateUploadMetadata(
    String uploadId, {
    String? title,
    String? description,
    List<String>? hashtags,
  }) async {
    final upload = getUpload(uploadId);
    if (upload == null) {
      Log.warning('Upload not found for metadata update: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }
    final updatedUpload = upload.copyWith(
      title: title ?? upload.title,
      description: description ?? upload.description,
      hashtags: hashtags ?? upload.hashtags,
    );
    await _updateUpload(updatedUpload);
    Log.info('Updated upload metadata: $uploadId',
        name: 'UploadManager', category: LogCategory.video);
  }

  /// Get upload statistics
  Map<String, int> get uploadStats {
    final uploads = pendingUploads;
    return {
      'total': uploads.length,
      'pending': uploads.where((u) => u.status == UploadStatus.pending).length,
      'uploading':
          uploads.where((u) => u.status == UploadStatus.uploading).length,
      'processing':
          uploads.where((u) => u.status == UploadStatus.processing).length,
      'ready':
          uploads.where((u) => u.status == UploadStatus.readyToPublish).length,
      'published':
          uploads.where((u) => u.status == UploadStatus.published).length,
      'failed': uploads.where((u) => u.status == UploadStatus.failed).length,
    };
  }

  /// Fix uploads stuck in readyToPublish without proper data (debug method)
  Future<void> cleanupProblematicUploads() async {
    final uploads = pendingUploads;
    var fixedCount = 0;

    for (final upload in uploads) {
      // Fix uploads that are ready to publish but missing required data
      // These should be moved back to failed status so user can retry
      if (upload.status == UploadStatus.readyToPublish &&
          (upload.videoId == null || upload.cdnUrl == null)) {
        Log.error(
            'Fixing stuck upload: ${upload.id} (missing videoId/cdnUrl) - moving to failed',
            name: 'UploadManager',
            category: LogCategory.video);
        final fixedUpload = upload.copyWith(status: UploadStatus.failed);
        await _updateUpload(fixedUpload);
        fixedCount++;
      }
    }

    if (fixedCount > 0) {
      Log.error('Fixed $fixedCount stuck uploads - moved back to failed status',
          name: 'UploadManager', category: LogCategory.video);
    }
  }

  /// Get comprehensive performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    final metrics = _uploadMetrics.values.toList();
    final successful = metrics.where((m) => m.wasSuccessful).toList();
    final failed = metrics.where((m) => !m.wasSuccessful).toList();

    return {
      'total_uploads': metrics.length,
      'successful_uploads': successful.length,
      'failed_uploads': failed.length,
      'success_rate':
          metrics.isNotEmpty ? (successful.length / metrics.length * 100) : 0,
      'average_throughput_mbps': successful.isNotEmpty
          ? successful
                  .map((m) => m.throughputMBps ?? 0)
                  .reduce((a, b) => a + b) /
              successful.length
          : 0,
      'average_retry_count': metrics.isNotEmpty
          ? metrics.map((m) => m.retryCount).reduce((a, b) => a + b) /
              metrics.length
          : 0,
      'error_categories': _getErrorCategoriesCount(failed),
      'circuit_breaker_state': _circuitBreaker.state.toString(),
      'circuit_breaker_failure_rate': _circuitBreaker.failureRate,
    };
  }

  /// Get error categories breakdown
  Map<String, int> _getErrorCategoriesCount(List<UploadMetrics> failedMetrics) {
    final categories = <String, int>{};
    for (final metric in failedMetrics) {
      final category = metric.errorCategory ?? 'UNKNOWN';
      categories[category] = (categories[category] ?? 0) + 1;
    }
    return categories;
  }

  /// Get upload metrics for a specific upload
  UploadMetrics? getUploadMetrics(String uploadId) => _uploadMetrics[uploadId];

  /// Get recent upload metrics (last 24 hours)
  List<UploadMetrics> getRecentMetrics() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));

    return _uploadMetrics.values
        .where((m) => m.startTime.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  /// Clear old metrics to prevent memory bloat
  void _cleanupOldMetrics() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7)); // Keep 1 week

    _uploadMetrics.removeWhere(
      (key, metric) => metric.startTime.isBefore(cutoff),
    );
  }

  /// Enhanced retry mechanism for manual retry
  Future<void> retryUploadWithBackoff(String uploadId) async {
    final upload = getUpload(uploadId);
    if (upload == null) {
      Log.warning('Upload not found for retry: $uploadId',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    if (upload.status != UploadStatus.failed) {
      Log.error('Upload is not in failed state: ${upload.status}',
          name: 'UploadManager', category: LogCategory.video);
      return;
    }

    // Cancel any existing retry timer
    _retryTimers[uploadId]?.cancel();
    _retryTimers.remove(uploadId);

    Log.warning('Retrying upload with backoff: $uploadId',
        name: 'UploadManager', category: LogCategory.video);

    // Reset retry count if it's been more than 1 hour since last attempt
    final now = DateTime.now();
    final timeSinceLastAttempt = upload.completedAt != null
        ? now.difference(upload.completedAt!)
        : now.difference(upload.createdAt);

    final shouldResetRetries = timeSinceLastAttempt.inHours >= 1;
    final newRetryCount = shouldResetRetries ? 0 : (upload.retryCount ?? 0);

    // Update upload with reset retry count if applicable
    final updatedUpload = upload.copyWith(
      status: UploadStatus.pending,
      retryCount: newRetryCount,
      errorMessage: null,
    );

    await _updateUpload(updatedUpload);

    // Start upload process
    await _performUpload(updatedUpload);
  }

  /// Create successful upload with metadata
  PendingUpload _createSuccessfulUpload(PendingUpload upload, dynamic result) {
    // Handle DirectUploadResult structure
    final thumbnailUrl = result.thumbnailUrl as String?;
    Log.info('📸 Storing thumbnail URL in PendingUpload: $thumbnailUrl',
        name: 'UploadManager', category: LogCategory.system);

    return upload.copyWith(
      status: UploadStatus.readyToPublish, // Direct upload is immediately ready
      cloudinaryPublicId:
          result.videoId as String?, // Use videoId for existing systems
      videoId:
          result.videoId as String?, // Store videoId for new publishing system
      cdnUrl: result.cdnUrl as String?, // Store CDN URL directly
      thumbnailPath: thumbnailUrl, // Store thumbnail URL
      uploadProgress: 1,
      completedAt: DateTime.now(),
    );
  }

  /// Helper method to upload to OpenVine backend
  Future<DirectUploadResult> _uploadToBackend(
      PendingUpload upload, File videoFile) async {
    Log.info('☁️ Using OpenVine backend upload service',
        name: 'UploadManager', category: LogCategory.video);

    return await _uploadService.uploadVideo(
      videoFile: videoFile,
      nostrPubkey: upload.nostrPubkey,
      title: upload.title,
      description: upload.description,
      hashtags: upload.hashtags,
      onProgress: (progress) {
        Log.info(
            '📊 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
            name: 'UploadManager',
            category: LogCategory.video);
        _updateUploadProgress(upload.id, progress);
      },
    ).timeout(
      _retryConfig.networkTimeout,
      onTimeout: () {
        Log.error('⏱️ Upload timed out!',
            name: 'UploadManager', category: LogCategory.video);
        throw TimeoutException(
            'Upload timed out after ${_retryConfig.networkTimeout.inMinutes} minutes');
      },
    );
  }

  /// Create success metrics with calculated values
  UploadMetrics _createSuccessMetrics(
      UploadMetrics currentMetrics, DateTime endTime, int retryCount) {
    final duration = endTime.difference(currentMetrics.startTime);
    final throughput =
        _calculateThroughput(currentMetrics.fileSizeMB, duration);

    return UploadMetrics(
      uploadId: currentMetrics.uploadId,
      startTime: currentMetrics.startTime,
      endTime: endTime,
      uploadDuration: duration,
      retryCount: retryCount,
      fileSizeMB: currentMetrics.fileSizeMB,
      throughputMBps: throughput,
      wasSuccessful: true,
    );
  }

  /// Calculate upload throughput in MB/s
  double _calculateThroughput(double fileSizeMB, Duration duration) {
    // Handle zero duration edge case
    if (duration.inMicroseconds == 0) {
      return fileSizeMB * 1000; // Assume instant = 1ms
    }
    return fileSizeMB / (duration.inMicroseconds / 1000000.0);
  }

  /// Log upload success with formatted details
  void _logUploadSuccess(dynamic result, UploadMetrics metrics) {
    Log.info('Direct upload successful: ${result.videoId}',
        name: 'UploadManager', category: LogCategory.video);
    Log.debug('🎬 CDN URL: ${result.cdnUrl}',
        name: 'UploadManager', category: LogCategory.video);

    final durationStr = metrics.uploadDuration?.inSeconds ?? 0;
    final throughputStr = metrics.throughputMBps?.toStringAsFixed(2) ?? '0.00';

    Log.debug(
      'Upload metrics: ${metrics.fileSizeMB.toStringAsFixed(1)}MB in ${durationStr}s ($throughputStr MB/s)',
      name: 'UploadManager',
      category: LogCategory.video,
    );
  }

  void dispose() {
    // Cancel all progress subscriptions
    for (final subscription in _progressSubscriptions.values) {
      subscription.cancel();
    }
    _progressSubscriptions.clear();

    // Cancel all retry timers
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();

    // Cancel save queue timer
    _saveQueueTimer?.cancel();
    _saveQueueTimer = null;

    // Clean up old metrics
    _cleanupOldMetrics();

    // Note: We don't close the box here as it might be shared across instances
    // The box will be closed when Hive.close() is called in tearDownAll
    // Closing it here causes "File closed" errors in tests
    // _uploadsBox?.close();
    _uploadsBox = null;
    _isInitialized = false;

    // Clear any pending saves
    _pendingSaveQueue.clear();

    Log.info('UploadManager disposed',
        name: 'UploadManager', category: LogCategory.video);
  }
}
