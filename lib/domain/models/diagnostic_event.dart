/// Timestamped data-quality event for `diagnostics.json` (DATA-005).
library;

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestampNs,
    required this.type,
    required this.message,
    this.context = const {},
  });

  /// Elapsed-realtime nanoseconds when the event was observed.
  final int timestampNs;

  /// Machine-readable category, e.g. `sensor_gap`, `queue_overflow`,
  /// `gps_outage`, `storage_error`, `camera_failure`, `recovery`.
  final String type;

  final String message;
  final Map<String, Object?> context;

  Map<String, Object?> toJson() => {
    'timestamp_ns': timestampNs,
    'type': type,
    'message': message,
    'context': context,
  };
}
