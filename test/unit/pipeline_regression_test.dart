import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/data/session/session_paths.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/data/session/session_writer.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/services/recovery/recovery_service.dart';
import 'package:roadsense_logger/services/resampling/resampler.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pipeline_regression');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('GPS fixes before video start get a negative t_video_s', () async {
    final paths = SessionPaths(tempDir);
    final writer = SessionWriter(
      paths: paths,
      clockMapping: const ClockMapping(
        sessionStartElapsedNs: 1_000_000_000,
        sessionStartUnixMs: 1_700_000_000_000,
      ),
      nowNs: () => 0,
    );
    await writer.open();
    writer.addGpsFix(
      const GpsFix(
        timestampNs: 1_250_000_000,
        unixTimeMs: 1_700_000_000_250,
        latitude: 12.5,
        longitude: 77.5,
      ),
    );
    writer.setVideoStartNs(1_500_000_000);
    writer.flush();

    final row = File(paths.gpsPartFile).readAsLinesSync()[1].split(',');
    expect(row[1], '-0.25');
    expect(writer.gpsRowCount, 1);
  });

  test('resampling a 10 minute session finishes promptly', () {
    final events = <ImuEvent>[
      for (var i = 0; i < 120000; i++) ...[
        ImuEvent(
          timestampNs: i * 5000000,
          sensor: ImuSensorKind.acc,
          x: 0,
          y: 0,
          z: 9.8,
        ),
        ImuEvent(
          timestampNs: i * 5000000,
          sensor: ImuSensorKind.gyro,
          x: 0,
          y: 0,
          z: 0,
        ),
      ],
    ];
    final stopwatch = Stopwatch()..start();
    final result = Resampler(rateHz: 100, maxImuGapMs: 50, maxGpsAgeS: 2)
        .generate(
          imuEvents: events,
          gpsFixes: const [],
          videoStartNs: 0,
          videoEndNs: 599 * 1000000000,
          clockMapping: const ClockMapping(
            sessionStartElapsedNs: 0,
            sessionStartUnixMs: 0,
          ),
        );
    expect(result.rows.length, 59901);
    expect(result.accMissingRows, 0);
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });

  group('RecoveryService', () {
    Directory sessionDir(String name) =>
        Directory('${tempDir.path}/$name')..createSync(recursive: true);

    test('keeps real metadata of a finalized incomplete session', () async {
      final dir = sessionDir('session_20261021_100000_aaaaaa');
      final original = {
        'session_id': 'session_20261021_100000_aaaaaa',
        'status': 'incomplete',
        'clock_mapping': {'session_start_elapsed_ns': 42},
      };
      File('${dir.path}/metadata.json').writeAsStringSync(jsonEncode(original));

      final report = await RecoveryService(
        repository: SessionRepository(rootDir: tempDir),
      ).recoverAll();

      expect(report.recoveredSessions, isEmpty);
      expect(
        jsonDecode(File('${dir.path}/metadata.json').readAsStringSync()),
        original,
      );
    });

    test('interleaved ACC/GYRO rows are not truncated as corrupt', () async {
      final dir = sessionDir('session_20261021_110000_bbbbbb');
      File('${dir.path}/imu_raw.csv.part').writeAsStringSync(
        'timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z\n'
        '100,0.1,0,ACC,1,1,1\n'
        '200,0.2,0,ACC,1,1,1\n'
        '150,0.15,0,GYRO,0,0,0\n'
        '250,0.25,0,GYRO,0,0,0\n',
      );

      await RecoveryService(
        repository: SessionRepository(rootDir: tempDir),
      ).recoverAll();

      expect(File('${dir.path}/imu_raw.csv').readAsLinesSync().length, 5);
    });
  });
}
