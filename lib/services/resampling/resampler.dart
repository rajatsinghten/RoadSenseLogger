/// Uniform-grid resampling for `merged.csv` (FR-060..063, DATA-003).
///
/// Grid: `t_i = i / rateHz` seconds (video-relative), i = 0..floor((t1-t0)*rate),
/// computed from `i` directly so no cumulative floating-point drift builds up.
/// Start is inclusive (first point at `t0`); the last point is the largest
/// `t_i <= t1`.
///
/// IMU: linear interpolation over actual timestamps between the bracketing
/// samples, only when the bracketing gap is <= `maxImuGapMs`. A grid point
/// landing exactly on sample timestamp(s) takes the last-arriving sample at
/// that timestamp (deterministic; duplicates are never averaged). Otherwise
/// missing values are emitted as null (never zero).
///
/// GPS: forward-fill from the latest fix at or before the grid point (never a
/// future fix). `gpsAgeS` always reports the real age of the used fix; fixes
/// older than `maxGpsAgeS` produce empty GPS fields but keep `gpsAgeS`.
library;

import 'package:roadsense_logger/core/csv/csv.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';

/// One row of `merged.csv`.
class MergedRow {
  const MergedRow({
    required this.tVideoS,
    required this.unixTimeMs,
    this.accX,
    this.accY,
    this.accZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.latitude,
    this.longitude,
    this.altitudeM,
    this.speedMps,
    this.bearingDeg,
    this.gpsAccuracyM,
    this.gpsAgeS,
  });

  final double tVideoS;
  final int unixTimeMs;
  final double? accX, accY, accZ;
  final double? gyroX, gyroY, gyroZ;
  final double? latitude, longitude, altitudeM, speedMps, bearingDeg;
  final double? gpsAccuracyM;
  final double? gpsAgeS;

  static const header =
      't_video_s,unix_time_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z,'
      'latitude,longitude,altitude_m,speed_mps,bearing_deg,gps_accuracy_m,'
      'gps_age_s,label';

  String toCsv() => Csv.row([
    Csv.formatDouble(tVideoS),
    Csv.formatInt(unixTimeMs),
    Csv.formatDouble(accX),
    Csv.formatDouble(accY),
    Csv.formatDouble(accZ),
    Csv.formatDouble(gyroX),
    Csv.formatDouble(gyroY),
    Csv.formatDouble(gyroZ),
    Csv.formatDouble(latitude),
    Csv.formatDouble(longitude),
    Csv.formatDouble(altitudeM),
    Csv.formatDouble(speedMps),
    Csv.formatDouble(bearingDeg),
    Csv.formatDouble(gpsAccuracyM),
    Csv.formatDouble(gpsAgeS),
    '', // label: reserved for later manual annotation
  ]);
}

class ResampleResult {
  const ResampleResult({
    required this.rows,
    required this.accEventsOutsideInterval,
    required this.gyroEventsOutsideInterval,
    required this.gpsFixesOutsideInterval,
    required this.accMissingRows,
    required this.gyroMissingRows,
    required this.gpsMissingRows,
    required this.gpsStaleRows,
  });

  final List<MergedRow> rows;
  final int accEventsOutsideInterval;
  final int gyroEventsOutsideInterval;
  final int gpsFixesOutsideInterval;
  final int accMissingRows;
  final int gyroMissingRows;
  final int gpsMissingRows;

  /// Rows where a fix existed but exceeded the staleness limit.
  final int gpsStaleRows;
}

class Resampler {
  Resampler({
    required this.rateHz,
    required this.maxImuGapMs,
    required this.maxGpsAgeS,
  }) : assert(rateHz > 0);

  /// Uniform grid rate in Hz (default 100 via callers).
  final double rateHz;

  /// Bracketing gaps above this are not interpolated across (ms).
  final double maxImuGapMs;

  /// Forward-filled fixes older than this are treated as missing (seconds).
  final double maxGpsAgeS;

  ResampleResult generate({
    required List<ImuEvent> imuEvents,
    required List<GpsFix> gpsFixes,
    required int videoStartNs,
    required int videoEndNs,
    required ClockMapping clockMapping,
  }) {
    final acc = _stableByTimestamp(
      imuEvents.where((e) => e.sensor == ImuSensorKind.acc).toList(),
    );
    final gyro = _stableByTimestamp(
      imuEvents.where((e) => e.sensor == ImuSensorKind.gyro).toList(),
    );
    final gps = _stableByTimestampGps(gpsFixes.toList());

    final maxGapNs = (maxImuGapMs * 1e6).round();
    final maxGpsAgeNs = (maxGpsAgeS * 1e9).round();

    final intervalNs = videoEndNs - videoStartNs;
    final gridCount = intervalNs < 0
        ? 0
        : (intervalNs / 1e9 * rateHz).floor() + 1;

    final rows = <MergedRow>[];
    var accMissing = 0;
    var gyroMissing = 0;
    var gpsMissing = 0;
    var gpsStale = 0;

    for (var i = 0; i < gridCount; i++) {
      final tVideoS = i / rateHz;
      final gridNs = videoStartNs + (tVideoS * 1e9).round();

      final accPoint = _interpolate(acc, gridNs, maxGapNs);
      final gyroPoint = _interpolate(gyro, gridNs, maxGapNs);
      final gpsPoint = _forwardFill(gps, gridNs, maxGpsAgeNs);

      if (accPoint == null) accMissing++;
      if (gyroPoint == null) gyroMissing++;
      if (gpsPoint == null) {
        gpsMissing++;
      } else if (gpsPoint.stale) {
        gpsStale++;
      }

      rows.add(
        MergedRow(
          tVideoS: tVideoS,
          unixTimeMs: clockMapping.unixMsFromElapsedNs(gridNs),
          accX: accPoint?.x,
          accY: accPoint?.y,
          accZ: accPoint?.z,
          gyroX: gyroPoint?.x,
          gyroY: gyroPoint?.y,
          gyroZ: gyroPoint?.z,
          latitude: gpsPoint?.latitude,
          longitude: gpsPoint?.longitude,
          altitudeM: gpsPoint?.altitudeM,
          speedMps: gpsPoint?.speedMps,
          bearingDeg: gpsPoint?.bearingDeg,
          gpsAccuracyM: gpsPoint?.accuracyM,
          gpsAgeS: gpsPoint?.ageS,
        ),
      );
    }

    return ResampleResult(
      rows: rows,
      accEventsOutsideInterval: _outside(acc, videoStartNs, videoEndNs),
      gyroEventsOutsideInterval: _outside(gyro, videoStartNs, videoEndNs),
      gpsFixesOutsideInterval: _outsideGps(gps, videoStartNs, videoEndNs),
      accMissingRows: accMissing,
      gyroMissingRows: gyroMissing,
      gpsMissingRows: gpsMissing,
      gpsStaleRows: gpsStale,
    );
  }

  ({double x, double y, double z})? _interpolate(
    List<ImuEvent> sorted,
    int gridNs,
    int maxGapNs,
  ) {
    if (sorted.isEmpty) return null;
    final ts = [for (final e in sorted) e.timestampNs];
    final exactIdx = _upperBound(ts, gridNs) - 1;
    if (exactIdx >= 0 && ts[exactIdx] == gridNs) {
      final e = sorted[exactIdx];
      return (x: e.x, y: e.y, z: e.z);
    }
    final leftIdx = exactIdx;
    final rightIdx = _lowerBound(ts, gridNs);
    if (leftIdx < 0 || rightIdx >= sorted.length) return null;
    final left = sorted[leftIdx];
    final right = sorted[rightIdx];
    final gapNs = right.timestampNs - left.timestampNs;
    if (gapNs <= 0 || gapNs > maxGapNs) return null;
    final alpha = (gridNs - left.timestampNs) / gapNs;
    return (
      x: left.x + alpha * (right.x - left.x),
      y: left.y + alpha * (right.y - left.y),
      z: left.z + alpha * (right.z - left.z),
    );
  }

  ({
    double? latitude,
    double? longitude,
    double? altitudeM,
    double? speedMps,
    double? bearingDeg,
    double? accuracyM,
    double ageS,
    bool stale,
  })?
  _forwardFill(List<GpsFix> sorted, int gridNs, int maxGpsAgeNs) {
    if (sorted.isEmpty) return null;
    final ts = [for (final f in sorted) f.timestampNs];
    final idx = _upperBound(ts, gridNs) - 1;
    if (idx < 0) return null;
    final fix = sorted[idx];
    final ageNs = gridNs - fix.timestampNs;
    final stale = ageNs > maxGpsAgeNs;
    return (
      latitude: stale ? null : fix.latitude,
      longitude: stale ? null : fix.longitude,
      altitudeM: stale ? null : fix.altitudeM,
      speedMps: stale ? null : fix.speedMps,
      bearingDeg: stale ? null : fix.bearingDeg,
      accuracyM: stale ? null : fix.accuracyM,
      ageS: ageNs / 1e9,
      stale: stale,
    );
  }

  int _outside(List<ImuEvent> events, int startNs, int endNs) => events
      .where((e) => e.timestampNs < startNs || e.timestampNs > endNs)
      .length;

  int _outsideGps(List<GpsFix> fixes, int startNs, int endNs) => fixes
      .where((f) => f.timestampNs < startNs || f.timestampNs > endNs)
      .length;

  /// First index with `values[i] >= value`.
  static int _lowerBound(List<int> values, int value) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (values[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// First index with `values[i] > value`.
  static int _upperBound(List<int> values, int value) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (values[mid] <= value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Stable sort keeps arrival order among duplicate timestamps, so the
  /// "last-arriving sample at a timestamp" rule is deterministic.
  static List<ImuEvent> _stableByTimestamp(List<ImuEvent> events) {
    final indexed = <(int, ImuEvent)>[
      for (var i = 0; i < events.length; i++) (i, events[i]),
    ];
    indexed.sort((a, b) {
      final c = a.$2.timestampNs.compareTo(b.$2.timestampNs);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  static List<GpsFix> _stableByTimestampGps(List<GpsFix> fixes) {
    final indexed = <(int, GpsFix)>[
      for (var i = 0; i < fixes.length; i++) (i, fixes[i]),
    ];
    indexed.sort((a, b) {
      final c = a.$2.timestampNs.compareTo(b.$2.timestampNs);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }
}
