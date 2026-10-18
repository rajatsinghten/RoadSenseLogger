/// Video capture seam (FR-010..015). Implemented by the CameraX-backed
/// camera-plugin implementation and by fakes in tests.
library;

import 'package:flutter/widgets.dart';

/// Requested video configuration (achieved configuration is reported
/// separately — NFR-005).
class VideoConfig {
  const VideoConfig({
    required this.width,
    required this.height,
    required this.fps,
    required this.audio,
  });

  final int width;
  final int height;

  /// Target frame rate. Not controllable through the camera plugin on
  /// Android; recorded as a request only (see `specs/architecture.md` §6).
  final int fps;
  final bool audio;
}

/// Captured recording-start reference (FR-014).
class VideoStartInfo {
  const VideoStartInfo({
    required this.videoStartNs,
    required this.reference,
    required this.resolutionPreset,
  });

  /// Elapsed-realtime nanoseconds sampled at the recording-start event.
  final int videoStartNs;

  /// How [videoStartNs] was obtained; never claimed to be the exposure time
  /// of the first encoded frame.
  final String reference;

  /// Camera plugin resolution preset actually requested from CameraX.
  final String resolutionPreset;
}

/// Captured recording-stop/finalization reference.
class VideoEndInfo {
  const VideoEndInfo({required this.videoEndNs, required this.fileSizeBytes});

  final int videoEndNs;
  final int fileSizeBytes;
}

abstract interface class VideoRecorder {
  bool get isInitialized;
  bool get isRecording;

  Future<void> initialize(VideoConfig config);

  /// Live camera preview widget (requires initialization).
  Widget buildPreview();

  /// Starts recording and captures `video_start_ns` (FR-014).
  Future<VideoStartInfo> startRecording();

  /// Stops recording, finalizes the file at [outputPath] and captures
  /// `video_end_ns`.
  Future<VideoEndInfo> stopRecording(String outputPath);

  Future<void> dispose();
}
