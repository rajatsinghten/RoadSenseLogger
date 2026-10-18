/// Canonical session file names and directory layout (FR-050, FR-051).
library;

import 'dart:io';

class SessionPaths {
  SessionPaths(this.sessionDir);

  final Directory sessionDir;

  String get videoFile => '${sessionDir.path}/video.mp4';
  String get imuFile => '${sessionDir.path}/imu_raw.csv';
  String get gpsFile => '${sessionDir.path}/gps.csv';
  String get mergedFile => '${sessionDir.path}/merged.csv';
  String get metadataFile => '${sessionDir.path}/metadata.json';
  String get diagnosticsFile => '${sessionDir.path}/diagnostics.json';

  /// Temporary names used while a session is being written.
  String get imuPartFile => '$imuFile.part';
  String get gpsPartFile => '$gpsFile.part';
}
