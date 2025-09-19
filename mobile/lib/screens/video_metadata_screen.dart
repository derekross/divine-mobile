// ABOUTME: Screen for adding metadata to recorded videos before publishing
// ABOUTME: Uses VideoManager providers for secure controller creation and memory management

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openvine/main.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/profile_videos_provider.dart';
import 'package:openvine/providers/profile_stats_provider.dart';
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/utils/ios_upload_debug_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

class VideoMetadataScreen extends ConsumerStatefulWidget {
  const VideoMetadataScreen({
    required this.videoFile,
    required this.duration,
    super.key,
  });
  final File videoFile;
  final Duration duration;

  @override
  ConsumerState<VideoMetadataScreen> createState() =>
      _VideoMetadataScreenState();
}

class _VideoMetadataScreenState extends ConsumerState<VideoMetadataScreen> {
  String? _videoControllerId;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();
  final List<String> _hashtags = [];
  bool _isVideoInitialized = false;
  String? _currentUploadId;
  bool _isExpiringPost = false;
  int _expirationHours = 24;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    // Delay initialization to ensure file is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVideo();
      _startBackgroundUpload();
    });
  }

  @override
  void dispose() {
    if (_videoControllerId != null) {
      try {
        // VideoManager will handle cleanup and GlobalVideoRegistry coordination
        ref
            .read(videoManagerProvider.notifier)
            .disposeVideo(_videoControllerId!);
      } catch (e) {
        // If ref is already disposed, log and continue
        Log.warning('Could not dispose video controller (ref disposed): $e',
            name: 'VideoMetadataScreen', category: LogCategory.ui);
      }
      _videoControllerId = null;
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _hashtagController.dispose();

    super.dispose();
  }

  Future<void> _initializeVideo() async {
    Log.debug('Initializing video preview: ${widget.videoFile.path}',
        name: 'VideoMetadataScreen', category: LogCategory.ui);
    Log.debug('📱 File exists: ${widget.videoFile.existsSync()}',
        name: 'VideoMetadataScreen', category: LogCategory.ui);
    Log.debug(
        '📱 File size: ${widget.videoFile.existsSync() ? widget.videoFile.lengthSync() : 0} bytes',
        name: 'VideoMetadataScreen',
        category: LogCategory.ui);

    try {
      // Use VideoManager to create file controller securely
      final videoManager = ref.read(videoManagerProvider.notifier);
      final controllerId = 'metadata_${widget.videoFile.path.hashCode}';

      Log.debug(
          'Creating video controller with ID: $controllerId for file: ${widget.videoFile.path}',
          name: 'VideoMetadataScreen',
          category: LogCategory.ui);

      final controller = await videoManager.createFileController(
        controllerId,
        widget.videoFile,
        priority: PreloadPriority.current,
      );

      if (controller != null && mounted) {
        _videoControllerId = controllerId;

        Log.info('Video initialized: ${controller.value.size}',
            name: 'VideoMetadataScreen', category: LogCategory.ui);

        // Pause all other videos before playing this one
        videoManager.pauseAllVideos();

        await controller.setLooping(true);
        await controller.play();
        setState(() => _isVideoInitialized = true);
      } else {
        setState(() => _isVideoInitialized = false);
      }
    } catch (e) {
      Log.error('Failed to initialize video: $e',
          name: 'VideoMetadataScreen', category: LogCategory.ui);
      Log.verbose('📱 Stack trace: ${StackTrace.current}',
          name: 'VideoMetadataScreen', category: LogCategory.ui);
      // Still update UI to show error state
      setState(() => _isVideoInitialized = false);
    }
  }

  Widget _buildVideoPreview() {
    // Get controller from VideoManager
    final controller = _videoControllerId != null
        ? ref.watch(videoPlayerControllerProvider(_videoControllerId!))
        : null;

    if (_isVideoInitialized && controller?.value.isInitialized == true) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller!.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    // Check if file exists
    if (!widget.videoFile.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            const Text(
              'Video file not found',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back',
                  style: TextStyle(color: VineTheme.vineGreen)),
            ),
          ],
        ),
      );
    }

    // Loading state
    return const Center(
      child: CircularProgressIndicator(color: VineTheme.vineGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: VineTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: VineTheme.vineGreen,
        elevation: 0,
        title: const Text(
          'Add Details',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isPublishing ? null : _publishVideo,
            child: _isPublishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'PUBLISH',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Upload progress bar at the top (always visible)
          if (_currentUploadId != null)
            Consumer(
              builder: (context, ref, child) {
                final uploadManager = ref.watch(uploadManagerProvider);
                final upload = uploadManager.getUpload(_currentUploadId!);
                if (upload == null) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  color: Colors.grey[900],
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: upload.progressValue,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            VineTheme.vineGreen),
                        minHeight: 3,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_upload,
                                color: VineTheme.vineGreen, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              upload.status == UploadStatus.uploading
                                  ? 'Uploading ${(upload.progressValue * 100).toInt()}%'
                                  : upload.status == UploadStatus.readyToPublish
                                      ? 'Upload complete - Ready to publish'
                                      : upload.statusText,
                              style: const TextStyle(
                                  color: VineTheme.vineGreen, fontSize: 13),
                            ),
                            const Spacer(),
                            Text(
                              '${widget.duration.inSeconds}s • ${_getFileSize()}',
                              style: const TextStyle(
                                  color: VineTheme.secondaryText, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Video preview - smaller to save space
          ClipRect(
            child: Container(
              height: screenHeight * 0.25, // 25% of screen height
              width: double.infinity,
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildVideoPreview(),
                  ),
                ],
              ),
            ),
          ),

          // Form fields with better spacing
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title field with integrated counter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Title',
                            style: TextStyle(
                              color: VineTheme.secondaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${_titleController.text.length}/100',
                            style: TextStyle(
                              color: VineTheme.secondaryText
                                  .withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _titleController,
                        enabled: true,
                        autofocus: false,
                        enableInteractiveSelection: true,
                        style: const TextStyle(
                          color: VineTheme.primaryText,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Give your vine a catchy title',
                          hintStyle: TextStyle(
                            color:
                                VineTheme.secondaryText.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: VineTheme.secondaryText
                                    .withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: VineTheme.vineGreen),
                          ),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                        maxLength: 100,
                        buildCounter: (context,
                            {required currentLength,
                            required isFocused,
                            maxLength}) {
                          return const SizedBox
                              .shrink(); // Hide default counter
                        },
                        onChanged: (_) => setState(() {}), // Update counter
                      ),
                    ],
                  ),

                  Divider(
                      color: VineTheme.secondaryText.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),

                  // Description field with integrated counter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Description (optional)',
                            style: TextStyle(
                              color: VineTheme.secondaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${_descriptionController.text.length}/500',
                            style: TextStyle(
                              color: VineTheme.secondaryText
                                  .withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _descriptionController,
                        enabled: true,
                        enableInteractiveSelection: true,
                        style: const TextStyle(
                          color: VineTheme.primaryText,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Tell viewers about your vine',
                          hintStyle: TextStyle(
                            color:
                                VineTheme.secondaryText.withValues(alpha: 0.5),
                            fontSize: 15,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: VineTheme.secondaryText
                                    .withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: VineTheme.vineGreen),
                          ),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                        maxLines: 2,
                        maxLength: 500,
                        buildCounter: (context,
                            {required currentLength,
                            required isFocused,
                            maxLength}) {
                          return const SizedBox
                              .shrink(); // Hide default counter
                        },
                        onChanged: (_) => setState(() {}), // Update counter
                      ),
                    ],
                  ),

                  Divider(
                      color: VineTheme.secondaryText.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),

                  // Hashtags section - more compact
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hashtags',
                        style: TextStyle(
                          color: VineTheme.secondaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Hashtag chips - horizontal scroll if needed
                      SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // Default openvine tag
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: const Text('#openvine',
                                    style: TextStyle(fontSize: 13)),
                                backgroundColor:
                                    VineTheme.vineGreen.withValues(alpha: 0.2),
                                labelStyle:
                                    const TextStyle(color: VineTheme.vineGreen),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            // User added tags
                            ..._hashtags.map(
                              (tag) => Container(
                                margin: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text('#$tag',
                                      style: const TextStyle(fontSize: 13)),
                                  backgroundColor: VineTheme.vineGreen
                                      .withValues(alpha: 0.2),
                                  labelStyle: const TextStyle(
                                      color: VineTheme.vineGreen),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  deleteIconColor: VineTheme.vineGreen,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onDeleted: () {
                                    setState(() {
                                      _hashtags.remove(tag);
                                    });
                                  },
                                ),
                              ),
                            ),
                            // Add hashtag button
                            if (_hashtags.length < 5) // Limit to 5 custom tags
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: const Text('+ Add',
                                      style: TextStyle(fontSize: 13)),
                                  backgroundColor: Colors.grey[850],
                                  labelStyle: const TextStyle(
                                      color: VineTheme.secondaryText),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onPressed: _showHashtagDialog,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  Divider(
                      color: VineTheme.secondaryText.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),

                  // Expiring post toggle
                  Row(
                    children: [
                      const Text(
                        'Expiring Post',
                        style: TextStyle(
                          color: VineTheme.secondaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _isExpiringPost,
                        onChanged: (value) {
                          setState(() {
                            _isExpiringPost = value;
                          });
                        },
                        activeColor: VineTheme.vineGreen,
                      ),
                    ],
                  ),
                  if (_isExpiringPost) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Expires in:',
                      style: TextStyle(
                        color: VineTheme.secondaryText.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildExpirationOption('1 hour', 1),
                          const SizedBox(width: 8),
                          _buildExpirationOption('1 day', 24),
                          const SizedBox(width: 8),
                          _buildExpirationOption('1 week', 168),
                          const SizedBox(width: 8),
                          _buildExpirationOption('1 month', 720),
                          const SizedBox(width: 8),
                          _buildExpirationOption('1 year', 8760),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpirationOption(String label, int hours) {
    final isSelected = _expirationHours == hours;
    return GestureDetector(
      onTap: () {
        setState(() {
          _expirationHours = hours;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? VineTheme.vineGreen : Colors.grey[850],
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? null
              : Border.all(
                  color: VineTheme.secondaryText.withValues(alpha: 0.3),
                  width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : VineTheme.secondaryText,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _addHashtag() {
    final tag = _hashtagController.text.trim().replaceAll('#', '');
    if (tag.isNotEmpty && !_hashtags.contains(tag) && tag != 'openvine') {
      setState(() {
        _hashtags.add(tag);
        _hashtagController.clear();
      });
    }
  }

  void _showHashtagDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Add Hashtag',
          style: TextStyle(color: VineTheme.primaryText),
        ),
        content: TextField(
          controller: _hashtagController,
          autofocus: true,
          style: const TextStyle(color: VineTheme.primaryText),
          decoration: InputDecoration(
            hintText: 'Enter hashtag',
            hintStyle: TextStyle(
                color: VineTheme.secondaryText.withValues(alpha: 0.5)),
            prefixText: '#',
            prefixStyle: const TextStyle(color: VineTheme.vineGreen),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: VineTheme.secondaryText),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: VineTheme.vineGreen),
            ),
          ),
          onSubmitted: (_) {
            _addHashtag();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              _hashtagController.clear();
              Navigator.of(context).pop();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: VineTheme.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () {
              _addHashtag();
              Navigator.of(context).pop();
            },
            child: const Text(
              'Add',
              style: TextStyle(color: VineTheme.vineGreen),
            ),
          ),
        ],
      ),
    );
  }

  String _getFileSize() {
    final bytes = widget.videoFile.lengthSync();
    final mb = bytes / 1024 / 1024;
    return '${mb.toStringAsFixed(1)}MB';
  }

  /// Start upload immediately in the background
  Future<void> _startBackgroundUpload() async {
    try {
      Log.info('Starting background upload for video: ${widget.videoFile.path}',
          name: 'VideoMetadataScreen', category: LogCategory.ui);

      final uploadManager = ref.read(uploadManagerProvider);
      final authService = ref.read(authServiceProvider);

      // Get user's public key
      final userPubkey = authService.currentPublicKeyHex ?? 'anonymous';

      // Get video dimensions if controller is initialized
      int? videoWidth;
      int? videoHeight;
      if (_videoControllerId != null) {
        final controller = ref
            .read(videoManagerProvider)
            .getPlayerController(_videoControllerId!);
        if (controller != null && controller.value.isInitialized) {
          videoWidth = controller.value.size.width.toInt();
          videoHeight = controller.value.size.height.toInt();
        }
      }

      // Start the upload with placeholder metadata (will update when user publishes)
      final upload = await uploadManager.startUpload(
        videoFile: widget.videoFile,
        nostrPubkey: userPubkey,
        title: 'Untitled', // Placeholder title
        description: '',
        hashtags: ['openvine'],
        videoWidth: videoWidth,
        videoHeight: videoHeight,
        videoDuration: widget.duration,
      );

      setState(() {
        _currentUploadId = upload.id;
        Log.info('🆔 Current upload ID set to: $_currentUploadId',
            name: 'VideoMetadataScreen', category: LogCategory.ui);
      });

      Log.info('✅ === BACKGROUND UPLOAD COMPLETE ===',
          name: 'VideoMetadataScreen', category: LogCategory.ui);
      Log.info('🆔 Upload ID: ${upload.id}',
          name: 'VideoMetadataScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('❌ === BACKGROUND UPLOAD FAILED ===',
          name: 'VideoMetadataScreen', category: LogCategory.ui);
      Log.error('❌ Error: $e',
          name: 'VideoMetadataScreen', category: LogCategory.ui);

      // Check if it's a file issue
      if (widget.videoFile.existsSync()) {
        Log.error('📁 File exists but upload failed anyway',
            name: 'VideoMetadataScreen', category: LogCategory.ui);
      } else {
        Log.error('📁 File does not exist!',
            name: 'VideoMetadataScreen', category: LogCategory.ui);
      }
      // Don't show error here - let the publish button handle it
      // This allows the user to retry by hitting publish
    }
  }

  Future<void> _publishVideo() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a title'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Always include openvine tag
    final allHashtags = ['openvine', ..._hashtags];

    // Calculate expiration timestamp if enabled
    int? expirationTimestamp;
    if (_isExpiringPost) {
      final now = DateTime.now();
      final expirationDate = now.add(Duration(hours: _expirationHours));
      expirationTimestamp = expirationDate.millisecondsSinceEpoch ~/ 1000;
    }

    setState(() {
      _isPublishing = true;
    });

    try {
      // If upload hasn't started, start it now
      if (_currentUploadId == null) {
        Log.info('Upload not started yet, starting now...',
            name: 'VideoMetadataScreen', category: LogCategory.ui);
        await _startBackgroundUpload();

        // Check if it succeeded
        if (_currentUploadId == null) {
          throw Exception(
              'Failed to start upload. Please check your connection and try again.');
        }
      }

      // Get the current upload
      final uploadManager = ref.read(uploadManagerProvider);
      var upload = uploadManager.getUpload(_currentUploadId!);

      if (upload == null) {
        throw Exception('Upload not found');
      }

      // If still uploading, update metadata and wait for completion
      if (upload.status == UploadStatus.uploading ||
          upload.status == UploadStatus.processing) {
        Log.info('Upload in progress, will publish when ready...',
            name: 'VideoMetadataScreen', category: LogCategory.ui);

        // Update metadata while uploading
        await uploadManager.updateUploadMetadata(
          _currentUploadId!,
          title: title,
          description: _descriptionController.text.trim(),
          hashtags: allHashtags,
        );

        // Show progress indicator
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Uploading and publishing...'),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 10),
          ),
        );

        // Wait for upload to complete
        int waitCount = 0;
        while (upload?.status == UploadStatus.uploading ||
            upload?.status == UploadStatus.processing) {
          await Future.delayed(const Duration(seconds: 1));
          waitCount++;

          // Timeout after 60 seconds
          if (waitCount > 60) {
            throw Exception('Upload timeout. Please try again.');
          }

          // Refresh upload status
          final updatedUpload = uploadManager.getUpload(_currentUploadId!);
          if (updatedUpload == null) {
            throw Exception('Upload lost');
          }
          upload = updatedUpload;
        }
      }

      if (upload?.status == UploadStatus.failed) {
        final errorMsg = upload?.errorMessage ?? "Unknown error";

        // Show detailed error on iOS
        if (IOSUploadDebugHelper.shouldShowDebugInfo() && mounted) {
          IOSUploadDebugHelper.showDetailedError(
            context,
            errorMessage: errorMsg,
            upload: upload,
          );
        }

        throw Exception('Upload failed: $errorMsg');
      }

      if (upload?.status != UploadStatus.readyToPublish &&
          upload?.status != UploadStatus.published) {
        throw Exception('Upload not ready for publishing: ${upload?.status}');
      }

      // Get the video event publisher and publish
      final videoEventPublisher = ref.read(videoEventPublisherProvider);

      Log.info('Publishing video event to Nostr...',
          name: 'VideoMetadataScreen', category: LogCategory.ui);

      final success = await videoEventPublisher.publishVideoEvent(
        upload: upload!,
        title: title,
        description: _descriptionController.text.trim(),
        hashtags: allHashtags,
        expirationTimestamp: expirationTimestamp,
      );

      if (!success) {
        throw Exception('Failed to publish video event');
      }

      Log.info('Video successfully published to Nostr!',
          name: 'VideoMetadataScreen', category: LogCategory.ui);

      // Navigate to profile screen to see the published video
      if (mounted) {
        // Show success message first
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video published successfully! 🎉'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Clear all profile caches to force complete refresh
        clearAllProfileVideosCache();

        // Force refresh of all profile-related providers
        ref.invalidate(profileVideosNotifierProvider);
        ref.invalidate(profileStatsNotifierProvider);
        ref.invalidate(userProfileNotifierProvider);

        // Navigate to profile tab (index 3) to show user their new video
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                const MainNavigationScreen(initialTabIndex: 3),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      Log.error('Failed to publish video: $e',
          name: 'VideoMetadataScreen', category: LogCategory.ui);

      if (mounted) {
        // Show detailed error dialog on iOS
        if (IOSUploadDebugHelper.shouldShowDebugInfo()) {
          // Get upload details if available
          PendingUpload? failedUpload;
          if (_currentUploadId != null) {
            final uploadManager = ref.read(uploadManagerProvider);
            failedUpload = uploadManager.getUpload(_currentUploadId!);
          }

          IOSUploadDebugHelper.showDetailedError(
            context,
            errorMessage: e.toString(),
            upload: failedUpload,
            exception: e,
          );
        }

        // Also show snackbar for quick feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }
}
