/// Complete session metadata model (`metadata.json`, DATA-004).
///
/// Unknown values are serialized as JSON null — never zero (FR-074).
library;

import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/domain/models/diagnostic_event.dart';
import 'package:roadsense_logger/domain/models/sensor_info.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

enum SessionStatus {
  completed('completed'),
  incomplete('incomplete'),
  recovered('recovered');

  const SessionStatus(this.id);

  final String id;
}

class SensorRateStats {
  const SensorRateStats({
    required this.eventCount,
    required this.achievedRateHz,
  });

  final int eventCount;

  /// Measured average rate over the recording; null before two events.
  final double? achievedRateHz;
}

class SessionMetadata {
  const SessionMetadata({
    required this.appVersion,
    required this.sessionId,
    required this.status,
    required this.clockMapping,
    required this.config,
    required this.sensorInfos,
    required this.accStats,
    required this.gyroStats,
    required this.requestedImuRate,
    required this.gpsRequestedIntervalMs,
    required this.gpsFixCount,
    required this.gpsRejectedCount,
    required this.gpsOutageCount,
    required this.mergedRateHz,
    required this.mergedRowCount,
    required this.quality,
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    this.sessionEndElapsedNs,
    this.sessionEndUnixMs,
    this.durationS,
    this.videoStartNs,
    this.videoEndNs,
    this.videoStartReference,
    this.videoRequestedWidth,
    this.videoRequestedHeight,
    this.videoRequestedFps,
    this.videoResolutionPreset,
    this.videoFileSizeBytes,
    this.videoAudioEnabled = false,
    this.gpsDistanceM,
    this.gpsAvgSpeedMps,
    this.interrupted = false,
    this.interruptionReason,
    this.recovered = false,
    this.retainedRows,
    this.lossWindowS,
  });

  final String appVersion;
  final String sessionId;
  final SessionStatus status;
  final ClockMapping clockMapping;
  final SessionConfig config;

  final String manufacturer;
  final String model;
  final String androidVersion;

  final int? sessionEndElapsedNs;
  final int? sessionEndUnixMs;
  final double? durationS;

  final int? videoStartNs;
  final int? videoEndNs;
  final String? videoStartReference;
  final int? videoRequestedWidth;
  final int? videoRequestedHeight;
  final int? videoRequestedFps;
  final String? videoResolutionPreset;
  final int? videoFileSizeBytes;
  final bool videoAudioEnabled;

  final List<SensorInfo> sensorInfos;

  /// Requested IMU sampling rate label (a request, not a guarantee).
  final String requestedImuRate;
  final SensorRateStats accStats;
  final SensorRateStats gyroStats;

  final int gpsRequestedIntervalMs;
  final int gpsFixCount;
  final int gpsRejectedCount;
  final int gpsOutageCount;
  final double? gpsDistanceM;
  final double? gpsAvgSpeedMps;

  final double mergedRateHz;
  final int mergedRowCount;

  /// Missing-data and quality statistics (DATA-004/005).
  final Map<String, Object?> quality;

  final bool interrupted;
  final String? interruptionReason;
  final bool recovered;
  final int? retainedRows;
  final double? lossWindowS;

  Map<String, Object?> toJson() => {
    'app_version': appVersion,
    'session_id': sessionId,
    'status': status.id,
    'device': {
      'manufacturer': manufacturer,
      'model': model,
      'android_version': androidVersion,
    },
    'session': {
      'start_elapsed_ns': clockMapping.sessionStartElapsedNs,
      'start_unix_ms': clockMapping.sessionStartUnixMs,
      'end_elapsed_ns': sessionEndElapsedNs,
      'end_unix_ms': sessionEndUnixMs,
      'duration_s': durationS,
    },
    'clock_mapping': clockMapping.toJson(),
    'video': {
      'start_ns': videoStartNs,
      'end_ns': videoEndNs,
      'start_reference': videoStartReference,
      // The recording-start event is not the first frame's exposure time
      // (documented limitation, FR-014).
      'start_reference_is_frame_accurate': false,
      'requested_width': videoRequestedWidth,
      'requested_height': videoRequestedHeight,
      'requested_fps': videoRequestedFps,
      'resolution_preset': videoResolutionPreset,
      'fps_control_supported': false,
      'file_size_bytes': videoFileSizeBytes,
      'audio_enabled': videoAudioEnabled,
    },
    'sensors': [for (final info in sensorInfos) info.toJson()],
    'imu': {
      'requested_rate': requestedImuRate,
      'acc': {
        'event_count': accStats.eventCount,
        'achieved_rate_hz': accStats.achievedRateHz,
      },
      'gyro': {
        'event_count': gyroStats.eventCount,
        'achieved_rate_hz': gyroStats.achievedRateHz,
      },
    },
    'gps': {
      'requested_interval_ms': gpsRequestedIntervalMs,
      'fix_count': gpsFixCount,
      'rejected_count': gpsRejectedCount,
      'outage_count': gpsOutageCount,
      'distance_m': gpsDistanceM,
      'avg_speed_mps': gpsAvgSpeedMps,
    },
    'merged': {'rate_hz': mergedRateHz, 'row_count': mergedRowCount},
    'quality': quality,
    'config': config.toJson(),
    'interruption': {'interrupted': interrupted, 'reason': interruptionReason},
    'recovery': {
      'recovered': recovered,
      'retained_rows': retainedRows,
      'loss_window_s': lossWindowS,
    },
  };
}

/// Writes `diagnostics.json` (DATA-005): timestamped data-quality events with
/// per-type counts.
class DiagnosticsRecorder {
  final List<DiagnosticEvent> events = [];

  void record(DiagnosticEvent event) => events.add(event);

  Map<String, Object?> toJson() {
    final counts = <String, int>{};
    for (final event in events) {
      counts[event.type] = (counts[event.type] ?? 0) + 1;
    }
    return {
      'counts': counts,
      'events': [for (final event in events) event.toJson()],
    };
  }
}
