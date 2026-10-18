/// Seam over the native IMU collector so recorders are testable with fakes.
library;

import 'package:roadsense_logger/domain/models/sensor_info.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';

abstract interface class SensorSource {
  /// Batched IMU events with original `SensorEvent.timestamp` values.
  Stream<NativeSensorBatch> get sensorBatches;

  /// Requests collection at the given nominal periods (0 = fastest).
  Future<({bool accelerometerAvailable, bool gyroscopeAvailable})>
  startSensors({required int accPeriodUs, required int gyroPeriodUs});

  Future<void> stopSensors();

  Future<List<SensorInfo>> getSensorInfo();
}
