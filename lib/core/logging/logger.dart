/// Minimal leveled logging for diagnostics and debugging.
///
/// Failures are additionally recorded in `diagnostics.json` via the session
/// diagnostics recorder; this logger is for console/development output only.
library;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

typedef LogSink = void Function(LogLevel level, String message, Object? error);

/// Routes log lines to an injectable sink (defaults to `debugPrint`).
class Logger {
  Logger({LogSink? sink}) : _sink = sink ?? _defaultSink;

  final LogSink _sink;

  static void _defaultSink(LogLevel level, String message, Object? error) {
    final suffix = error == null ? '' : ' | error: $error';
    debugPrint('[${level.name}] $message$suffix');
  }

  void debug(String message) => _sink(LogLevel.debug, message, null);

  void info(String message) => _sink(LogLevel.info, message, null);

  void warn(String message, [Object? error]) =>
      _sink(LogLevel.warn, message, error);

  void error(String message, [Object? error]) =>
      _sink(LogLevel.error, message, error);
}
