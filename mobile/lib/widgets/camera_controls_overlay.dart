// ABOUTME: Camera controls overlay for advanced features like zoom and flash
// ABOUTME: Works with CameraAwesome on mobile platforms to provide enhanced controls

import 'package:flutter/material.dart';
import 'package:openvine/services/camera/enhanced_mobile_camera_interface.dart';
import 'package:openvine/services/vine_recording_controller.dart';
import 'package:openvine/theme/vine_theme.dart';

/// Overlay widget that provides camera controls for zoom, flash, etc.
class CameraControlsOverlay extends StatefulWidget {
  const CameraControlsOverlay({
    required this.cameraInterface,
    required this.recordingState,
    super.key,
  });

  final CameraPlatformInterface cameraInterface;
  final VineRecordingState recordingState;

  @override
  State<CameraControlsOverlay> createState() => _CameraControlsOverlayState();
}

class _CameraControlsOverlayState extends State<CameraControlsOverlay> {
  double _currentZoom = 0.0;
  bool _showZoomSlider = false;

  @override
  Widget build(BuildContext context) {
    // Only show enhanced controls for enhanced mobile camera
    if (widget.cameraInterface is! EnhancedMobileCameraInterface) {
      return const SizedBox.shrink();
    }

    final enhancedCamera =
        widget.cameraInterface as EnhancedMobileCameraInterface;
    final isRecording = widget.recordingState == VineRecordingState.recording;

    return Stack(
      children: [
        // Zoom gesture detector
        Positioned.fill(
          child: GestureDetector(
            onScaleStart: (_) {
              if (!isRecording) {
                setState(() => _showZoomSlider = true);
              }
            },
            onScaleUpdate: (details) {
              if (!isRecording && details.scale != 1.0) {
                final newZoom =
                    (_currentZoom + (details.scale - 1) * 0.1).clamp(0.0, 1.0);
                setState(() => _currentZoom = newZoom);
                enhancedCamera.setZoom(newZoom);
              }
            },
            onScaleEnd: (_) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() => _showZoomSlider = false);
                }
              });
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // Top controls (flash toggle)
        if (!isRecording)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Column(
              children: [
                // Flash toggle button
                _buildControlButton(
                  icon: Icons.flash_auto,
                  onTap: () => enhancedCamera.toggleFlash(),
                ),
              ],
            ),
          ),

        // Zoom slider
        if (_showZoomSlider && !isRecording)
          Positioned(
            bottom: 180,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.zoom_out,
                    color: Colors.white,
                    size: 20,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: VineTheme.vineGreen,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: VineTheme.vineGreen,
                        overlayColor:
                            VineTheme.vineGreen.withValues(alpha: 0.3),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _currentZoom,
                        onChanged: (value) {
                          setState(() => _currentZoom = value);
                          enhancedCamera.setZoom(value);
                        },
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

        // Zoom level indicator
        if (_currentZoom > 0 && !isRecording)
          Positioned(
            bottom: 240,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(_currentZoom * 10 + 1).toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Enhanced camera features info widget
class CameraFeaturesInfo extends StatelessWidget {
  const CameraFeaturesInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Camera Controls',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: VineTheme.vineGreen,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          _buildFeatureRow(Icons.touch_app, 'Tap to focus'),
          _buildFeatureRow(Icons.zoom_in, 'Pinch to zoom'),
          _buildFeatureRow(Icons.flash_on, 'Toggle flash'),
          _buildFeatureRow(Icons.cameraswitch, 'Switch camera'),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
