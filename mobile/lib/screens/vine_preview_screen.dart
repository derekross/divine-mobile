// ABOUTME: Vine-style preview screen for reviewing recorded videos before publishing
// ABOUTME: Uses VideoManager providers for secure controller creation and memory management

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/pending_upload.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/services/video_manager_interface.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:video_player/video_player.dart';

class VinePreviewScreen extends ConsumerStatefulWidget {
  const VinePreviewScreen({
    required this.videoFile,
    required this.frameCount,
    required this.selectedApproach,
    super.key,
  });
  final File videoFile;
  final int frameCount;
  final String selectedApproach;

  @override
  ConsumerState<VinePreviewScreen> createState() => _VinePreviewScreenState();
}

class _VinePreviewScreenState extends ConsumerState<VinePreviewScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _hashtagsController = TextEditingController();
  String? _videoControllerId;
  bool _isUploading = false;
  bool _isPlaying = false;
  bool _isExpiringPost = false;
  int _expirationHours = 24;

  @override
  void initState() {
    super.initState();
    // Pre-populate with default hashtags
    _hashtagsController.text = 'openvine vine';
    _initializeVideoPlayer();

    // Start background upload while user enters metadata
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundUpload();
    });
  }

  @override
  void dispose() {
    if (_videoControllerId != null) {
      // VideoManager will handle cleanup and GlobalVideoRegistry coordination
      ref.read(videoManagerProvider.notifier).disposeVideo(_videoControllerId!);
      _videoControllerId = null;
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _hashtagsController.dispose();

    super.dispose();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      // Use VideoManager to create file controller securely
      final videoManager = ref.read(videoManagerProvider.notifier);
      final controllerId = 'vine_preview_${widget.videoFile.path.hashCode}';

      final controller = await videoManager.createFileController(
        controllerId,
        widget.videoFile,
        priority: PreloadPriority.current,
      );

      if (controller != null && mounted) {
        _videoControllerId = controllerId;

        await controller.setLooping(true);
        setState(() {});
        // Auto-play the video
        _playVideo();
      }
    } catch (e) {
      Log.error('Error initializing video preview: $e',
          name: 'VinePreviewScreen', category: LogCategory.ui);
    }
  }

  void _playVideo() {
    if (_videoControllerId != null) {
      final controller =
          ref.read(videoPlayerControllerProvider(_videoControllerId!));
      if (controller?.value.isInitialized == true) {
        controller!.play();
        setState(() {
          _isPlaying = true;
        });
      }
    }
  }

  void _pauseVideo() {
    if (_videoControllerId != null) {
      final controller =
          ref.read(videoPlayerControllerProvider(_videoControllerId!));
      if (controller?.value.isInitialized == true) {
        controller!.pause();
        setState(() {
          _isPlaying = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _pauseVideo();
    } else {
      _playVideo();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get controller from VideoManager
    final controller = _videoControllerId != null
        ? ref.watch(videoPlayerControllerProvider(_videoControllerId!))
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with Vine branding
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: VineTheme.whiteText),
                    onPressed: _isUploading ? null : _showExitConfirmation,
                  ),
                  const Expanded(
                    child: Text(
                      'Review Your Vine',
                      style: TextStyle(
                        color: VineTheme.whiteText,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _isUploading ? null : _saveDraft,
                    child: Text(
                      'Draft',
                      style: TextStyle(
                        color: _isUploading ? Colors.grey : VineTheme.vineGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Video preview section
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[900],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Video player
                      if (controller?.value.isInitialized == true)
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: controller!.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          height: double.infinity,
                          color: Colors.grey[800],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: VineTheme.vineGreen,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Loading video...',
                                style: TextStyle(
                                  color: VineTheme.whiteText,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Play/pause overlay
                      if (controller?.value.isInitialized == true &&
                          !_isPlaying)
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.black.withValues(alpha: 0.3),
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_filled,
                                color: VineTheme.whiteText,
                                size: 64,
                              ),
                            ),
                          ),
                        ),

                      // Video info overlay
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.frameCount} frames • ${widget.selectedApproach}',
                            style: const TextStyle(
                              color: VineTheme.whiteText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Details section
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title input
                      const Text(
                        'Title',
                        style: TextStyle(
                          color: VineTheme.whiteText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(color: VineTheme.whiteText),
                        decoration: InputDecoration(
                          hintText: 'Give your Vine a title...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[800],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: VineTheme.vineGreen),
                          ),
                        ),
                        maxLength: 100,
                        enableInteractiveSelection: true,
                      ),
                      const SizedBox(height: 16),

                      // Description input
                      const Text(
                        'Description',
                        style: TextStyle(
                          color: VineTheme.whiteText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descriptionController,
                        style: const TextStyle(color: VineTheme.whiteText),
                        decoration: InputDecoration(
                          hintText: 'Tell people about your Vine...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[800],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: VineTheme.vineGreen),
                          ),
                        ),
                        maxLines: 3,
                        maxLength: 280,
                        enableInteractiveSelection: true,
                      ),
                      const SizedBox(height: 16),

                      // Expiring post toggle
                      Row(
                        children: [
                          const Text(
                            'Expiring Post',
                            style: TextStyle(
                              color: VineTheme.whiteText,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildExpirationOption('1 hour', 1),
                              const SizedBox(width: 8),
                              _buildExpirationOption('6 hours', 6),
                              const SizedBox(width: 8),
                              _buildExpirationOption('1 day', 24),
                              const SizedBox(width: 8),
                              _buildExpirationOption('3 days', 72),
                              const SizedBox(width: 8),
                              _buildExpirationOption('1 week', 168),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Hashtags input
                      const Text(
                        'Hashtags',
                        style: TextStyle(
                          color: VineTheme.whiteText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _hashtagsController,
                        style: const TextStyle(color: VineTheme.whiteText),
                        decoration: InputDecoration(
                          hintText: 'funny viral comedy',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[800],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: VineTheme.vineGreen),
                          ),
                          prefixText: '#',
                          prefixStyle:
                              const TextStyle(color: VineTheme.vineGreen),
                        ),
                        enableInteractiveSelection: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Upload button
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _publishVine,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VineTheme.vineGreen,
                    foregroundColor: VineTheme.whiteText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isUploading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: VineTheme.whiteText,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Publishing...'),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.upload, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Publish Vine',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? VineTheme.vineGreen : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(color: Colors.grey[600]!, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : VineTheme.whiteText,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Discard Vine?',
          style: TextStyle(color: VineTheme.whiteText),
        ),
        content: const Text(
          'Your Vine will be lost if you exit without saving as draft or publishing.',
          style: TextStyle(color: VineTheme.whiteText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _saveDraft();
            },
            child: const Text('Save Draft'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDraft() async {
    try {
      // TODO: Implement proper draft saving
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💾 Vine saved to drafts'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save draft: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Start background upload as soon as the screen loads
  Future<void> _startBackgroundUpload() async {
    try {
      final uploadManager = ref.read(uploadManagerProvider);
      final authService = ref.read(authServiceProvider);

      // Get user's public key
      final userPubkey = authService.currentPublicKeyHex ?? 'anonymous';

      // Start the upload with placeholder metadata
      await uploadManager.startUpload(
        videoFile: widget.videoFile,
        nostrPubkey: userPubkey,
        title: 'Vine Video', // Will be updated when user publishes
        description:
            'Created with divine', // Will be updated when user publishes
        hashtags: ['openvine'], // Will be updated when user publishes
      );

      // Background upload started successfully

      Log.info('Background upload started while user enters metadata',
          name: 'VinePreviewScreen', category: LogCategory.ui);
    } catch (e) {
      Log.error('Failed to start background upload: $e',
          name: 'VinePreviewScreen', category: LogCategory.ui);
    }
  }

  Future<void> _publishVine() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a title for your Vine'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final uploadManager = ref.read(uploadManagerProvider);

      // Parse hashtags
      final hashtags = _hashtagsController.text
          .split(' ')
          .map((tag) => tag.trim().replaceAll('#', ''))
          .where((tag) => tag.isNotEmpty)
          .toList();

      // Find the existing upload by file path
      final existingUpload =
          uploadManager.getUploadByFilePath(widget.videoFile.path);

      if (existingUpload != null &&
          existingUpload.status == UploadStatus.readyToPublish) {
        // Use the existing upload data to publish directly
        Log.debug('📱 Publishing existing upload: ${existingUpload.id}',
            name: 'VinePreviewScreen', category: LogCategory.ui);
        Log.debug('📱 CDN URL: ${existingUpload.cdnUrl}',
            name: 'VinePreviewScreen', category: LogCategory.ui);

        // Get the video event publisher
        final videoEventPublisher = ref.read(videoEventPublisherProvider);

        // Calculate expiration timestamp if enabled
        int? expirationTimestamp;
        if (_isExpiringPost) {
          final now = DateTime.now();
          final expirationDate = now.add(Duration(hours: _expirationHours));
          expirationTimestamp = expirationDate.millisecondsSinceEpoch ~/ 1000;
        }

        // Create and publish the Nostr event with user's metadata
        await videoEventPublisher.publishVideoEvent(
          upload: existingUpload,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          hashtags: hashtags,
          expirationTimestamp: expirationTimestamp,
        );

        Log.info('Published video with user metadata',
            name: 'VinePreviewScreen', category: LogCategory.ui);
      } else {
        // Fallback: if upload not found or not ready, show error
        throw Exception(
            'Upload not ready. Please wait for upload to complete.');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 Vine published successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Navigate back to camera or feed
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish Vine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
