/// GPS-derived trip statistics (DATA-004). Distances use the haversine
/// formula over consecutive accepted fixes; values are null (never zero)
/// when there is insufficient data.
library;

import 'dart:math' as math;

import 'package:roadsense_logger/domain/models/gps_fix.dart';

/// Great-circle distance between two coordinates in meters.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusM = 6371008.8;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.sqrt(a));
}

double _rad(double deg) => deg * math.pi / 180;

class GpsStats {
  const GpsStats({required this.distanceM, required this.avgSpeedMps});

  final double? distanceM;
  final double? avgSpeedMps;

  /// Computes distance along consecutive fixes (in timestamp order) and
  /// average speed over the fix timespan. Null when fewer than two fixes.
  static GpsStats compute(List<GpsFix> fixes) {
    if (fixes.length < 2) {
      return const GpsStats(distanceM: null, avgSpeedMps: null);
    }
    final sorted = List<GpsFix>.of(fixes)
      ..sort((a, b) => a.timestampNs.compareTo(b.timestampNs));
    var distance = 0.0;
    for (var i = 1; i < sorted.length; i++) {
      distance += haversineMeters(
        sorted[i - 1].latitude,
        sorted[i - 1].longitude,
        sorted[i].latitude,
        sorted[i].longitude,
      );
    }
    final spanS = (sorted.last.timestampNs - sorted.first.timestampNs) / 1e9;
    final avgSpeed = spanS > 0 ? distance / spanS : null;
    return GpsStats(distanceM: distance, avgSpeedMps: avgSpeed);
  }
}
