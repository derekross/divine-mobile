// ABOUTME: Riverpod state management for VineRecordingController
// ABOUTME: Provides reactive state updates for recording UI without ChangeNotifier

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/services/vine_recording_controller.dart';

/// State class for VineRecording that captures all necessary UI state
class VineRecordingUIState {
  const VineRecordingUIState({
    required this.recordingState,
    required this.progress,
    required this.totalRecordedDuration,
    required this.remainingDuration,
    required this.canRecord,
    required this.segments,
  });

  final VineRecordingState recordingState;
  final double progress;
  final Duration totalRecordedDuration;
  final Duration remainingDuration;
  final bool canRecord;
  final List<RecordingSegment> segments;

  VineRecordingUIState copyWith({
    VineRecordingState? recordingState,
    double? progress,
    Duration? totalRecordedDuration,
    Duration? remainingDuration,
    bool? canRecord,
    List<RecordingSegment>? segments,
  }) {
    return VineRecordingUIState(
      recordingState: recordingState ?? this.recordingState,
      progress: progress ?? this.progress,
      totalRecordedDuration:
          totalRecordedDuration ?? this.totalRecordedDuration,
      remainingDuration: remainingDuration ?? this.remainingDuration,
      canRecord: canRecord ?? this.canRecord,
      segments: segments ?? this.segments,
    );
  }
}

/// StateNotifier that wraps VineRecordingController and provides reactive updates
class VineRecordingNotifier extends StateNotifier<VineRecordingUIState> {
  VineRecordingNotifier(this._controller)
      : super(
          VineRecordingUIState(
            recordingState: _controller.state,
            progress: _controller.progress,
            totalRecordedDuration: _controller.totalRecordedDuration,
            remainingDuration: _controller.remainingDuration,
            canRecord: _controller.canRecord,
            segments: _controller.segments,
          ),
        ) {
    // Set up callback for recording progress updates
    _controller.setStateChangeCallback(updateState);
  }

  final VineRecordingController _controller;

  /// Update the state based on the current controller state
  void updateState() {
    state = VineRecordingUIState(
      recordingState: _controller.state,
      progress: _controller.progress,
      totalRecordedDuration: _controller.totalRecordedDuration,
      remainingDuration: _controller.remainingDuration,
      canRecord: _controller.canRecord,
      segments: _controller.segments,
    );
  }

  // Delegate methods to the controller
  Future<void> initialize() async {
    await _controller.initialize();
    updateState();
  }

  Future<void> startRecording() async {
    await _controller.startRecording();
    updateState();
  }

  Future<void> stopRecording() async {
    await _controller.stopRecording();
    updateState();
  }

  Future<File?> finishRecording() async {
    final result = await _controller.finishRecording();
    updateState();
    return result;
  }

  void reset() {
    _controller.reset();
    updateState();
  }

  @override
  void dispose() {
    // Clear callback to prevent memory leaks
    _controller.setStateChangeCallback(null);
    _controller.dispose();
    super.dispose();
  }

  // Getters that delegate to controller
  VineRecordingController get controller => _controller;
}

/// Provider for VineRecordingController with reactive state management
final vineRecordingProvider =
    StateNotifierProvider<VineRecordingNotifier, VineRecordingUIState>((ref) {
  final controller = VineRecordingController();
  final notifier = VineRecordingNotifier(controller);

  ref.onDispose(() {
    notifier.dispose();
  });

  return notifier;
});
