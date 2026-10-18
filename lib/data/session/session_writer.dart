/// Incremental CSV persistence for raw session data (FR-052, DATA-001/2/7).
///
/// Rows are buffered in memory and flushed to disk at most once per
/// [flushInterval] or every [maxBufferedRows] rows — never from sensor
/// callbacks themselves. Flushes use bounded synchronous appends so a flush
/// is deterministic and its failures surface as [StorageFailure] (FR-054).
/// Files are written under `.part` names and renamed by [finalizeNames] so
/// incomplete sessions stay identifiable (FR-055).
library;

import 'dart:io';

import 'package:roadsense_logger/core/csv/csv.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/data/session/session_paths.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';

class SessionWriter {
  SessionWriter({
    required this.paths,
    required this.clockMapping,
    required int Function() nowNs,
    this.flushIntervalNs = 1000 * 1000 * 1000,
    this.maxBufferedRows = 5000,
    this.maxPendingPreRollRows = 50000,
  }) : _nowNs = nowNs;

  static const imuHeader = 'timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z';
  static const gpsHeader =
      'timestamp_ns,t_video_s,unix_time_ms,latitude,longitude,altitude_m,'
      'speed_mps,bearing_deg,accuracy_m';

  final SessionPaths paths;
  final ClockMapping clockMapping;
  final int Function() _nowNs;

  /// Rows are flushed to disk at most this often (nanoseconds).
  final int flushIntervalNs;

  /// Rows buffered before a timed flush is triggered.
  final int maxBufferedRows;

  /// Bounded pre-video-start buffer (events awaiting `video_start_ns`).
  final int maxPendingPreRollRows;

  final List<String> _imuRows = <String>[];
  final List<String> _gpsRows = <String>[];
  List<ImuEvent> _pendingPreRoll = <ImuEvent>[];
  int _lastFlushNs = 0;

  int _imuRowCount = 0;
  int _gpsRowCount = 0;
  int _droppedPreRollRows = 0;
  int? _videoStartNs;
  bool _closed = false;

  /// Rows accepted per file (including any dropped from the pre-roll buffer).
  int get imuRowCount => _imuRowCount;
  int get gpsRowCount => _gpsRowCount;

  /// Pre-roll rows dropped by the bounded buffer (never silent).
  int get droppedPreRollRows => _droppedPreRollRows;

  bool get isClosed => _closed;

  Future<void> open() async {
    await paths.sessionDir.create(recursive: true);
    await File(paths.imuPartFile).create();
    await File(paths.gpsPartFile).create();
    File(
      paths.imuPartFile,
    ).writeAsStringSync('$imuHeader\n', mode: FileMode.append);
    File(
      paths.gpsPartFile,
    ).writeAsStringSync('$gpsHeader\n', mode: FileMode.append);
    _lastFlushNs = _nowNs();
  }

  /// Records the video recording-start reference (FR-014). Events buffered
  /// before this point are emitted with negative `t_video_s` (FR-044).
  void setVideoStartNs(int videoStartNs) {
    _videoStartNs = videoStartNs;
    if (_pendingPreRoll.isNotEmpty) {
      _imuRows.insertAll(0, _pendingPreRoll.map(_imuRow));
      _pendingPreRoll = <ImuEvent>[];
    }
  }

  void addImuEvents(List<ImuEvent> events) {
    for (final event in events) {
      if (_videoStartNs == null) {
        if (_pendingPreRoll.length >= maxPendingPreRollRows) {
          _pendingPreRoll.removeAt(0);
          _droppedPreRollRows++;
        }
        _pendingPreRoll.add(event);
      } else {
        _imuRows.add(_imuRow(event));
      }
      _imuRowCount++;
    }
    _maybeFlush();
  }

  void addGpsFix(GpsFix fix) {
    _gpsRows.add(_gpsRow(fix));
    _gpsRowCount++;
    _maybeFlush();
  }

  String _imuRow(ImuEvent event) {
    return Csv.row([
      Csv.formatInt(event.timestampNs),
      Csv.formatDouble(
        _videoStartNs == null
            ? null
            : Timestamps.tVideoS(event.timestampNs, _videoStartNs!),
      ),
      Csv.formatInt(clockMapping.unixMsFromElapsedNs(event.timestampNs)),
      event.sensor.csvId,
      Csv.formatDouble(event.x),
      Csv.formatDouble(event.y),
      Csv.formatDouble(event.z),
    ]);
  }

  String _gpsRow(GpsFix fix) {
    return Csv.row([
      Csv.formatInt(fix.timestampNs),
      Csv.formatDouble(
        _videoStartNs == null
            ? null
            : Timestamps.tVideoS(fix.timestampNs, _videoStartNs!),
      ),
      Csv.formatInt(clockMapping.unixMsFromElapsedNs(fix.timestampNs)),
      Csv.formatDouble(fix.latitude),
      Csv.formatDouble(fix.longitude),
      Csv.formatDouble(fix.altitudeM),
      Csv.formatDouble(fix.speedMps),
      Csv.formatDouble(fix.bearingDeg),
      Csv.formatDouble(fix.accuracyM),
    ]);
  }

  void _maybeFlush() {
    if (_imuRows.length + _gpsRows.length >= maxBufferedRows ||
        _nowNs() - _lastFlushNs >= flushIntervalNs) {
      flush();
    }
  }

  /// Writes buffered rows to disk. Failures surface as [StorageFailure].
  void flush() {
    try {
      if (_imuRows.isNotEmpty) {
        File(
          paths.imuPartFile,
        ).writeAsStringSync('${_imuRows.join('\n')}\n', mode: FileMode.append);
        _imuRows.clear();
      }
      if (_gpsRows.isNotEmpty) {
        File(
          paths.gpsPartFile,
        ).writeAsStringSync('${_gpsRows.join('\n')}\n', mode: FileMode.append);
        _gpsRows.clear();
      }
      _lastFlushNs = _nowNs();
    } catch (error) {
      throw StorageFailure('Failed to write session CSV data', cause: error);
    }
  }

  /// Flushes remaining rows and renames `.part` files to their final names.
  Future<void> finalizeNames() async {
    close();
    await File(paths.imuPartFile).rename(paths.imuFile);
    await File(paths.gpsPartFile).rename(paths.gpsFile);
  }

  void close() {
    if (_closed) return;
    flush();
    _closed = true;
  }
}
