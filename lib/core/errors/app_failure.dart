/// Application failure hierarchy (FR-081): actionable messages, never silent.
library;

/// Base class for failures surfaced to the UI and diagnostics.
class AppFailure implements Exception {
  AppFailure(this.message, {this.cause, this.context = const {}});

  /// Human-readable, actionable description.
  final String message;

  /// Underlying cause, if any.
  final Object? cause;

  /// Structured context for diagnostics.
  final Map<String, Object?> context;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) buffer.write(' (cause: $cause)');
    return buffer.toString();
  }
}

/// Illegal recording state transition (FR-002).
class StateTransitionError extends AppFailure {
  StateTransitionError(super.message, {super.cause, super.context});
}

/// Storage and file I/O failures (FR-054).
class StorageFailure extends AppFailure {
  StorageFailure(super.message, {super.cause, super.context});
}

/// Dataset or session validation failures (FR-003).
class ValidationFailure extends AppFailure {
  ValidationFailure(super.message, {super.cause, super.context});
}

/// Camera initialization/recording failures (FR-015).
class CameraFailure extends AppFailure {
  CameraFailure(super.message, {super.cause, super.context});
}

/// Sensor collection failures (FR-027).
class SensorFailure extends AppFailure {
  SensorFailure(super.message, {super.cause, super.context});
}

/// Export/share failures (FR-071).
class ExportFailure extends AppFailure {
  ExportFailure(super.message, {super.cause, super.context});
}
