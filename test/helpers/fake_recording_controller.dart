import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';
import 'package:roadsense_logger/services/location/gps_recorder.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';
import 'package:roadsense_logger/services/sensors/sensor_recorder.dart';

/// UI-level recording controller fake (no file I/O, fully controllable).
class FakeRecordingController implements RecordingController {
  @override
  RecordingState state = RecordingState.idle;
  final StreamController<RecordingSnapshot> snapshotController =
      StreamController<RecordingSnapshot>.broadcast(sync: true);

  SessionConfig? startedConfig;
  int startCount = 0;
  int stopCount = 0;
  int resetCount = 0;
  int prepareCount = 0;
  Object? startError;
  Object? stopError;
  Object? previewError;
  Widget preview = const SizedBox(width: 120, height: 120);

  @override
  SessionMetadata? lastMetadata;

  @override
  Stream<RecordingSnapshot> get snapshots => snapshotController.stream;

  @override
  RecordingSnapshot snapshot() => RecordingSnapshot(
    state: state,
    elapsedS: 0,
    sensorReport: const SensorReport(
      accCount: 0,
      gyroCount: 0,
      accAvgRateHz: null,
      gyroAvgRateHz: null,
      accLiveRateHz: null,
      gyroLiveRateHz: null,
      accLastMagnitude: null,
      gyroLastMagnitude: null,
      gyroscopeAvailable: true,
      gapCount: 0,
      droppedCount: 0,
    ),
    gpsReport: const GpsReport(
      acceptedCount: 0,
      rejectedCount: 0,
      lastFix: null,
      lastFixAgeS: null,
      outageCount: 0,
    ),
    freeStorageBytes: 8 * 1024 * 1024 * 1024,
    warnings: const [],
  );

  void _emit() => snapshotController.add(snapshot());

  @override
  Future<void> prepareCamera(VideoConfig config) async {
    prepareCount++;
  }

  @override
  Widget buildPreview() {
    if (previewError != null) throw previewError!;
    return preview;
  }

  @override
  Future<void> start(SessionConfig config) async {
    if (startError != null) throw startError!;
    startCount++;
    startedConfig = config;
    state = RecordingState.recording;
    _emit();
  }

  @override
  Future<void> stop() async {
    if (stopError != null) throw stopError!;
    stopCount++;
    state = RecordingState.completed;
    _emit();
  }

  @override
  Future<void> interrupt(String reason) async {
    state = RecordingState.interrupted;
    _emit();
  }

  @override
  void reset() {
    resetCount++;
    state = RecordingState.idle;
    _emit();
  }
}
