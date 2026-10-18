/// Hardware metadata for a sensor (FR-026, DATA-004).
library;

class SensorInfo {
  const SensorInfo({
    required this.kind,
    required this.name,
    required this.vendor,
    this.range,
    this.resolution,
    this.available = true,
  });

  /// `ACC` or `GYRO` (matches `ImuSensorKind.csvId`).
  final String kind;
  final String name;
  final String vendor;
  final double? range;
  final double? resolution;

  /// False when the device has no such sensor (e.g. missing gyroscope).
  final bool available;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    'vendor': vendor,
    'range': range,
    'resolution': resolution,
    'available': available,
  };
}
