// ABOUTME: Native platform channel to detect physical camera zoom factors dynamically
// ABOUTME: Queries iOS AVCaptureDevice to get actual zoom values (not hardcoded)

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Information about a physical camera sensor
class PhysicalCameraSensor {
  const PhysicalCameraSensor({
    required this.type,
    required this.zoomFactor,
    required this.deviceId,
    required this.displayName,
  });

  final String type; // 'wide', 'ultrawide', 'telephoto', 'front'
  final double zoomFactor; // Actual zoom factor (e.g., 0.5, 1.0, 3.0)
  final String deviceId; // Native device identifier
  final String displayName; // Human-readable name

  @override
  String toString() => 'PhysicalCameraSensor($displayName, ${zoomFactor}x, $type)';
}

/// Detects available physical cameras and their actual zoom factors
class CameraZoomDetector {
  static const MethodChannel _channel = MethodChannel('com.openvine/camera_zoom_detector');

  /// Get all available physical cameras with their actual zoom factors
  /// Returns empty list if detection fails or platform doesn't support it
  static Future<List<PhysicalCameraSensor>> getPhysicalCameras() async {
    if (!Platform.isIOS) {
      Log.info(
        'Camera zoom detection only supported on iOS',
        name: 'CameraZoomDetector',
        category: LogCategory.system,
      );
      return [];
    }

    try {
      Log.info(
        'Detecting physical cameras and zoom factors...',
        name: 'CameraZoomDetector',
        category: LogCategory.system,
      );

      final List<dynamic>? result = await _channel.invokeListMethod('getPhysicalCameras');

      if (result == null || result.isEmpty) {
        Log.warning(
          'No physical cameras detected from native side',
          name: 'CameraZoomDetector',
          category: LogCategory.system,
        );
        return [];
      }

      final cameras = result.map((dynamic item) {
        final map = Map<String, dynamic>.from(item as Map);
        return PhysicalCameraSensor(
          type: map['type'] as String,
          zoomFactor: (map['zoomFactor'] as num).toDouble(),
          deviceId: map['deviceId'] as String,
          displayName: map['displayName'] as String,
        );
      }).toList();

      Log.info(
        'Detected ${cameras.length} physical cameras: ${cameras.map((c) => '${c.displayName} (${c.zoomFactor}x)').join(', ')}',
        name: 'CameraZoomDetector',
        category: LogCategory.system,
      );

      return cameras;
    } catch (e) {
      Log.error(
        'Failed to detect physical cameras: $e',
        name: 'CameraZoomDetector',
        category: LogCategory.system,
      );
      return [];
    }
  }

  /// Get back-facing cameras only (for zoom UI)
  static Future<List<PhysicalCameraSensor>> getBackCameras() async {
    final allCameras = await getPhysicalCameras();
    return allCameras.where((c) => c.type != 'front').toList();
  }

  /// Get sorted back cameras by zoom factor (ascending order)
  static Future<List<PhysicalCameraSensor>> getSortedBackCameras() async {
    final backCameras = await getBackCameras();
    backCameras.sort((a, b) => a.zoomFactor.compareTo(b.zoomFactor));
    return backCameras;
  }
}
