import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/domain/models/sensor_info.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/location/location_source.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/native/native_control.dart';
import 'package:roadsense_logger/services/sensors/sensor_source.dart';

/// Controllable monotonic clock for deterministic tests.
class FakeClock {
  int nowNs = 0;
}

class FakeSensorSource implements SensorSource {
  final StreamController<NativeSensorBatch> controller =
      StreamController<NativeSensorBatch>.broadcast(sync: true);

  int startCount = 0;
  int stopCount = 0;
  int accPeriodUs = -1;
  int gyroPeriodUs = -1;
  bool gyroscopeAvailable = true;

  @override
  Stream<NativeSensorBatch> get sensorBatches => controller.stream;

  @override
  Future<({bool accelerometerAvailable, bool gyroscopeAvailable})>
  startSensors({required int accPeriodUs, required int gyroPeriodUs}) async {
    startCount++;
    this.accPeriodUs = accPeriodUs;
    this.gyroPeriodUs = gyroPeriodUs;
    return (
      accelerometerAvailable: true,
      gyroscopeAvailable: gyroscopeAvailable,
    );
  }

  @override
  Future<void> stopSensors() async {
    stopCount++;
  }

  @override
  Future<List<SensorInfo>> getSensorInfo() async => const [
    SensorInfo(kind: 'ACC', name: 'Fake ACC', vendor: 'Fake'),
    SensorInfo(kind: 'GYRO', name: 'Fake GYRO', vendor: 'Fake'),
  ];
}

class FakeLocationSource implements LocationSource {
  final StreamController<NativeGpsEvent> controller =
      StreamController<NativeGpsEvent>.broadcast(sync: true);

  int startCount = 0;
  int stopCount = 0;
  bool failStart = false;

  @override
  Stream<NativeGpsEvent> get gpsEvents => controller.stream;

  @override
  Future<void> startGps({required int intervalMs}) async {
    if (failStart) {
      throw Exception('location unavailable');
    }
    startCount++;
  }

  @override
  Future<void> stopGps() async {
    stopCount++;
  }
}

class FakeVideoRecorder implements VideoRecorder {
  bool initialized = false;
  bool recording = false;
  bool disposed = false;
  VideoConfig? config;
  int initializeCount = 0;

  /// Video recording-start reference timestamp returned by [startRecording].
  int videoStartNs = 0;

  /// Video finalization timestamp returned by [stopRecording].
  int videoEndNs = 0;

  /// Hook executed inside [startRecording] (to simulate pre-roll events).
  Future<void> Function()? duringStartRecording;

  /// When set, [initialize] throws.
  Object? initializeError;

  @override
  bool get isInitialized => initialized;

  @override
  bool get isRecording => recording;

  @override
  Future<void> initialize(VideoConfig config) async {
    initializeCount++;
    if (initializeError != null) {
      throw initializeError!;
    }
    this.config = config;
    initialized = true;
  }

  @override
  Widget buildPreview() => const SizedBox(width: 100, height: 100);

  @override
  Future<VideoStartInfo> startRecording() async {
    recording = true;
    await duringStartRecording?.call();
    return VideoStartInfo(
      videoStartNs: videoStartNs,
      reference: 'camera_plugin_start_completed',
      resolutionPreset: 'veryHigh',
    );
  }

  @override
  Future<VideoEndInfo> stopRecording(String outputPath) async {
    recording = false;
    await File(outputPath).writeAsBytes(const [0, 0, 0, 0]);
    return VideoEndInfo(videoEndNs: videoEndNs, fileSizeBytes: 4);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    initialized = false;
  }
}

class FakeNativeControl implements NativeControl {
  FakeNativeControl({required this.clock});

  final FakeClock clock;
  int freeStorageBytes = 10 * 1024 * 1024 * 1024;
  int startForegroundCount = 0;
  int stopForegroundCount = 0;

  @override
  Future<int> getElapsedNs() async => clock.nowNs;

  @override
  Future<ClockMapping> getClockMapping() async => ClockMapping(
    sessionStartElapsedNs: clock.nowNs,
    sessionStartUnixMs: 1_700_000_000_000,
  );

  @override
  Future<void> startForeground({required bool audio}) async {
    startForegroundCount++;
  }

  @override
  Future<void> stopForeground() async {
    stopForegroundCount++;
  }

  @override
  Future<DeviceInfo> getDeviceInfo() async => const DeviceInfo(
    manufacturer: 'FakeMaker',
    model: 'FakePhone',
    androidVersion: '15',
  );

  @override
  Future<int> getFreeStorageBytes() async => freeStorageBytes;

  @override
  Future<Map<String, bool>> checkPermissions(List<String> permissions) async =>
      {for (final p in permissions) p: true};

  @override
  Future<Map<String, bool>> requestPermissions(
    List<String> permissions,
  ) async => {for (final p in permissions) p: true};
}
