/// Accepted GPS fix model (DATA-002). Optional fields are null when the
/// underlying `Location.has*()` reported them absent — never zero-substituted.
library;

class GpsFix {
  const GpsFix({
    required this.timestampNs,
    required this.unixTimeMs,
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    this.speedMps,
    this.bearingDeg,
    this.accuracyM,
  });

  /// Original `Location.elapsedRealtimeNanos` of the fix.
  final int timestampNs;

  /// Wall-clock time reported by the fix.
  final int unixTimeMs;

  final double latitude;
  final double longitude;

  /// null when the provider did not report the value.
  final double? altitudeM;
  final double? speedMps;
  final double? bearingDeg;
  final double? accuracyM;

  /// Whether the fix satisfies acceptance rules (FR-031).
  static bool isValid({
    required double latitude,
    required double longitude,
    required int timestampNs,
  }) {
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        timestampNs > 0;
  }
}
