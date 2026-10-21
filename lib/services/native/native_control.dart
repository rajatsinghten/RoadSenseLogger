/// Seam over native control-plane calls (clock, foreground service, device
/// info, storage, permissions) so orchestration is testable with fakes.
library;

import 'package:roadsense_logger/core/time/timestamps.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
  });

  final String manufacturer;
  final String model;
  final String androidVersion;
}

abstract interface class NativeControl {
  /// Current monotonic elapsed-realtime nanoseconds.
  Future<int> getElapsedNs();

  /// Samples the elapsed ↔ wall-clock mapping (FR-041).
  Future<ClockMapping> getClockMapping();

  Future<void> startForeground({required bool audio});

  Future<void> stopForeground();

  Future<DeviceInfo> getDeviceInfo();

  /// Free bytes available to the app on the data volume (FR-054).
  Future<int> getFreeStorageBytes();

  /// Copies the file at [path] into the public `Download/RoadSense/` folder
  /// as [displayName] (FR-070). Returns the user-visible saved location,
  /// which may carry a " (n)" suffix when the name already exists.
  Future<String> saveToDownloads(String path, {required String displayName});

  Future<Map<String, bool>> checkPermissions(List<String> permissions);

  Future<Map<String, bool>> requestPermissions(List<String> permissions);
}
