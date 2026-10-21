/// CameraX-backed [VideoRecorder] using the `camera` plugin.
///
/// Timing limitation (documented, FR-014): the plugin does not expose
/// CameraX's `Recording` start callback, so `video_start_ns` is sampled
/// natively when `startVideoRecording` completes. This is the closest
/// available recording-start event — it is NOT the exposure timestamp of the
/// first encoded frame.
library;

import 'dart:io';

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';

/// Maps a requested resolution to the closest camera-plugin preset, keyed by
/// the short (vertical) side per the 480p/720p/1080p convention.
/// Exposed for unit testing.
ResolutionPreset resolutionPresetFor(int width, int height) {
  final shortSide = width < height ? width : height;
  if (shortSide <= 240) return ResolutionPreset.low;
  if (shortSide <= 480) return ResolutionPreset.medium;
  if (shortSide <= 720) return ResolutionPreset.high;
  if (shortSide <= 1080) return ResolutionPreset.veryHigh;
  if (shortSide <= 1440) return ResolutionPreset.ultraHigh;
  return ResolutionPreset.max;
}

class CameraVideoRecorder implements VideoRecorder {
  CameraVideoRecorder({required Future<int> Function() elapsedNs})
    : _elapsedNs = elapsedNs;

  final Future<int> Function() _elapsedNs;

  CameraController? _controller;
  String _presetLabel = '';
  bool _recording = false;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> initialize(VideoConfig config) async {
    await dispose();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraFailure('No cameras available on this device');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final preset = resolutionPresetFor(config.width, config.height);
      _presetLabel = preset.name;
      final controller = CameraController(
        selected,
        preset,
        enableAudio: config.audio,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await _enableContinuousFocus(controller);
      _controller = controller;
    } on CameraFailure {
      rethrow;
    } catch (error) {
      throw CameraFailure('Camera initialization failed', cause: error);
    }
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraFailure('Camera preview requested before initialization');
    }
    return _FocusablePreview(controller: controller);
  }

  /// Continuous autofocus/auto-exposure keep the viewfinder sharp while
  /// driving. Devices without focus control (fixed-focus lenses) report a
  /// CameraException; the default lens behaviour is then the best available.
  static Future<void> _enableContinuousFocus(
    CameraController controller,
  ) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } on CameraException {
      return;
    }
  }

  @override
  Future<VideoStartInfo> startRecording() async {
    final controller = _requireController();
    if (_recording) {
      throw CameraFailure('startRecording called while already recording');
    }
    try {
      await controller.startVideoRecording();
      final startNs = await _elapsedNs();
      _recording = true;
      return VideoStartInfo(
        videoStartNs: startNs,
        reference: 'camera_plugin_start_completed',
        resolutionPreset: _presetLabel,
      );
    } catch (error) {
      throw CameraFailure('Failed to start video recording', cause: error);
    }
  }

  @override
  Future<VideoEndInfo> stopRecording(String outputPath) async {
    final controller = _requireController();
    if (!_recording) {
      throw CameraFailure('stopRecording called while not recording');
    }
    try {
      final file = await controller.stopVideoRecording();
      final endNs = await _elapsedNs();
      _recording = false;
      await file.saveTo(outputPath);
      final size = await File(outputPath).length();
      return VideoEndInfo(videoEndNs: endNs, fileSizeBytes: size);
    } catch (error) {
      throw CameraFailure('Failed to stop and finalize video', cause: error);
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    _recording = false;
    if (controller != null) {
      await controller.dispose();
    }
  }

  CameraController _requireController() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraFailure('Camera used before initialization');
    }
    return controller;
  }
}

/// Full-frame preview with tap-to-focus. A tap meters focus and exposure on
/// that point and briefly shows a focus square.
class _FocusablePreview extends StatefulWidget {
  const _FocusablePreview({required this.controller});

  final CameraController controller;

  @override
  State<_FocusablePreview> createState() => _FocusablePreviewState();
}

class _FocusablePreviewState extends State<_FocusablePreview> {
  Offset? _focusPoint;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _focusAt(Offset local, Size size) async {
    setState(() => _focusPoint = local);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    final point = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    try {
      await widget.controller.setFocusPoint(point);
      await widget.controller.setExposurePoint(point);
    } on CameraException {
      // Point metering unsupported: continuous autofocus stays in effect.
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CameraPreview(
      widget.controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final point = _focusPoint;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _focusAt(details.localPosition, size),
            child: Stack(
              children: [
                if (point != null)
                  Positioned(
                    left: point.dx - 32,
                    top: point.dy - 32,
                    child: IgnorePointer(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFFD60A),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
