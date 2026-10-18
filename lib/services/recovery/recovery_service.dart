/// Crash recovery for interrupted sessions (FR-055).
///
/// A session without a valid `metadata.json` is *incomplete*. Recovery:
/// 1. renames `.part` CSVs to their final names,
/// 2. keeps the header plus every well-formed, monotonically timestamped row
///    and truncates any corrupt tail,
/// 3. writes `metadata.json` with `"status": "recovered"` (never `completed`)
///    including retained row counts, remaining problems and the estimated
///    loss window (the writer's unflushed buffer, ≤ ~1 s of events).
///
/// `merged.csv` cannot be regenerated without the in-memory video interval, so
/// a recovered session may lack it; that is recorded as a problem, not hidden.
library;

import 'dart:convert';
import 'dart:io';

import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';

class RecoveryReport {
  const RecoveryReport({
    required this.recoveredSessions,
    required this.skippedSessions,
  });

  final List<String> recoveredSessions;
  final List<String> skippedSessions;
}

class RecoveryService {
  RecoveryService({required this.repository, this.lossWindowS = 1.0});

  final SessionRepository repository;

  /// Upper bound of the unflushed write buffer at crash time (FR-055).
  final double lossWindowS;

  /// Recovers every incomplete session; complete sessions are untouched.
  Future<RecoveryReport> recoverAll() async {
    final recovered = <String>[];
    final skipped = <String>[];
    for (final record in repository.listSessions()) {
      if (record.status != SessionStatus.incomplete) {
        skipped.add(record.id);
        continue;
      }
      await recover(record);
      recovered.add(record.id);
    }
    return RecoveryReport(
      recoveredSessions: recovered,
      skippedSessions: skipped,
    );
  }

  /// Recovers one incomplete session.
  Future<void> recover(SessionRecord record) async {
    final paths = record.paths;
    final problems = <String>[];

    final imuRows = await _recoverCsv(
      partFile: paths.imuPartFile,
      finalFile: paths.imuFile,
      expectedColumns: 7,
      problems: problems,
    );
    final gpsRows = await _recoverCsv(
      partFile: paths.gpsPartFile,
      finalFile: paths.gpsFile,
      expectedColumns: 9,
      problems: problems,
    );

    final merged = File(paths.mergedFile);
    final mergedRows = merged.existsSync()
        ? _countDataRows(merged.readAsLinesSync())
        : 0;
    if (!merged.existsSync()) {
      problems.add(
        'merged.csv missing; cannot regenerate without video interval',
      );
    }
    if (!File(paths.videoFile).existsSync()) {
      problems.add('video.mp4 missing');
    }

    final metadata = <String, Object?>{
      'app_version': null,
      'session_id': record.id,
      'status': SessionStatus.recovered.id,
      'device': {'manufacturer': null, 'model': null, 'android_version': null},
      'session': {
        'start_elapsed_ns': null,
        'start_unix_ms': null,
        'end_elapsed_ns': null,
        'end_unix_ms': null,
        'duration_s': null,
      },
      'clock_mapping': null,
      'video': {
        'start_ns': null,
        'end_ns': null,
        'start_reference': null,
        'start_reference_is_frame_accurate': false,
        'requested_width': null,
        'requested_height': null,
        'requested_fps': null,
        'resolution_preset': null,
        'fps_control_supported': false,
        'file_size_bytes': _fileSize(paths.videoFile),
        'audio_enabled': null,
      },
      'sensors': <Object?>[],
      'imu': {
        'requested_rate': null,
        'acc': {'event_count': null, 'achieved_rate_hz': null},
        'gyro': {'event_count': null, 'achieved_rate_hz': null},
      },
      'gps': {
        'requested_interval_ms': null,
        'fix_count': gpsRows,
        'rejected_count': null,
        'outage_count': null,
        'distance_m': null,
        'avg_speed_mps': null,
      },
      'merged': {'rate_hz': null, 'row_count': mergedRows},
      'quality': {
        'imu_data_rows_retained': imuRows,
        'gps_data_rows_retained': gpsRows,
      },
      'config': {
        'vehicle_type': null,
        'mount_position': null,
        'notes': null,
        'settings': null,
      },
      'interruption': {
        'interrupted': true,
        'reason': 'app terminated before finalization',
      },
      'recovery': {
        'recovered': true,
        'retained_rows': {'imu': imuRows, 'gps': gpsRows, 'merged': mergedRows},
        'loss_window_s': lossWindowS,
        'problems': problems,
      },
    };

    final diagnosticsFile = File(paths.diagnosticsFile);
    final events = <Object?>[
      {
        'timestamp_ns': null,
        'type': 'recovery',
        'message': 'Session recovered from interrupted recording',
        'context': {
          'imu_rows_retained': imuRows,
          'gps_rows_retained': gpsRows,
          'problems': problems,
        },
      },
    ];
    if (diagnosticsFile.existsSync()) {
      try {
        final decoded = jsonDecode(diagnosticsFile.readAsStringSync());
        final existing = (decoded as Map<String, Object?>)['events'];
        if (existing is List) {
          events.insertAll(0, existing);
        }
      } catch (error) {
        problems.add('diagnostics.json unreadable and rebuilt: $error');
      }
    }
    await diagnosticsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'counts': {'recovery': 1},
        'events': events,
      }),
      flush: true,
    );

    // Written last: marks the session as recovered (not merely incomplete).
    await File(paths.metadataFile).writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
      flush: true,
    );
  }

  /// Renames the `.part` file (if any) and returns retained data rows.
  Future<int> _recoverCsv({
    required String partFile,
    required String finalFile,
    required int expectedColumns,
    required List<String> problems,
  }) async {
    final part = File(partFile);
    final finalF = File(finalFile);
    if (part.existsSync() && !finalF.existsSync()) {
      await part.rename(finalFile);
    }
    if (!finalF.existsSync()) {
      problems.add('${finalF.path.split('/').last} missing');
      return 0;
    }

    final lines = finalF.readAsLinesSync();
    if (lines.isEmpty) {
      problems.add('${finalF.path.split('/').last} empty');
      return 0;
    }
    final kept = <String>[lines.first];
    int? lastTimestamp;
    var truncated = 0;
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final fields = line.split(',');
      final timestamp = int.tryParse(fields.isNotEmpty ? fields.first : '');
      final valid =
          fields.length == expectedColumns &&
          timestamp != null &&
          (lastTimestamp == null || timestamp >= lastTimestamp);
      if (!valid) {
        truncated++;
        break; // corrupt tail: stop at the first bad row
      }
      kept.add(line);
      lastTimestamp = timestamp;
    }
    if (truncated > 0) {
      problems.add(
        '${finalF.path.split('/').last}: truncated $truncated corrupt row(s)',
      );
      await finalF.writeAsString('${kept.join('\n')}\n', flush: true);
    }
    return kept.length - 1;
  }

  int _countDataRows(List<String> lines) {
    var count = 0;
    for (final line in lines.skip(1)) {
      if (line.trim().isNotEmpty) count++;
    }
    return count;
  }

  int? _fileSize(String path) {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : null;
  }
}
