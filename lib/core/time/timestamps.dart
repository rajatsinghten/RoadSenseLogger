/// Monotonic time math for session synchronization.
///
/// Master clock: Android elapsed realtime (`SystemClock.elapsedRealtimeNanos()`).
/// All relative timestamps use double precision (DATA-006).
library;

/// Conversion helpers for video-relative and Unix timestamps.
class Timestamps {
  const Timestamps._();

  /// Seconds relative to video start: `(timestamp_ns - video_start_ns) / 1e9`.
  ///
  /// Negative for events captured before the video recording-start reference.
  static double tVideoS(int timestampNs, int videoStartNs) {
    return (timestampNs - videoStartNs) / 1e9;
  }
}

/// Captured relationship between elapsed realtime and wall-clock time.
///
/// Sampled once per session. Wall-clock changes afterwards do not disturb
/// monotonic alignment; Unix values derived from this mapping are estimates.
class ClockMapping {
  const ClockMapping({
    required this.sessionStartElapsedNs,
    required this.sessionStartUnixMs,
  });

  /// Elapsed-realtime nanoseconds at the moment the mapping was sampled.
  final int sessionStartElapsedNs;

  /// Wall-clock Unix milliseconds at the moment the mapping was sampled.
  final int sessionStartUnixMs;

  /// Estimated Unix time in milliseconds for a monotonic [timestampNs].
  ///
  /// `unix_ms = session_start_unix_ms + (timestamp_ns - session_start_elapsed_ns) / 1e6`,
  /// rounded to the nearest millisecond.
  int unixMsFromElapsedNs(int timestampNs) {
    final deltaMs = (timestampNs - sessionStartElapsedNs) / 1e6;
    return sessionStartUnixMs + deltaMs.round();
  }

  Map<String, Object> toJson() => {
        'session_start_elapsed_ns': sessionStartElapsedNs,
        'session_start_unix_ms': sessionStartUnixMs,
      };

  factory ClockMapping.fromJson(Map<String, Object?> json) {
    return ClockMapping(
      sessionStartElapsedNs: (json['session_start_elapsed_ns'] as num).toInt(),
      sessionStartUnixMs: (json['session_start_unix_ms'] as num).toInt(),
    );
  }
}
