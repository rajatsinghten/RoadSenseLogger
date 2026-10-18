/// Raw IMU event model (DATA-001). Values are raw sensor readings; the
/// accelerometer includes gravity and is never transformed.
library;

import 'dart:math' as math;

enum ImuSensorKind {
  acc('ACC'),
  gyro('GYRO');

  const ImuSensorKind(this.csvId);

  /// Identifier used in the `sensor` column of `imu_raw.csv`.
  final String csvId;

  static ImuSensorKind fromCsvId(String id) => ImuSensorKind.values.firstWhere(
    (kind) => kind.csvId == id,
    orElse: () => throw ArgumentError.value(id, 'id'),
  );
}

class ImuEvent {
  const ImuEvent({
    required this.timestampNs,
    required this.sensor,
    required this.x,
    required this.y,
    required this.z,
  });

  /// Original `SensorEvent.timestamp` (elapsed-realtime nanoseconds).
  final int timestampNs;

  final ImuSensorKind sensor;

  /// m/s² for [ImuSensorKind.acc]; rad/s for [ImuSensorKind.gyro].
  final double x;
  final double y;
  final double z;

  /// Euclidean magnitude of the reading, in the sensor's unit.
  double get magnitude => math.sqrt(x * x + y * y + z * z);
}
