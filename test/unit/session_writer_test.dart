import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/data/session/session_paths.dart';
import 'package:roadsense_logger/data/session/session_writer.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';

void main() {
  late Directory tempDir;
  late SessionPaths paths;
  const mapping = ClockMapping(
    sessionStartElapsedNs: 1_000_000_000,
    sessionStartUnixMs: 1_700_000_000_000,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_writer_test');
    paths = SessionPaths(tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  SessionWriter buildWriter({int nowNs = 0, int maxPending = 50000}) {
    return SessionWriter(
      paths: paths,
      clockMapping: mapping,
      nowNs: () => nowNs,
      maxPendingPreRollRows: maxPending,
    );
  }

  group('SessionWriter', () {
    test('writes exact imu schema order and values', () async {
      final writer = buildWriter();
      await writer.open();
      writer.setVideoStartNs(1_500_000_000);
      writer.addImuEvents(const [
        ImuEvent(
          timestampNs: 1_600_000_000,
          sensor: ImuSensorKind.acc,
          x: 0.5,
          y: -0.25,
          z: 9.81,
        ),
      ]);
      writer.flush();

      final lines = File(
        paths.imuPartFile,
      ).readAsStringSync().trim().split('\n');
      expect(lines.first, SessionWriter.imuHeader);
      final fields = lines[1].split(',');
      expect(fields.length, 7);
      expect(fields[0], '1600000000');
      expect(fields[1], '0.1'); // t_video_s
      expect(fields[2], '1700000000600'); // unix_time_ms
      expect(fields[3], 'ACC');
      expect(fields[4], '0.5');
      expect(fields[5], '-0.25');
      expect(fields[6], '9.81');
    });

    test('preserves pre-roll events with negative t_video_s', () async {
      final writer = buildWriter();
      await writer.open();
      writer.addImuEvents(const [
        ImuEvent(
          timestampNs: 1_400_000_000,
          sensor: ImuSensorKind.gyro,
          x: 0,
          y: 0,
          z: 0,
        ),
      ]);
      writer.setVideoStartNs(1_500_000_000);
      writer.flush();

      final lines = File(
        paths.imuPartFile,
      ).readAsStringSync().trim().split('\n');
      final fields = lines[1].split(',');
      expect(fields[1], '-0.1');
    });

    test('gps missing values are empty fields, never zero', () async {
      final writer = buildWriter();
      await writer.open();
      writer.setVideoStartNs(1_000_000_000);
      writer.addGpsFix(
        const GpsFix(
          timestampNs: 1_200_000_000,
          unixTimeMs: 1_700_000_000_200,
          latitude: 12.5,
          longitude: 77.5,
        ),
      );
      writer.flush();

      final lines = File(
        paths.gpsPartFile,
      ).readAsStringSync().trim().split('\n');
      expect(lines.first, SessionWriter.gpsHeader);
      final fields = lines[1].split(',');
      expect(fields.length, 9);
      expect(fields[3], '12.5');
      expect(fields[5], ''); // altitude missing
      expect(fields[6], ''); // speed missing
      expect(fields[7], ''); // bearing missing
      expect(fields[8], ''); // accuracy missing
    });

    test('rows stay buffered until flush', () async {
      final writer = buildWriter();
      await writer.open();
      writer.setVideoStartNs(1_000_000_000);
      writer.addImuEvents(const [
        ImuEvent(
          timestampNs: 1_100_000_000,
          sensor: ImuSensorKind.acc,
          x: 1,
          y: 1,
          z: 1,
        ),
      ]);

      var content = File(paths.imuPartFile).readAsStringSync();
      expect(content.trim().split('\n').length, 1); // header only

      writer.flush();
      content = File(paths.imuPartFile).readAsStringSync();
      expect(content.trim().split('\n').length, 2);
      expect(writer.imuRowCount, 1);
    });

    test('timed flush triggers after the flush interval', () async {
      var now = 0;
      final writer = SessionWriter(
        paths: paths,
        clockMapping: mapping,
        nowNs: () => now,
        flushIntervalNs: 1000,
      );
      await writer.open();
      writer.setVideoStartNs(1_000_000_000);

      writer.addImuEvents(const [
        ImuEvent(
          timestampNs: 1_100_000_000,
          sensor: ImuSensorKind.acc,
          x: 0,
          y: 0,
          z: 0,
        ),
      ]);
      expect(
        File(paths.imuPartFile).readAsStringSync().trim().split('\n').length,
        1,
      );

      now = 2000;
      writer.addImuEvents(const [
        ImuEvent(
          timestampNs: 1_200_000_000,
          sensor: ImuSensorKind.acc,
          x: 0,
          y: 0,
          z: 0,
        ),
      ]);
      expect(
        File(paths.imuPartFile).readAsStringSync().trim().split('\n').length,
        3,
      );
    });

    test('bounded pre-roll buffer drops oldest rows and counts them', () async {
      final writer = buildWriter(maxPending: 2);
      await writer.open();
      writer.addImuEvents(const [
        ImuEvent(
          timestampNs: 1_000_000_000,
          sensor: ImuSensorKind.acc,
          x: 1,
          y: 1,
          z: 1,
        ),
        ImuEvent(
          timestampNs: 1_100_000_000,
          sensor: ImuSensorKind.acc,
          x: 2,
          y: 2,
          z: 2,
        ),
        ImuEvent(
          timestampNs: 1_200_000_000,
          sensor: ImuSensorKind.acc,
          x: 3,
          y: 3,
          z: 3,
        ),
      ]);
      expect(writer.droppedPreRollRows, 1);

      writer.setVideoStartNs(1_000_000_000);
      writer.flush();
      final lines = File(
        paths.imuPartFile,
      ).readAsStringSync().trim().split('\n');
      expect(lines.length, 3); // header + 2 surviving rows
    });

    test('finalizeNames renames part files to final names', () async {
      final writer = buildWriter();
      await writer.open();
      writer.setVideoStartNs(1_000_000_000);
      await writer.finalizeNames();

      expect(File(paths.imuFile).existsSync(), isTrue);
      expect(File(paths.gpsFile).existsSync(), isTrue);
      expect(File(paths.imuPartFile).existsSync(), isFalse);
      expect(writer.isClosed, isTrue);
    });

    test('write failure surfaces as StorageFailure', () async {
      final writer = buildWriter();
      await writer.open();
      writer.setVideoStartNs(1_000_000_000);
      await tempDir.delete(recursive: true);

      expect(() {
        writer.addImuEvents(const [
          ImuEvent(
            timestampNs: 1_100_000_000,
            sensor: ImuSensorKind.acc,
            x: 0,
            y: 0,
            z: 0,
          ),
        ]);
        writer.flush();
      }, throwsA(isA<StorageFailure>()));
    });
  });
}
