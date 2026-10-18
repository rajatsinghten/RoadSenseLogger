import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/domain/models/diagnostic_event.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/domain/models/sensor_info.dart';
import 'package:roadsense_logger/services/location/gps_recorder.dart';
import 'package:roadsense_logger/services/location/location_source.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/sensors/sensor_recorder.dart';
import 'package:roadsense_logger/services/sensors/sensor_source.dart';

class FakeSensorSource implements SensorSource {
  final StreamController<NativeSensorBatch> controller =
      StreamController<NativeSensorBatch>.broadcast(sync: true);

  bool started = false;
  bool stopped = false;
  int accPeriodUs = -1;
  int gyroPeriodUs = -1;

  @override
  Stream<NativeSensorBatch> get sensorBatches => controller.stream;

  @override
  Future<({bool accelerometerAvailable, bool gyroscopeAvailable})>
  startSensors({required int accPeriodUs, required int gyroPeriodUs}) async {
    started = true;
    this.accPeriodUs = accPeriodUs;
    this.gyroPeriodUs = gyroPeriodUs;
    return (accelerometerAvailable: true, gyroscopeAvailable: true);
  }

  @override
  Future<void> stopSensors() async {
    stopped = true;
  }

  @override
  Future<List<SensorInfo>> getSensorInfo() async => const [];
}

class FakeLocationSource implements LocationSource {
  final StreamController<NativeGpsEvent> controller =
      StreamController<NativeGpsEvent>.broadcast(sync: true);

  bool started = false;
  bool stopped = false;

  @override
  Stream<NativeGpsEvent> get gpsEvents => controller.stream;

  @override
  Future<void> startGps({required int intervalMs}) async {
    started = true;
  }

  @override
  Future<void> stopGps() async {
    stopped = true;
  }
}

void main() {
  group('SensorRecorder', () {
    test(
      'forwards events with original timestamps and measures rate',
      () async {
        final source = FakeSensorSource();
        final forwarded = <ImuEvent>[];
        final recorder = SensorRecorder(
          source: source,
          onEvents: forwarded.addAll,
          onDiagnostic: (_) {},
          nowNs: () => 0,
        );

        await recorder.start(accPeriodUs: 5000, gyroPeriodUs: 5000);
        expect(source.started, isTrue);
        expect(source.accPeriodUs, 5000);

        // 201 events at 5 ms spacing = 200 Hz.
        final events = [
          for (var i = 0; i <= 200; i++)
            ImuEvent(
              timestampNs: 1_000_000_000 + i * 5_000_000,
              sensor: ImuSensorKind.acc,
              x: 0,
              y: 0,
              z: 9.8,
            ),
        ];
        source.controller.add(
          NativeSensorBatch(sensor: ImuSensorKind.acc, events: events),
        );

        expect(forwarded.length, 201);
        expect(forwarded.first.timestampNs, 1_000_000_000);

        final report = recorder.report();
        expect(report.accCount, 201);
        expect(report.accAvgRateHz, closeTo(200, 0.01));
        expect(report.accLiveRateHz, closeTo(200, 0.01));
        expect(report.accLastMagnitude, closeTo(9.8, 1e-6));

        await recorder.stop();
        expect(source.stopped, isTrue);
      },
    );

    test('detects timestamp gaps and reports diagnostics', () async {
      final source = FakeSensorSource();
      final diagnostics = <DiagnosticEvent>[];
      final recorder = SensorRecorder(
        source: source,
        onEvents: (_) {},
        onDiagnostic: diagnostics.add,
        nowNs: () => 0,
      );
      await recorder.start(accPeriodUs: 5000, gyroPeriodUs: 5000);

      source.controller.add(
        NativeSensorBatch(
          sensor: ImuSensorKind.acc,
          events: const [
            ImuEvent(
              timestampNs: 1_000_000_000,
              sensor: ImuSensorKind.acc,
              x: 0,
              y: 0,
              z: 0,
            ),
            ImuEvent(
              timestampNs: 2_000_000_000,
              sensor: ImuSensorKind.acc,
              x: 0,
              y: 0,
              z: 0,
            ),
          ],
        ),
      );

      expect(diagnostics.length, 1);
      expect(diagnostics.single.type, 'sensor_gap');
      expect(diagnostics.single.context['sensor'], 'ACC');
      expect(recorder.report().gapCount, 1);
      await recorder.stop();
    });

    test('no gap diagnostic for normal spacing', () async {
      final source = FakeSensorSource();
      final diagnostics = <DiagnosticEvent>[];
      final recorder = SensorRecorder(
        source: source,
        onEvents: (_) {},
        onDiagnostic: diagnostics.add,
        nowNs: () => 0,
      );
      await recorder.start(accPeriodUs: 5000, gyroPeriodUs: 5000);

      source.controller.add(
        NativeSensorBatch(
          sensor: ImuSensorKind.gyro,
          events: const [
            ImuEvent(
              timestampNs: 1_000_000_000,
              sensor: ImuSensorKind.gyro,
              x: 0,
              y: 0,
              z: 0,
            ),
            ImuEvent(
              timestampNs: 1_005_000_000,
              sensor: ImuSensorKind.gyro,
              x: 0,
              y: 0,
              z: 0,
            ),
          ],
        ),
      );

      expect(diagnostics, isEmpty);
      expect(recorder.report().gyroCount, 2);
      await recorder.stop();
    });

    test('overflow markers raise diagnostics and count drops', () async {
      final source = FakeSensorSource();
      final diagnostics = <DiagnosticEvent>[];
      final recorder = SensorRecorder(
        source: source,
        onEvents: (_) {},
        onDiagnostic: diagnostics.add,
        nowNs: () => 100,
      );
      await recorder.start(accPeriodUs: 5000, gyroPeriodUs: 5000);

      source.controller.add(
        const NativeSensorBatch(
          sensor: ImuSensorKind.acc,
          events: [],
          droppedTotal: 42,
          isOverflowMarker: true,
        ),
      );

      expect(diagnostics.single.type, 'queue_overflow');
      expect(recorder.report().droppedCount, 42);
      await recorder.stop();
    });
  });

  group('GpsRecorder', () {
    GpsFix fix(int ts, {double? speed}) => GpsFix(
      timestampNs: ts,
      unixTimeMs: 1_700_000_000_000 + ts ~/ 1000000,
      latitude: 12.97,
      longitude: 77.59,
      speedMps: speed,
    );

    test('forwards accepted fixes and counts them', () async {
      final source = FakeLocationSource();
      final fixes = <GpsFix>[];
      final recorder = GpsRecorder(
        source: source,
        onFix: fixes.add,
        onDiagnostic: (_) {},
        nowNs: () => 1_000_000_000,
      );
      await recorder.start(intervalMs: 1000);

      source.controller.add(
        NativeGpsEvent.accepted(fix(500_000_000, speed: 8.5)),
      );
      expect(fixes.length, 1);

      final report = recorder.report();
      expect(report.acceptedCount, 1);
      expect(report.lastSpeedMps, 8.5);
      expect(report.lastFixAgeS, closeTo(0.5, 1e-9));
      await recorder.stop();
    });

    test('rejected fixes raise diagnostics and are never forwarded', () async {
      final source = FakeLocationSource();
      final fixes = <GpsFix>[];
      final diagnostics = <DiagnosticEvent>[];
      final recorder = GpsRecorder(
        source: source,
        onFix: fixes.add,
        onDiagnostic: diagnostics.add,
        nowNs: () => 0,
      );
      await recorder.start(intervalMs: 1000);

      source.controller.add(
        const NativeGpsEvent.rejected('latitude_out_of_range'),
      );

      expect(fixes, isEmpty);
      expect(diagnostics.single.type, 'gps_rejected');
      expect(recorder.report().rejectedCount, 1);
      await recorder.stop();
    });

    test('reports staleness exactly once until a new fix arrives', () async {
      var now = 0;
      final source = FakeLocationSource();
      final diagnostics = <DiagnosticEvent>[];
      final recorder = GpsRecorder(
        source: source,
        onFix: (_) {},
        onDiagnostic: diagnostics.add,
        nowNs: () => now,
        staleAfterS: 10,
      );
      await recorder.start(intervalMs: 1000);

      source.controller.add(NativeGpsEvent.accepted(fix(1_000_000_000)));
      now = 20_000_000_000;
      recorder.checkStaleness();
      recorder.checkStaleness();
      expect(diagnostics.where((d) => d.type == 'gps_stale').length, 1);

      now = 40_000_000_000;
      recorder.checkStaleness();
      expect(diagnostics.where((d) => d.type == 'gps_stale').length, 1);

      source.controller.add(NativeGpsEvent.accepted(fix(41_000_000_000)));
      now = 55_000_000_000;
      recorder.checkStaleness();
      expect(diagnostics.where((d) => d.type == 'gps_stale').length, 2);
      await recorder.stop();
    });

    test('detects GPS outages by inter-fix silence', () async {
      final source = FakeLocationSource();
      final diagnostics = <DiagnosticEvent>[];
      final recorder = GpsRecorder(
        source: source,
        onFix: (_) {},
        onDiagnostic: diagnostics.add,
        nowNs: () => 0,
        outageThresholdS: 30,
      );
      await recorder.start(intervalMs: 1000);

      source.controller.add(NativeGpsEvent.accepted(fix(1_000_000_000)));
      source.controller.add(NativeGpsEvent.accepted(fix(46_000_000_000)));

      expect(diagnostics.single.type, 'gps_outage');
      expect(recorder.report().outageCount, 1);
      await recorder.stop();
    });

    test('stale flag follows fix age against max age', () async {
      var now = 0;
      final source = FakeLocationSource();
      final recorder = GpsRecorder(
        source: source,
        onFix: (_) {},
        onDiagnostic: (_) {},
        nowNs: () => now,
      );
      await recorder.start(intervalMs: 1000);

      source.controller.add(NativeGpsEvent.accepted(fix(1_000_000_000)));
      expect(recorder.report().isStale(5), isFalse);

      now = 8_000_000_000;
      expect(recorder.report().isStale(5), isTrue);
      await recorder.stop();
    });
  });
}
