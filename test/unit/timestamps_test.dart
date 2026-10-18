import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';

void main() {
  group('Timestamps.tVideoS', () {
    test('converts nanoseconds to video-relative seconds', () {
      expect(Timestamps.tVideoS(2_000_000_000, 1_000_000_000), 1.0);
    });

    test('is negative before video start', () {
      expect(Timestamps.tVideoS(500_000_000, 1_000_000_000), -0.5);
    });

    test('uses double precision for sub-nanosecond fractions', () {
      final t = Timestamps.tVideoS(1_000_000_001, 1_000_000_000);
      expect(t, closeTo(1e-9, 1e-18));
    });

    test('handles large epoch-scale timestamps without precision collapse', () {
      final base = 7_200_000_000_000; // 7200 s in ns
      final t = Timestamps.tVideoS(base + 250_000_000, base);
      expect(t, closeTo(0.25, 1e-12));
    });
  });

  group('ClockMapping', () {
    const mapping = ClockMapping(
      sessionStartElapsedNs: 1_000_000_000,
      sessionStartUnixMs: 1_700_000_000_000,
    );

    test('derives unix ms from elapsed ns', () {
      expect(mapping.unixMsFromElapsedNs(1_500_000_000),
          1_700_000_000_000 + 500);
    });

    test('derives unix ms for earlier events', () {
      expect(mapping.unixMsFromElapsedNs(900_000_000),
          1_700_000_000_000 - 100);
    });

    test('rounds to nearest millisecond', () {
      expect(mapping.unixMsFromElapsedNs(1_000_400_000), 1_700_000_000_000);
      expect(mapping.unixMsFromElapsedNs(1_000_600_000), 1_700_000_000_001);
    });

    test('round-trips through json', () {
      final restored = ClockMapping.fromJson(mapping.toJson());
      expect(restored.sessionStartElapsedNs, mapping.sessionStartElapsedNs);
      expect(restored.sessionStartUnixMs, mapping.sessionStartUnixMs);
    });
  });
}
