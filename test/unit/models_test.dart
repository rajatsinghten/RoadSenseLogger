import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

void main() {
  group('ImuEvent', () {
    test('computes magnitude', () {
      const event = ImuEvent(
        timestampNs: 1,
        sensor: ImuSensorKind.acc,
        x: 3,
        y: 4,
        z: 0,
      );
      expect(event.magnitude, closeTo(5, 1e-9));
    });

    test('maps csv ids', () {
      expect(ImuSensorKind.acc.csvId, 'ACC');
      expect(ImuSensorKind.gyro.csvId, 'GYRO');
      expect(ImuSensorKind.fromCsvId('GYRO'), ImuSensorKind.gyro);
    });
  });

  group('GpsFix.isValid', () {
    test('accepts a valid fix', () {
      expect(
        GpsFix.isValid(latitude: 12.97, longitude: 77.59, timestampNs: 1),
        isTrue,
      );
    });

    test('rejects out-of-range coordinates and zero timestamps', () {
      expect(
        GpsFix.isValid(latitude: 91, longitude: 0, timestampNs: 1),
        isFalse,
      );
      expect(
        GpsFix.isValid(latitude: 0, longitude: 181, timestampNs: 1),
        isFalse,
      );
      expect(
        GpsFix.isValid(latitude: 0, longitude: 0, timestampNs: 0),
        isFalse,
      );
    });
  });

  group('SessionSettings', () {
    test('maps imu rate settings to nominal periods', () {
      expect(ImuRateSetting.hz200.periodUs, 5000);
      expect(ImuRateSetting.hz100.periodUs, 10000);
      expect(ImuRateSetting.fastest.periodUs, 0);
    });

    test('defaults follow the spec', () {
      const settings = SessionSettings();
      expect(settings.imuRate, ImuRateSetting.hz200);
      expect(settings.mergedRateHz, 100);
      expect(settings.videoWidth, 1920);
      expect(settings.videoHeight, 1080);
      expect(settings.videoFps, 30);
      expect(settings.audioEnabled, isFalse);
      expect(settings.maxImuGapMs, 250);
      expect(settings.maxGpsAgeS, 5);
    });

    test('json keeps snake_case keys and units', () {
      final json = const SessionSettings().toJson();
      expect(json['imu_rate'], '200 Hz');
      expect(json['max_imu_gap_ms'], 250);
      expect(json['max_gps_age_s'], 5);
    });
  });
}
