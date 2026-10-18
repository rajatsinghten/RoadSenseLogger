/// Sensor intake service (FR-020..027): forwards raw events for persistence,
/// measures achieved rates, and reports gaps/overflows as diagnostics.
///
/// Never performs disk I/O — persistence is delegated to [onEvents].
library;

import 'dart:async';

import 'package:roadsense_logger/domain/models/diagnostic_event.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/sensors/rate_meter.dart';
import 'package:roadsense_logger/services/sensors/sensor_source.dart';

/// Immutable measurement report used for metadata and live UI.
class SensorReport {
  const SensorReport({
    required this.accCount,
    required this.gyroCount,
    required this.accAvgRateHz,
    required this.gyroAvgRateHz,
    required this.accLiveRateHz,
    required this.gyroLiveRateHz,
    required this.accLastMagnitude,
    required this.gyroLastMagnitude,
    required this.gyroscopeAvailable,
    required this.gapCount,
    required this.droppedCount,
  });

  final int accCount;
  final int gyroCount;
  final double? accAvgRateHz;
  final double? gyroAvgRateHz;
  final double? accLiveRateHz;
  final double? gyroLiveRateHz;
  final double? accLastMagnitude;
  final double? gyroLastMagnitude;
  final bool gyroscopeAvailable;
  final int gapCount;

  /// Events dropped by the native bounded queue.
  final int droppedCount;
}

class SensorRecorder {
  SensorRecorder({
    required SensorSource source,
    required void Function(List<ImuEvent> events) onEvents,
    required void Function(DiagnosticEvent event) onDiagnostic,
    required int Function() nowNs,
    this.gapThresholdNs = 500 * 1000 * 1000,
  }) : _source = source,
       _onEvents = onEvents,
       _onDiagnostic = onDiagnostic,
       _nowNs = nowNs;

  final SensorSource _source;
  final void Function(List<ImuEvent> events) _onEvents;
  final void Function(DiagnosticEvent event) _onDiagnostic;
  final int Function() _nowNs;

  /// A per-sensor timestamp delta above this is reported as `sensor_gap`.
  final int gapThresholdNs;

  final RateMeter _accMeter = RateMeter();
  final RateMeter _gyroMeter = RateMeter();

  StreamSubscription<NativeSensorBatch>? _subscription;
  int? _lastAccTs;
  int? _lastGyroTs;
  int _gapCount = 0;
  int _droppedCount = 0;
  double? _accMagnitude;
  double? _gyroMagnitude;
  bool _gyroscopeAvailable = true;

  bool get gyroscopeAvailable => _gyroscopeAvailable;

  /// Starts collection at the given nominal periods and subscribes to events.
  Future<void> start({
    required int accPeriodUs,
    required int gyroPeriodUs,
  }) async {
    final availability = await _source.startSensors(
      accPeriodUs: accPeriodUs,
      gyroPeriodUs: gyroPeriodUs,
    );
    _gyroscopeAvailable = availability.gyroscopeAvailable;
    _subscription = _source.sensorBatches.listen(
      _onBatch,
      onError: (Object error) {
        _onDiagnostic(
          DiagnosticEvent(
            timestampNs: _nowNs(),
            type: 'sensor_stream_error',
            message: 'IMU event stream error: $error',
          ),
        );
      },
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _source.stopSensors();
  }

  void _onBatch(NativeSensorBatch batch) {
    if (batch.isOverflowMarker) {
      _droppedCount = batch.droppedTotal;
      _onDiagnostic(
        DiagnosticEvent(
          timestampNs: _nowNs(),
          type: 'queue_overflow',
          message:
              'Native IMU queue overflow; ${batch.droppedTotal} events dropped',
          context: {'dropped_total': batch.droppedTotal},
        ),
      );
      return;
    }

    for (final event in batch.events) {
      _track(event);
    }
    _onEvents(batch.events);
  }

  void _track(ImuEvent event) {
    switch (event.sensor) {
      case ImuSensorKind.acc:
        _accMeter.add(event.timestampNs);
        _accMagnitude = event.magnitude;
        _checkGap('ACC', _lastAccTs, event.timestampNs);
        _lastAccTs = event.timestampNs;
      case ImuSensorKind.gyro:
        _gyroMeter.add(event.timestampNs);
        _gyroMagnitude = event.magnitude;
        _checkGap('GYRO', _lastGyroTs, event.timestampNs);
        _lastGyroTs = event.timestampNs;
    }
  }

  void _checkGap(String sensor, int? lastTs, int ts) {
    if (lastTs == null) return;
    final gapNs = ts - lastTs;
    if (gapNs > gapThresholdNs) {
      _gapCount++;
      _onDiagnostic(
        DiagnosticEvent(
          timestampNs: ts,
          type: 'sensor_gap',
          message: '$sensor timestamp gap of ${gapNs / 1e6} ms',
          context: {
            'sensor': sensor,
            'gap_ns': gapNs,
            'from_ns': lastTs,
            'to_ns': ts,
          },
        ),
      );
    }
  }

  SensorReport report() {
    return SensorReport(
      accCount: _accMeter.count,
      gyroCount: _gyroMeter.count,
      accAvgRateHz: _accMeter.averageRateHz,
      gyroAvgRateHz: _gyroMeter.averageRateHz,
      accLiveRateHz: _accMeter.liveRateHz,
      gyroLiveRateHz: _gyroMeter.liveRateHz,
      accLastMagnitude: _accMagnitude,
      gyroLastMagnitude: _gyroMagnitude,
      gyroscopeAvailable: _gyroscopeAvailable,
      gapCount: _gapCount,
      droppedCount: _droppedCount,
    );
  }
}
