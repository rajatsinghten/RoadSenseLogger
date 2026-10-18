/// Dart side of the native integration boundary (`specs/architecture.md` §2).
///
/// IMU events arrive batched with their original `SensorEvent.timestamp`
/// values; this bridge only decodes — it never restamps events.
library;

import 'package:flutter/services.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/domain/models/sensor_info.dart';
import 'package:roadsense_logger/services/location/location_source.dart';
import 'package:roadsense_logger/services/sensors/sensor_source.dart';

/// One decoded native IMU batch.
class NativeSensorBatch {
  const NativeSensorBatch({
    required this.sensor,
    required this.events,
    this.droppedTotal = 0,
    this.isOverflowMarker = false,
  });

  final ImuSensorKind sensor;

  /// Events in arrival order with original timestamps.
  final List<ImuEvent> events;

  /// Total events dropped by the native bounded queue (overflow markers only).
  final int droppedTotal;

  /// True for queue-overflow diagnostic markers (no events).
  final bool isOverflowMarker;
}

/// One decoded native GPS event: an accepted fix or a rejection record.
class NativeGpsEvent {
  const NativeGpsEvent.accepted(this.fix) : accepted = true, reason = null;

  const NativeGpsEvent.rejected(this.reason) : fix = null, accepted = false;

  final GpsFix? fix;
  final bool accepted;
  final String? reason;
}

class NativeBridge implements SensorSource, LocationSource {
  NativeBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    EventChannel? gpsEventChannel,
  }) : _method = methodChannel ?? const MethodChannel(_methodName),
       _events = eventChannel ?? const EventChannel(_eventsName),
       _gpsEvents = gpsEventChannel ?? const EventChannel(_gpsEventsName);

  static const _methodName = 'roadsense/native';
  static const _eventsName = 'roadsense/sensors';
  static const _gpsEventsName = 'roadsense/gps';

  final MethodChannel _method;
  final EventChannel _events;
  final EventChannel _gpsEvents;

  /// Decoded IMU batches (ACC and GYRO interleaved in arrival order).
  @override
  Stream<NativeSensorBatch> get sensorBatches =>
      _events.receiveBroadcastStream().map(decodeSensorBatch);

  static NativeSensorBatch decodeSensorBatch(Object? raw) {
    final map = (raw as Map).cast<String, Object?>();
    final kind = map['sensor'] as String;
    if (kind == 'OVERFLOW') {
      return NativeSensorBatch(
        sensor: ImuSensorKind.acc,
        events: const [],
        droppedTotal: ((map['dropped_total'] as num?) ?? 0).toInt(),
        isOverflowMarker: true,
      );
    }
    final sensor = ImuSensorKind.fromCsvId(kind);
    final rows = (map['events'] as List).cast<List<Object?>>();
    final events = rows
        .map((row) {
          return ImuEvent(
            timestampNs: (row[0] as num).toInt(),
            sensor: sensor,
            x: (row[1] as num).toDouble(),
            y: (row[2] as num).toDouble(),
            z: (row[3] as num).toDouble(),
          );
        })
        .toList(growable: false);
    return NativeSensorBatch(sensor: sensor, events: events);
  }

  /// Decoded GPS events (accepted fixes and rejection records).
  @override
  Stream<NativeGpsEvent> get gpsEvents =>
      _gpsEvents.receiveBroadcastStream().map(decodeGpsEvent);

  static NativeGpsEvent decodeGpsEvent(Object? raw) {
    final map = (raw as Map).cast<String, Object?>();
    if (map['accepted'] != true) {
      return NativeGpsEvent.rejected(
        (map['reason'] as String?) ?? 'unspecified',
      );
    }
    final fix = GpsFix(
      timestampNs: (map['timestamp_ns'] as num).toInt(),
      unixTimeMs: (map['unix_time_ms'] as num).toInt(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitudeM: (map['altitude_m'] as num?)?.toDouble(),
      speedMps: (map['speed_mps'] as num?)?.toDouble(),
      bearingDeg: (map['bearing_deg'] as num?)?.toDouble(),
      accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
    );
    return NativeGpsEvent.accepted(fix);
  }

  /// Requests IMU collection. [accPeriodUs]/[gyroPeriodUs] are nominal
  /// sampling periods (0 = fastest); achieved rates are measured separately.
  @override
  Future<({bool accelerometerAvailable, bool gyroscopeAvailable})>
  startSensors({required int accPeriodUs, required int gyroPeriodUs}) async {
    final result = (await _method.invokeMapMethod<String, Object?>(
      'startSensors',
      {'accPeriodUs': accPeriodUs, 'gyroPeriodUs': gyroPeriodUs},
    ))!;
    return (
      accelerometerAvailable: result['accelerometer_available'] as bool,
      gyroscopeAvailable: result['gyroscope_available'] as bool,
    );
  }

  @override
  Future<void> stopSensors() => _method.invokeMethod<void>('stopSensors');

  /// Starts high-accuracy GPS collection at [intervalMs] nominal interval.
  @override
  Future<void> startGps({required int intervalMs}) =>
      _method.invokeMethod<void>('startGps', {'intervalMs': intervalMs});

  @override
  Future<void> stopGps() => _method.invokeMethod<void>('stopGps');

  @override
  Future<List<SensorInfo>> getSensorInfo() async {
    final raw = (await _method.invokeListMethod<Object?>('getSensorInfo'))!;
    return raw
        .map((item) {
          final map = (item as Map).cast<String, Object?>();
          return SensorInfo(
            kind: map['kind'] as String,
            name: map['name'] as String? ?? '',
            vendor: map['vendor'] as String? ?? '',
            range: (map['range'] as num?)?.toDouble(),
            resolution: (map['resolution'] as num?)?.toDouble(),
            available: map['available'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  /// Samples the elapsed ↔ wall-clock mapping (FR-041).
  Future<ClockMapping> getClockMapping() async {
    final map = (await _method.invokeMapMethod<String, Object?>(
      'getClockMapping',
    ))!;
    return ClockMapping(
      sessionStartElapsedNs: (map['elapsed_ns'] as num).toInt(),
      sessionStartUnixMs: (map['unix_ms'] as num).toInt(),
    );
  }

  /// Current monotonic elapsed-realtime nanoseconds.
  Future<int> getElapsedNs() async =>
      (await _method.invokeMethod<int>('getElapsedNs'))!;

  Future<void> startForeground({required bool audio}) =>
      _method.invokeMethod<void>('startForeground', {'audio': audio});

  Future<void> stopForeground() => _method.invokeMethod<void>('stopForeground');

  Future<Map<String, bool>> checkPermissions(List<String> permissions) async {
    final map = (await _method.invokeMapMethod<String, Object?>(
      'checkPermissions',
      {'permissions': permissions},
    ))!;
    return map.map((key, value) => MapEntry(key, value as bool));
  }

  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    final map = (await _method.invokeMapMethod<String, Object?>(
      'requestPermissions',
      {'permissions': permissions},
    ))!;
    return map.map((key, value) => MapEntry(key, value as bool));
  }
}
