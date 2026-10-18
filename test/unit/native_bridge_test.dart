import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';

void main() {
  group('NativeBridge.decodeGpsEvent', () {
    test('decodes an accepted fix with all fields', () {
      final event = NativeBridge.decodeGpsEvent({
        'timestamp_ns': 5_000_000_000,
        'unix_time_ms': 1_700_000_000_000,
        'latitude': 12.9716,
        'longitude': 77.5946,
        'altitude_m': 920.5,
        'speed_mps': 8.25,
        'bearing_deg': 180.0,
        'accuracy_m': 4.5,
        'accepted': true,
      });

      expect(event.accepted, isTrue);
      final fix = event.fix!;
      expect(fix.timestampNs, 5_000_000_000);
      expect(fix.unixTimeMs, 1_700_000_000_000);
      expect(fix.latitude, closeTo(12.9716, 1e-9));
      expect(fix.longitude, closeTo(77.5946, 1e-9));
      expect(fix.altitudeM, 920.5);
      expect(fix.speedMps, 8.25);
      expect(fix.bearingDeg, 180.0);
      expect(fix.accuracyM, 4.5);
    });

    test('keeps unavailable optional fields null, never zero', () {
      final event = NativeBridge.decodeGpsEvent({
        'timestamp_ns': 5_000_000_000,
        'unix_time_ms': 1_700_000_000_000,
        'latitude': 12.9716,
        'longitude': 77.5946,
        'altitude_m': null,
        'speed_mps': null,
        'bearing_deg': null,
        'accuracy_m': null,
        'accepted': true,
      });

      final fix = event.fix!;
      expect(fix.altitudeM, isNull);
      expect(fix.speedMps, isNull);
      expect(fix.bearingDeg, isNull);
      expect(fix.accuracyM, isNull);
    });

    test('decodes rejected fixes with a reason and no data', () {
      final event = NativeBridge.decodeGpsEvent({
        'timestamp_ns': 5_000_000_000,
        'unix_time_ms': 1_700_000_000_000,
        'latitude': 95.0,
        'longitude': 0.0,
        'accepted': false,
        'reason': 'latitude_out_of_range',
      });

      expect(event.accepted, isFalse);
      expect(event.fix, isNull);
      expect(event.reason, 'latitude_out_of_range');
    });
  });

  group('NativeBridge.decodeSensorBatch', () {
    test('decodes events with original timestamps preserved', () {
      final batch = NativeBridge.decodeSensorBatch({
        'sensor': 'GYRO',
        'events': [
          [9_000_000_001, 0.1, -0.2, 0.3],
        ],
      });

      expect(batch.sensor, ImuSensorKind.gyro);
      expect(batch.isOverflowMarker, isFalse);
      expect(batch.events.single.timestampNs, 9_000_000_001);
      expect(batch.events.single.x, closeTo(0.1, 1e-9));
    });

    test('overflow markers carry drop totals and no events', () {
      final batch = NativeBridge.decodeSensorBatch({
        'sensor': 'OVERFLOW',
        'events': <List<Object?>>[],
        'dropped_total': 7,
      });

      expect(batch.isOverflowMarker, isTrue);
      expect(batch.droppedTotal, 7);
      expect(batch.events, isEmpty);
    });
  });
}
