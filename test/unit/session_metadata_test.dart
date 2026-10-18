import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/domain/models/diagnostic_event.dart';
import 'package:roadsense_logger/domain/models/sensor_info.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';

void main() {
  const mapping = ClockMapping(
    sessionStartElapsedNs: 1_000,
    sessionStartUnixMs: 1_700_000_000_000,
  );

  SessionMetadata build({int? videoStartNs, double? durationS}) {
    return SessionMetadata(
      appVersion: '1.0.0+1',
      sessionId: 'abc123',
      status: SessionStatus.completed,
      clockMapping: mapping,
      config: const SessionConfig(
        vehicleType: VehicleType.car,
        mountPosition: MountPosition.dashboard,
        notes: 'test run',
      ),
      manufacturer: 'Google',
      model: 'Pixel 8',
      androidVersion: '15',
      videoStartNs: videoStartNs,
      videoEndNs: 2_000_000_000,
      videoStartReference: 'camera_plugin_start_completed',
      videoRequestedWidth: 1920,
      videoRequestedHeight: 1080,
      videoRequestedFps: 30,
      videoResolutionPreset: 'veryHigh',
      videoFileSizeBytes: 12345,
      videoAudioEnabled: false,
      sensorInfos: const [
        SensorInfo(
          kind: 'ACC',
          name: 'ICM-42688',
          vendor: 'TDK',
          range: 78.4,
          resolution: 0.0024,
        ),
        SensorInfo(kind: 'GYRO', name: '', vendor: '', available: false),
      ],
      requestedImuRate: '200 Hz',
      accStats: const SensorRateStats(eventCount: 2000, achievedRateHz: 198.7),
      gyroStats: const SensorRateStats(eventCount: 0, achievedRateHz: null),
      gpsRequestedIntervalMs: 1000,
      gpsFixCount: 12,
      gpsRejectedCount: 1,
      gpsOutageCount: 0,
      gpsDistanceM: 152.5,
      gpsAvgSpeedMps: 4.2,
      mergedRateHz: 100,
      mergedRowCount: 500,
      quality: const {'acc_missing_rows': 3},
      durationS: durationS,
    );
  }

  group('SessionMetadata.toJson', () {
    test('serializes with snake_case keys and explicit units', () {
      final json = build(videoStartNs: 1_500).toJson();
      expect(json['app_version'], '1.0.0+1');
      expect(json['session_id'], 'abc123');
      expect(json['status'], 'completed');

      final video = json['video']! as Map<String, Object?>;
      expect(video['start_ns'], 1_500);
      expect(video['start_reference'], 'camera_plugin_start_completed');
      expect(video['start_reference_is_frame_accurate'], isFalse);
      expect(video['requested_width'], 1920);
      expect(video['fps_control_supported'], isFalse);

      final imu = json['imu']! as Map<String, Object?>;
      expect(imu['requested_rate'], '200 Hz');
      final acc = imu['acc']! as Map<String, Object?>;
      expect(acc['event_count'], 2000);
      expect(acc['achieved_rate_hz'], 198.7);

      final gps = json['gps']! as Map<String, Object?>;
      expect(gps['fix_count'], 12);
      expect(gps['distance_m'], 152.5);
    });

    test('unknown values serialize as null, never zero', () {
      final json = build().toJson();
      final video = json['video']! as Map<String, Object?>;
      expect(video['start_ns'], isNull);

      final gyro =
          (json['imu']! as Map<String, Object?>)['gyro']!
              as Map<String, Object?>;
      expect(gyro['achieved_rate_hz'], isNull);
      expect(gyro['event_count'], 0); // real count is zero, not unknown

      final session = json['session']! as Map<String, Object?>;
      expect(session['duration_s'], isNull);
    });

    test('json is valid and encodable', () {
      final text = jsonEncode(build(videoStartNs: 1_500).toJson());
      expect(text, contains('camera_plugin_start_completed'));
    });
  });

  group('DiagnosticsRecorder', () {
    test('collects events and per-type counts', () {
      final recorder = DiagnosticsRecorder();
      recorder.record(
        const DiagnosticEvent(
          timestampNs: 10,
          type: 'sensor_gap',
          message: 'gap',
        ),
      );
      recorder.record(
        const DiagnosticEvent(
          timestampNs: 20,
          type: 'sensor_gap',
          message: 'gap again',
        ),
      );
      recorder.record(
        const DiagnosticEvent(
          timestampNs: 30,
          type: 'gps_stale',
          message: 'stale',
          context: {'age_s': 12.0},
        ),
      );

      final json = recorder.toJson();
      final counts = json['counts']! as Map<String, Object?>;
      expect(counts['sensor_gap'], 2);
      expect(counts['gps_stale'], 1);
      final events = json['events']! as List<Object?>;
      expect(events.length, 3);
      expect((events.last! as Map<String, Object?>)['context'], {
        'age_s': 12.0,
      });
    });
  });
}
