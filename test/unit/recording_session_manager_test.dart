import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/data/session/session_store.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';

import '../helpers/fakes.dart';

void main() {
  late Directory tempDir;
  late FakeClock clock;
  late FakeSensorSource sensors;
  late FakeLocationSource location;
  late FakeVideoRecorder video;
  late FakeNativeControl native;
  late RecordingSessionManager manager;

  const config = SessionConfig(
    vehicleType: VehicleType.car,
    mountPosition: MountPosition.dashboard,
    notes: 'test',
  );

  ImuEvent acc(int ts) =>
      ImuEvent(timestampNs: ts, sensor: ImuSensorKind.acc, x: 0, y: 0, z: 9.8);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('recording_manager_test');
    clock = FakeClock()..nowNs = 1_000_000_000;
    sensors = FakeSensorSource();
    location = FakeLocationSource();
    video = FakeVideoRecorder()
      ..videoStartNs = 2_000_000_000
      ..videoEndNs = 3_000_000_000;
    native = FakeNativeControl(clock: clock);
    manager = RecordingSessionManager(
      sensors: sensors,
      location: location,
      video: video,
      native: native,
      store: SessionStore(
        rootDir: tempDir,
        now: () => DateTime(2026, 10, 18, 12),
        random: Random(42),
      ),
      monotonicNow: () => clock.nowNs,
      minFreeStorageBytes: 1024,
      tickInterval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await manager.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('RecordingSessionManager lifecycle', () {
    test('happy path records and finalizes a validated session', () async {
      final states = <RecordingState>[];
      manager.stateChanges.listen(states.add);

      // Pre-roll events captured between sensor start and video start.
      video.duringStartRecording = () async {
        sensors.controller.add(
          NativeSensorBatch(
            sensor: ImuSensorKind.acc,
            events: [acc(1_900_000_000)],
          ),
        );
      };

      await manager.start(config);
      expect(manager.state, RecordingState.recording);
      expect(sensors.startCount, 1);
      expect(location.startCount, 1);
      expect(native.startForegroundCount, 1);

      sensors.controller.add(
        NativeSensorBatch(
          sensor: ImuSensorKind.acc,
          events: [acc(2_100_000_000), acc(2_900_000_000)],
        ),
      );
      location.controller.add(
        NativeGpsEvent.accepted(
          GpsFix(
            timestampNs: 2_500_000_000,
            unixTimeMs: 1_700_000_002_500,
            latitude: 12.97,
            longitude: 77.59,
            speedMps: 8.5,
          ),
        ),
      );

      clock.nowNs = 3_200_000_000;
      await manager.stop();

      expect(manager.state, RecordingState.completed);
      await pumpEventQueue();
      expect(states, [
        RecordingState.preparing,
        RecordingState.recording,
        RecordingState.finalizing,
        RecordingState.completed,
      ]);

      final paths = manager.sessionPaths!;
      for (final file in [
        paths.videoFile,
        paths.imuFile,
        paths.gpsFile,
        paths.mergedFile,
        paths.metadataFile,
        paths.diagnosticsFile,
      ]) {
        expect(File(file).existsSync(), isTrue, reason: file);
      }

      // imu_raw.csv: header + 1 pre-roll + 2 in-video events.
      final imuLines = File(paths.imuFile).readAsLinesSync();
      expect(imuLines.length, 4);
      final preRoll = imuLines[1].split(',');
      expect(preRoll[0], '1900000000');
      expect(preRoll[1].startsWith('-'), isTrue); // negative t_video_s

      // merged.csv: 100 Hz over the 1 s video interval → 101 rows + header.
      final mergedLines = File(paths.mergedFile).readAsLinesSync();
      expect(mergedLines.length, 102);

      final metadata = manager.lastMetadata!;
      expect(metadata.status, SessionStatus.completed);
      expect(metadata.videoStartNs, 2_000_000_000);
      expect(metadata.videoEndNs, 3_000_000_000);
      expect(metadata.durationS, 1.0);
      expect(metadata.mergedRowCount, 101);
      expect(metadata.accStats.eventCount, 3);
      expect(metadata.gpsFixCount, 1);
      expect(metadata.videoStartReference, 'camera_plugin_start_completed');
      expect(metadata.videoRequestedWidth, 1920);
      expect(metadata.gpsDistanceM, isNull); // one fix: not calculable

      expect(sensors.stopCount, 1);
      expect(location.stopCount, 1);
      expect(native.stopForegroundCount, 1);
    });

    test('rejects duplicate start while recording', () async {
      await manager.start(config);
      await expectLater(
        manager.start(config),
        throwsA(isA<StateTransitionError>()),
      );
      expect(manager.state, RecordingState.recording);
      await manager.stop();
    });

    test('rejects stop before start', () async {
      await expectLater(manager.stop(), throwsA(isA<StateTransitionError>()));
    });

    test(
      'camera init failure lands in error state and releases resources',
      () async {
        video.initializeError = CameraFailure('no camera');
        await expectLater(manager.start(config), throwsA(isA<CameraFailure>()));
        expect(manager.state, RecordingState.error);
        expect(video.disposed, isTrue);
      },
    );

    test('low storage blocks recording before capture starts', () async {
      native.freeStorageBytes = 10;
      await expectLater(manager.start(config), throwsA(isA<StorageFailure>()));
      expect(manager.state, RecordingState.error);
      expect(sensors.startCount, 0);
      expect(video.initializeCount, 0);
    });

    test('gps failure is recorded but does not stop recording', () async {
      location.failStart = true;
      await manager.start(config);
      expect(manager.state, RecordingState.recording);
      clock.nowNs = 3_200_000_000;
      await manager.stop();
      expect(manager.state, RecordingState.completed);

      final diagnostics = File(
        manager.sessionPaths!.diagnosticsFile,
      ).readAsStringSync();
      expect(diagnostics, contains('gps_unavailable'));
    });

    test('missing gyroscope is diagnosed', () async {
      sensors.gyroscopeAvailable = false;
      await manager.start(config);
      clock.nowNs = 3_200_000_000;
      await manager.stop();

      final diagnostics = File(
        manager.sessionPaths!.diagnosticsFile,
      ).readAsStringSync();
      expect(diagnostics, contains('gyroscope_unavailable'));
    });

    test('interrupt finalizes and flags the session as interrupted', () async {
      await manager.start(config);
      sensors.controller.add(
        NativeSensorBatch(
          sensor: ImuSensorKind.acc,
          events: [acc(2_100_000_000)],
        ),
      );
      clock.nowNs = 2_500_000_000;
      await manager.interrupt('camera disconnected');

      expect(manager.state, RecordingState.completed);
      final metadata = manager.lastMetadata!;
      expect(metadata.interrupted, isTrue);
      expect(metadata.interruptionReason, 'camera disconnected');
    });

    test('reset returns to idle and clears session data', () async {
      await manager.start(config);
      clock.nowNs = 3_200_000_000;
      await manager.stop();
      manager.reset();
      expect(manager.state, RecordingState.idle);
      expect(manager.lastMetadata, isNotNull); // history retained
    });

    test('snapshot exposes live diagnostics for the UI', () async {
      await manager.start(config);
      sensors.controller.add(
        NativeSensorBatch(
          sensor: ImuSensorKind.acc,
          events: [acc(2_100_000_000)],
        ),
      );
      clock.nowNs = 2_100_000_000;
      final snapshot = manager.snapshot();
      expect(snapshot.state, RecordingState.recording);
      expect(snapshot.sensorReport.accCount, 1);
      expect(snapshot.warnings, contains('No GPS fix received yet'));
      expect(snapshot.elapsedS, closeTo(0.1, 1e-9)); // now 2.1s vs start 2.0s
      clock.nowNs = 3_200_000_000;
      await manager.stop();
    });
  });
}
