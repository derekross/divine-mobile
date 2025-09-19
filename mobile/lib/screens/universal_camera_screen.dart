// ABOUTME: Universal camera screen that works on all platforms (mobile, macOS, web, Windows)
// ABOUTME: Uses VineRecordingController abstraction for consistent recording experience

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/main.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/vine_recording_provider.dart';
import 'package:openvine/screens/video_metadata_screen.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/upload_manager.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/vine_recording_controls.dart';
import 'package:openvine/widgets/camera_controls_overlay.dart';

class UniversalCameraScreen extends ConsumerStatefulWidget {
  const UniversalCameraScreen({super.key});

  @override
  ConsumerState<UniversalCameraScreen> createState() =>
      _UniversalCameraScreenState();
}

class _UniversalCameraScreenState extends ConsumerState<UniversalCameraScreen> {
  late final NostrKeyManager _keyManager;
  UploadManager? _uploadManager;

  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    // Provider handles disposal automatically
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      // Use post-frame callback to avoid provider modification during build
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // Stop all background videos after widget tree is built
          final videoManager = ref.read(videoManagerProvider.notifier);
          videoManager.stopAllVideos();

          // Clean up any metadata controllers from previous recording sessions
          await videoManager.disposeVideosWithPrefix('metadata_');
          Log.info(
              'Cleaned up old metadata controllers and stopped all background videos',
              name: 'UniversalCameraScreen',
              category: LogCategory.ui);

          // Get services from providers
          _uploadManager = ref.read(uploadManagerProvider);
          _keyManager = ref.read(nostrKeyManagerProvider);

          // Initialize recording controller via provider
          final recordingNotifier = ref.read(vineRecordingProvider.notifier);
          await recordingNotifier.initialize();

          if (mounted) {
            setState(() {
              _errorMessage = null;
            });
          }

          // For macOS, give the camera widget time to mount and initialize
          if (mounted && Theme.of(context).platform == TargetPlatform.macOS) {
            Log.debug('📱 Waiting for macOS camera widget to mount...',
                name: 'UniversalCameraScreen', category: LogCategory.ui);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Log.debug('📱 macOS camera widget should now be mounted',
                  name: 'UniversalCameraScreen', category: LogCategory.ui);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to initialize camera: $e';
            });
          }
          Log.error('Camera initialization failed: $e',
              name: 'UniversalCameraScreen', category: LogCategory.ui);
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
      Log.error('Camera initialization failed: $e',
          name: 'UniversalCameraScreen', category: LogCategory.ui);
    }
  }

  Future<void> _onRecordingComplete() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Finish recording and get the video file
      final recordingNotifier = ref.read(vineRecordingProvider.notifier);
      final videoFile = await recordingNotifier.finishRecording();

      if (videoFile != null && mounted) {
        // Navigate to metadata screen
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (context) => VideoMetadataScreen(
              videoFile: videoFile,
              duration: recordingNotifier.controller.totalRecordedDuration,
            ),
          ),
        );

        if (result != null && mounted) {
          // Get current user's pubkey
          final pubkey = _keyManager.publicKey ?? '';

          // Ensure upload manager is available
          _uploadManager ??= ref.read(uploadManagerProvider);

          // Start upload through upload manager
          await _uploadManager!.startUpload(
            videoFile: videoFile,
            nostrPubkey: pubkey,
            title: result['caption'] ?? '',
            description: result['caption'] ?? '',
            hashtags: result['hashtags'] ?? [],
          );

          // Don't reset here - let files persist until next recording session

          // Navigate back to the main feed immediately after starting upload
          // The upload will continue in the background
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    const MainNavigationScreen(initialTabIndex: 0),
              ),
            );
          }
        }
      }
    } catch (e) {
      Log.error('Error processing recording: $e',
          name: 'UniversalCameraScreen', category: LogCategory.ui);

      // Don't reset here on error - let files persist until next recording session

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process recording: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _onCancel() {
    // Just navigate back - keep recordings for potential retry
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Record Vine'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Stack(
          children: [
            // Camera preview (full screen)
            if (_errorMessage == null)
              Positioned.fill(
                child: Consumer(
                  builder: (context, ref, child) {
                    Log.debug('📱 Building camera preview widget',
                        name: 'UniversalCameraScreen',
                        category: LogCategory.ui);
                    final controller =
                        ref.watch(vineRecordingProvider.notifier).controller;
                    return controller.cameraPreview;
                  },
                ),
              )
            else
              _buildErrorView(),

            // Camera controls overlay (zoom, flash, etc.)
            if (_errorMessage == null)
              Positioned.fill(
                child: Consumer(
                  builder: (context, ref, child) {
                    final recordingNotifier =
                        ref.watch(vineRecordingProvider.notifier);
                    // Only show controls if camera interface is initialized
                    if (recordingNotifier.controller.cameraInterface == null) {
                      return const SizedBox.shrink();
                    }
                    return CameraControlsOverlay(
                      cameraInterface:
                          recordingNotifier.controller.cameraInterface!,
                      recordingState: recordingNotifier.controller.state,
                    );
                  },
                ),
              ),

            // Recording UI overlay
            if (_errorMessage == null)
              Positioned.fill(
                child: Consumer(
                  builder: (context, ref, child) {
                    final recordingState = ref.watch(vineRecordingProvider);
                    final recordingNotifier =
                        ref.watch(vineRecordingProvider.notifier);
                    return VineRecordingUIWithProvider(
                      controller: recordingNotifier.controller,
                      state: recordingState,
                      onRecordingComplete: _onRecordingComplete,
                      onCancel: _onCancel,
                    );
                  },
                ),
              ),

            // Upload progress indicator removed - we navigate away immediately after upload starts

            // Processing overlay
            if (_isProcessing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              VineTheme.vineGreen),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Processing your vine...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _buildErrorView() {
    // Parse error message to provide better guidance
    String title = 'Camera Error';
    String message = _errorMessage ?? 'Unknown error';
    String actionText = 'Try Again';
    IconData icon = Icons.error_outline;
    List<Widget> additionalInfo = [];

    // Check for specific error types and provide helpful guidance
    if (_errorMessage?.contains('No cameras available') == true ||
        _errorMessage?.contains('No camera found') == true ||
        _errorMessage?.contains('NotFoundError') == true) {
      title = 'No Camera Found';
      icon = Icons.videocam_off;
      message = 'A camera is required to record videos.';
      additionalInfo.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            kIsWeb
                ? 'Please connect a webcam to record videos.'
                : (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                    ? 'divine needs camera access to record videos. Please check your camera permissions in Settings.'
                    : 'Please connect a webcam to record videos.',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_errorMessage?.contains('Camera access denied') == true ||
        _errorMessage?.contains('NotAllowedError') == true ||
        _errorMessage?.contains('PermissionDeniedError') == true) {
      title = 'Camera Permission Needed';
      icon = Icons.camera_alt;
      message = 'divine needs camera access to record videos.';
      actionText = 'Grant Permission';
      additionalInfo.addAll([
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'To record and share videos, divine needs permission to use your camera.',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Click "Grant Permission" and allow camera access when prompted by your browser.',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      ]);
    } else if (_errorMessage?.contains('Camera is already in use') == true ||
        _errorMessage?.contains('NotReadableError') == true) {
      title = 'Camera In Use';
      icon = Icons.warning_amber;
      message = 'Your camera is being used by another application.';
      additionalInfo.add(
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Close other apps using your camera (video calls, etc.) and try again.',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_errorMessage?.contains('HTTPS') == true) {
      title = 'Secure Connection Required';
      icon = Icons.lock_outline;
      message = 'Camera access requires a secure connection.';
      additionalInfo.add(
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Please access divine using HTTPS for camera functionality.',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            ...additionalInfo,
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _initializeServices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VineTheme.vineGreen,
                  ),
                  child: Text(actionText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
