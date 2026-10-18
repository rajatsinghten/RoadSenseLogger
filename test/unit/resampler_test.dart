import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/services/resampling/resampler.dart';

void main() {
  const mapping = ClockMapping(
    sessionStartElapsedNs: 0,
    sessionStartUnixMs: 1_700_000_000_000,
  );
  // Video interval [0 s, 1 s] in nanoseconds.
  const videoStartNs = 0;
  const videoEndNs = 1_000_000_000;

  ImuEvent acc(int ts, double x, {double y = 0, double z = 0}) =>
      ImuEvent(timestampNs: ts, sensor: ImuSensorKind.acc, x: x, y: y, z: z);

  ImuEvent gyro(int ts, double z) =>
      ImuEvent(timestampNs: ts, sensor: ImuSensorKind.gyro, x: 0, y: 0, z: z);

  GpsFix fix(int ts, {double lat = 12.0, double lon = 77.0, double? speed}) =>
      GpsFix(
        timestampNs: ts,
        unixTimeMs: ts ~/ 1000000,
        latitude: lat,
        longitude: lon,
        speedMps: speed,
      );

  ResampleResult run(
    List<ImuEvent> imu,
    List<GpsFix> gps, {
    double rateHz = 100,
    double maxImuGapMs = 250,
    double maxGpsAgeS = 5,
    int startNs = videoStartNs,
    int endNs = videoEndNs,
  }) {
    final resampler = Resampler(
      rateHz: rateHz,
      maxImuGapMs: maxImuGapMs,
      maxGpsAgeS: maxGpsAgeS,
    );
    return resampler.generate(
      imuEvents: imu,
      gpsFixes: gps,
      videoStartNs: startNs,
      videoEndNs: endNs,
      clockMapping: mapping,
    );
  }

  group('grid generation', () {
    test('100 Hz over 1 s yields 101 uniform rows', () {
      final result = run(const [], const []);
      expect(result.rows.length, 101);
      for (var i = 0; i < result.rows.length; i++) {
        expect(result.rows[i].tVideoS, closeTo(i / 100, 1e-12));
      }
    });

    test('no cumulative drift at the far end', () {
      final result = run(
        const [],
        const [],
        rateHz: 1,
        endNs: 3_600_000_000_000,
      );
      expect(result.rows.length, 3601);
      expect(result.rows.last.tVideoS, closeTo(3600.0, 1e-9));
    });

    test('grid boundaries are inclusive at start and at exact end points', () {
      final result = run(const [], const []);
      expect(result.rows.first.tVideoS, 0);
      expect(result.rows.last.tVideoS, closeTo(1.0, 1e-12));
    });

    test('non-divisible interval ends at the largest grid point <= t1', () {
      // 0.005 s interval at 100 Hz: grid points 0 and 0.01? no — floor(0.5)=0.
      final result = run(const [], const [], endNs: 5_000_000);
      expect(result.rows.length, 1);
      expect(result.rows.single.tVideoS, 0);
    });

    test('zero-length interval yields a single row', () {
      final result = run(const [], const [], endNs: 0);
      expect(result.rows.length, 1);
    });
  });

  group('IMU interpolation', () {
    test('interpolates linearly between bracketing samples', () {
      final result = run([acc(0, 0), acc(200_000_000, 10)], const []);
      // Grid at 0.1 s is midway between the two samples.
      final row = result.rows[10];
      expect(row.accX, closeTo(5, 1e-6));
    });

    test('exact sample timestamps take the sample value', () {
      final result = run([acc(100_000_000, 7)], const []);
      expect(result.rows[10].accX, 7);
    });

    test('large gaps yield missing values, not interpolation', () {
      final result = run(
        [acc(0, 0), acc(900_000_000, 10)],
        const [],
        maxImuGapMs: 250,
      );
      expect(result.rows[10].accX, isNull);
      expect(result.rows[89].accX, isNull);
      // The exact sample at 0.9 s is still used (no interpolation needed).
      expect(result.rows[90].accX, 10);
    });

    test('gap exactly at threshold is interpolated', () {
      final result = run(
        [acc(0, 0), acc(250_000_000, 10)],
        const [],
        maxImuGapMs: 250,
      );
      expect(result.rows[10].accX, closeTo(4, 1e-6));
    });

    test('missing gyro leaves gyro columns empty but keeps acc', () {
      final result = run(
        [acc(0, 1), acc(1_000_000_000, 1)],
        const [],
        maxImuGapMs: 2000,
      );
      expect(result.rows[50].accX, closeTo(1, 1e-9));
      expect(result.rows[50].gyroX, isNull);
      expect(result.rows[50].gyroZ, isNull);
      expect(result.gyroMissingRows, result.rows.length);
    });

    test('gyro channels interpolate like acc channels', () {
      final result = run([gyro(0, 0), gyro(200_000_000, 4)], const []);
      expect(result.rows[10].gyroZ, closeTo(2, 1e-6));
    });

    test('duplicate timestamps use the last-arriving value at exact match', () {
      final result = run([
        acc(100_000_000, 1),
        acc(100_000_000, 2),
        acc(100_000_000, 3),
        acc(200_000_000, 5),
      ], const []);
      expect(result.rows[10].accX, 3);
    });

    test('empty inputs produce all-missing rows', () {
      final result = run(const [], const []);
      expect(
        result.rows.every((r) => r.accX == null && r.gyroX == null),
        isTrue,
      );
      expect(result.accMissingRows, result.rows.length);
    });

    test('no interpolation across the recording start boundary', () {
      final result = run([acc(500_000_000, 4)], const []);
      expect(result.rows.first.accX, isNull); // t=0 has no left sample
    });

    test('counts events outside the merged interval without using them', () {
      final result = run([
        acc(-100_000_000, 99), // before video start
        acc(500_000_000, 1),
        acc(1_200_000_000, 99), // after video end
      ], const []);
      expect(result.accEventsOutsideInterval, 2);
    });
  });

  group('GPS forward-fill', () {
    test('uses the latest fix at or before the grid point', () {
      final result = run(const [], [
        fix(0, lat: 1, lon: 1),
        fix(500_000_000, lat: 2, lon: 2),
      ]);
      expect(result.rows[0].latitude, 1);
      expect(result.rows[49].latitude, 1);
      expect(result.rows[50].latitude, 2);
    });

    test('never uses future fixes', () {
      final result = run(const [], [fix(800_000_000, lat: 5)]);
      expect(result.rows[0].latitude, isNull);
      expect(result.rows[79].latitude, isNull);
      expect(result.rows[80].latitude, 5);
    });

    test('reports gps_age_s at every filled row', () {
      final result = run(const [], [fix(0)], maxGpsAgeS: 5);
      expect(result.rows[0].gpsAgeS, closeTo(0, 1e-9));
      expect(result.rows[10].gpsAgeS, closeTo(0.1, 1e-9));
    });

    test('stale fixes produce empty GPS fields but keep gps_age_s', () {
      final result = run(const [], [fix(0, lat: 3, speed: 9)], maxGpsAgeS: 0.5);
      final staleRow = result.rows[60]; // 0.6 s old
      expect(staleRow.latitude, isNull);
      expect(staleRow.speedMps, isNull);
      expect(staleRow.gpsAgeS, closeTo(0.6, 1e-9));
      expect(result.gpsStaleRows > 0, isTrue);
    });

    test('no fixes yields missing GPS fields including gps_age_s', () {
      final result = run(const [], const []);
      expect(result.rows[0].latitude, isNull);
      expect(result.rows[0].gpsAgeS, isNull);
      expect(result.gpsMissingRows, result.rows.length);
    });

    test('counts GPS fixes outside the merged interval', () {
      final result = run(const [], [
        fix(-50_000_000),
        fix(500_000_000),
        fix(1_100_000_000),
      ]);
      expect(result.gpsFixesOutsideInterval, 2);
    });
  });

  group('timestamps and csv output', () {
    test('unix_time_ms follows the clock mapping', () {
      final result = run(const [], const [], rateHz: 10);
      expect(result.rows[0].unixTimeMs, 1_700_000_000_000);
      expect(result.rows[1].unixTimeMs, 1_700_000_000_100);
    });

    test('csv rows follow the merged schema and keep label empty', () {
      final result = run([acc(0, 1, y: 2, z: 3)], const []);
      final line = result.rows.first.toCsv();
      final fields = line.split(',');
      expect(MergedRow.header.split(',').length, fields.length);
      expect(fields.last, '');
      expect(fields[0], '0');
      expect(fields[2], '1');
      expect(fields[3], '2');
      expect(fields[4], '3');
      expect(fields[8], ''); // missing GPS latitude
    });
  });
}
