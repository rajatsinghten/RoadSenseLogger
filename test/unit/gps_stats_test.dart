import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/services/location/gps_stats.dart';

void main() {
  GpsFix fix(int ts, double lat, double lon) => GpsFix(
    timestampNs: ts,
    unixTimeMs: ts ~/ 1000000,
    latitude: lat,
    longitude: lon,
  );

  group('haversineMeters', () {
    test('0.001 degree of latitude is about 111 m', () {
      expect(haversineMeters(0, 0, 0.001, 0), closeTo(111.19, 0.1));
    });

    test('same point is zero', () {
      expect(haversineMeters(12.97, 77.59, 12.97, 77.59), 0);
    });
  });

  group('GpsStats.compute', () {
    test('null for fewer than two fixes', () {
      expect(GpsStats.compute(const []).distanceM, isNull);
      expect(GpsStats.compute([fix(0, 0, 0)]).avgSpeedMps, isNull);
    });

    test('distance accumulates over consecutive fixes', () {
      final stats = GpsStats.compute([
        fix(0, 0, 0),
        fix(1_000_000_000, 0.001, 0),
        fix(2_000_000_000, 0.002, 0),
      ]);
      expect(stats.distanceM, closeTo(222.4, 0.5));
      expect(stats.avgSpeedMps, closeTo(111.2, 0.5));
    });

    test('sorts fixes by timestamp before accumulating', () {
      final stats = GpsStats.compute([
        fix(2_000_000_000, 0.002, 0),
        fix(0, 0, 0),
        fix(1_000_000_000, 0.001, 0),
      ]);
      expect(stats.distanceM, closeTo(222.4, 0.5));
    });
  });
}
