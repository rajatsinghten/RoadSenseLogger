/// Recording orchestration (FR-001..006, architecture §5).
///
/// Owns the recording state machine and the session's recorders/writer. All
/// platform integrations are injected through seams, so the full lifecycle —
/// including failure paths — is unit-testable with deterministic fakes.
///
/// Memory: the recording path is bounded (writer buffers + native queues).
/// Finalization intentionally holds the session's IMU/GPS series in memory to
/// interpolate `merged.csv` at full precision; the series is released when the
/// manager is reset.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/core/time/timestamps.dart';
import 'package:roadsense_logger/data/session/json_writer.dart';
import 'package:roadsense_logger/data/session/session_paths.dart';
import 'package:roadsense_logger/data/session/session_store.dart';
import 'package:roadsense_logger/data/session/session_validator.dart';
import 'package:roadsense_logger/data/session/session_writer.dart';
import 'package:roadsense_logger/domain/models/diagnostic_event.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/domain/models/imu_event.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/location/gps_recorder.dart';
import 'package:roadsense_logger/services/location/gps_stats.dart';
import 'package:roadsense_logger/services/location/location_source.dart';
import 'package:roadsense_logger/services/native/native_control.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';
import 'package:roadsense_logger/services/resampling/resampler.dart';
import 'package:roadsense_logger/services/sensors/sensor_recorder.dart';
import 'package:roadsense_logger/services/sensors/sensor_source.dart';

/// Live view of an in-progress recording (FR-004).
class RecordingSnapshot {
  const RecordingSnapshot({
    required this.state,
    required this.elapsedS,
    required this.sensorReport,
    required this.gpsReport,
    required this.freeStorageBytes,
    required this.warnings,
  });

  final RecordingState state;
  final double elapsedS;
  final SensorReport sensorReport;
  final GpsReport gpsReport;
  final int freeStorageBytes;
  final List<String> warnings;
}

class RecordingSessionManager implements RecordingController {
  RecordingSessionManager({
    required this.sensors,
    required this.location,
    required this.video,
    required this.native,
    required this.store,
    this.appVersion = '1.0.0+1',
    this.minFreeStorageBytes = 500 * 1024 * 1024,
    this.tickInterval = const Duration(seconds: 1),
    int Function()? monotonicNow,
  }) : _clockOverride = monotonicNow {
    _machine = RecordingStateMachine();
  }

  final SensorSource sensors;
  final LocationSource location;
  final VideoRecorder video;
  final NativeControl native;
  final SessionStore store;
  final String appVersion;
  final int minFreeStorageBytes;
  final Duration tickInterval;

  /// Test override for the monotonic clock; production uses an elapsed-
  /// realtime-anchored stopwatch (see [_nowNs]).
  final int Function()? _clockOverride;

  Stopwatch? _stopwatch;
  int _anchorNs = 0;

  late final RecordingStateMachine _machine;
  final DiagnosticsRecorder _diagnostics = DiagnosticsRecorder();
  final List<ImuEvent> _imuEvents = <ImuEvent>[];
  final List<GpsFix> _gpsFixes = <GpsFix>[];

  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();
  final StreamController<RecordingSnapshot> _snapshotController =
      StreamController<RecordingSnapshot>.broadcast();

  SessionConfig? _config;
  SessionPaths? _paths;
  SessionWriter? _writer;
  SensorRecorder? _sensorRecorder;
  GpsRecorder? _gpsRecorder;
  Timer? _ticker;
  ClockMapping? _clockMapping;
  DeviceInfo? _deviceInfo;
  int? _videoStartNs;
  int? _videoEndNs;
  String? _videoStartReference;
  String? _videoResolutionPreset;
  int? _videoFileSizeBytes;
  bool _interrupted = false;
  String? _interruptionReason;
  int _freeStorageBytes = 0;
  SessionMetadata? _lastMetadata;

  @override
  RecordingState get state => _machine.state;

  VideoConfig? _preparedConfig;

  /// Initializes the camera for the live preview before recording starts
  /// (FR-013). Reused by [start] when the configuration matches.
  @override
  Future<void> prepareCamera(VideoConfig config) async {
    if (video.isInitialized &&
        _preparedConfig != null &&
        _preparedConfig!.matches(config)) {
      return;
    }
    await video.initialize(config);
    _preparedConfig = config;
  }

  Stream<RecordingState> get stateChanges => _stateController.stream;

  @override
  Stream<RecordingSnapshot> get snapshots => _snapshotController.stream;

  SessionPaths? get sessionPaths => _paths;

  /// Metadata of the most recently completed session, if any.
  @override
  SessionMetadata? get lastMetadata => _lastMetadata;

  /// Monotonic clock in elapsed-realtime nanoseconds. Production anchors a
  /// stopwatch at the session clock-mapping sample so wall-clock changes can
  /// never disturb it (FR-043); tests inject [monotonicNow].
  int _nowNs() {
    final override = _clockOverride;
    if (override != null) return override();
    final stopwatch = _stopwatch;
    if (stopwatch != null) {
      return _anchorNs + stopwatch.elapsedMicroseconds * 1000;
    }
    return DateTime.now().microsecondsSinceEpoch * 1000;
  }

  void _transition(RecordingState next, {String? reason}) {
    _machine.transition(next, reason: reason);
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Starts a recording session (IDLE → PREPARING → RECORDING).
  @override
  Future<void> start(SessionConfig config) async {
    _transition(RecordingState.preparing, reason: 'user start');
    _config = config;
    _interrupted = false;
    _interruptionReason = null;
    try {
      final paths = await store.createSession();
      _paths = paths;
      _clockMapping = await native.getClockMapping();
      _anchorNs = _clockMapping!.sessionStartElapsedNs;
      _stopwatch = Stopwatch()..start();
      _deviceInfo = await native.getDeviceInfo();

      final writer = SessionWriter(
        paths: paths,
        clockMapping: _clockMapping!,
        nowNs: _nowNs,
      );
      _writer = writer;
      await writer.open();

      _freeStorageBytes = await native.getFreeStorageBytes();
      if (_freeStorageBytes < minFreeStorageBytes) {
        throw StorageFailure(
          'Insufficient storage: ${_freeStorageBytes ~/ (1024 * 1024)} MB free, '
          'need at least ${minFreeStorageBytes ~/ (1024 * 1024)} MB',
        );
      }

      await prepareCamera(
        VideoConfig(
          width: config.settings.videoWidth,
          height: config.settings.videoHeight,
          fps: config.settings.videoFps,
          audio: config.settings.audioEnabled,
        ),
      );

      final sensorRecorder = SensorRecorder(
        source: sensors,
        onEvents: _onImuEvents,
        onDiagnostic: _diagnostics.record,
        nowNs: _nowNs,
      );
      _sensorRecorder = sensorRecorder;
      await sensorRecorder.start(
        accPeriodUs: config.settings.imuRate.periodUs,
        gyroPeriodUs: config.settings.imuRate.periodUs,
      );
      if (!sensorRecorder.gyroscopeAvailable) {
        _diagnostics.record(
          DiagnosticEvent(
            timestampNs: _nowNs(),
            type: 'gyroscope_unavailable',
            message: 'No gyroscope on this device; gyro columns will be empty',
          ),
        );
      }

      final gpsRecorder = GpsRecorder(
        source: location,
        onFix: _onGpsFix,
        onDiagnostic: _diagnostics.record,
        nowNs: _nowNs,
      );
      _gpsRecorder = gpsRecorder;
      try {
        await gpsRecorder.start(intervalMs: 1000);
      } catch (error) {
        _diagnostics.record(
          DiagnosticEvent(
            timestampNs: _nowNs(),
            type: 'gps_unavailable',
            message: 'GPS could not be started: $error',
          ),
        );
      }

      await native.startForeground(audio: config.settings.audioEnabled);

      final startInfo = await video.startRecording();
      _videoStartNs = startInfo.videoStartNs;
      _videoStartReference = startInfo.reference;
      _videoResolutionPreset = startInfo.resolutionPreset;
      writer.setVideoStartNs(startInfo.videoStartNs);

      _transition(RecordingState.recording, reason: 'subsystems ready');
      _ticker = Timer.periodic(tickInterval, (_) => _onTick());
      _emitSnapshot();
    } catch (error, stackTrace) {
      await _releaseResources();
      _diagnostics.record(
        DiagnosticEvent(
          timestampNs: _nowNs(),
          type: 'start_failure',
          message: 'Recording failed to start: $error',
        ),
      );
      _transition(RecordingState.error, reason: error.toString());
      _emitSnapshot();
      Error.throwWithStackTrace(
        error is AppFailure
            ? error
            : AppFailure('Recording failed to start', cause: error),
        stackTrace,
      );
    }
  }

  /// Stops recording and finalizes all session files
  /// (RECORDING → FINALIZING → COMPLETED).
  @override
  Future<void> stop() async {
    _transition(RecordingState.finalizing, reason: 'user stop');
    await _finalize();
  }

  /// Marks an interruption (camera loss, storage exhaustion, …) and
  /// finalizes best-effort (RECORDING → INTERRUPTED → FINALIZING).
  @override
  Future<void> interrupt(String reason) async {
    _transition(RecordingState.interrupted, reason: reason);
    _interrupted = true;
    _interruptionReason = reason;
    _diagnostics.record(
      DiagnosticEvent(
        timestampNs: _nowNs(),
        type: 'recording_interrupted',
        message: reason,
      ),
    );
    _transition(RecordingState.finalizing, reason: 'after interruption');
    await _finalize();
  }

  Future<void> _finalize() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      await _sensorRecorder?.stop();
      await _gpsRecorder?.stop();
      _writer?.flush();

      try {
        final endInfo = await video.stopRecording(_paths!.videoFile);
        _videoEndNs = endInfo.videoEndNs;
        _videoFileSizeBytes = endInfo.fileSizeBytes;
      } catch (error) {
        _interrupted = true;
        _interruptionReason ??= 'video finalization failed: $error';
        _diagnostics.record(
          DiagnosticEvent(
            timestampNs: _nowNs(),
            type: 'camera_failure',
            message: 'Video finalization failed: $error',
          ),
        );
      }
      await video.dispose();
      await _writer?.finalizeNames();
      await native.stopForeground();

      final config = _config!;
      final startNs = _videoStartNs;
      final endNs = _videoEndNs;
      if (startNs == null || endNs == null) {
        throw ValidationFailure('Video interval is unknown; cannot merge');
      }

      final resampler = Resampler(
        rateHz: config.settings.mergedRateHz,
        maxImuGapMs: config.settings.maxImuGapMs,
        maxGpsAgeS: config.settings.maxGpsAgeS,
      );
      final result = resampler.generate(
        imuEvents: _imuEvents,
        gpsFixes: _gpsFixes,
        videoStartNs: startNs,
        videoEndNs: endNs,
        clockMapping: _clockMapping!,
      );
      await _writeMerged(result.rows);

      final validation = await SessionValidator.validate(
        _paths!,
        expectedImuRows: _writer!.imuRowCount,
        expectedGpsRows: _writer!.gpsRowCount,
        expectedMergedRows: result.rows.length,
      );

      final status = validation.isValid
          ? SessionStatus.completed
          : SessionStatus.incomplete;
      if (!validation.isValid) {
        _diagnostics.record(
          DiagnosticEvent(
            timestampNs: _nowNs(),
            type: 'validation_failure',
            message:
                'Session validation failed: ${validation.problems.join('; ')}',
            context: {'problems': validation.problems},
          ),
        );
      }

      final gpsStats = GpsStats.compute(_gpsFixes);
      final sensorReport = _sensorRecorder?.report();
      final gpsReport = _gpsRecorder?.report();
      final endElapsedNs = await native.getElapsedNs();
      final metadata = SessionMetadata(
        appVersion: appVersion,
        sessionId: _paths!.sessionDir.path.split('/').last,
        status: status,
        clockMapping: _clockMapping!,
        config: config,
        manufacturer: _deviceInfo?.manufacturer ?? '',
        model: _deviceInfo?.model ?? '',
        androidVersion: _deviceInfo?.androidVersion ?? '',
        sessionEndElapsedNs: endElapsedNs,
        sessionEndUnixMs: _clockMapping!.unixMsFromElapsedNs(endElapsedNs),
        durationS: (endNs - startNs) / 1e9,
        videoStartNs: startNs,
        videoEndNs: endNs,
        videoStartReference: _videoStartReference,
        videoRequestedWidth: config.settings.videoWidth,
        videoRequestedHeight: config.settings.videoHeight,
        videoRequestedFps: config.settings.videoFps,
        videoResolutionPreset: _videoResolutionPreset,
        videoFileSizeBytes: _videoFileSizeBytes,
        videoAudioEnabled: config.settings.audioEnabled,
        sensorInfos: await sensors.getSensorInfo(),
        requestedImuRate: config.settings.imuRate.label,
        accStats: SensorRateStats(
          eventCount: sensorReport?.accCount ?? 0,
          achievedRateHz: sensorReport?.accAvgRateHz,
        ),
        gyroStats: SensorRateStats(
          eventCount: sensorReport?.gyroCount ?? 0,
          achievedRateHz: sensorReport?.gyroAvgRateHz,
        ),
        gpsRequestedIntervalMs: 1000,
        gpsFixCount: gpsReport?.acceptedCount ?? 0,
        gpsRejectedCount: gpsReport?.rejectedCount ?? 0,
        gpsOutageCount: gpsReport?.outageCount ?? 0,
        gpsDistanceM: gpsStats.distanceM,
        gpsAvgSpeedMps: gpsStats.avgSpeedMps,
        mergedRateHz: config.settings.mergedRateHz,
        mergedRowCount: result.rows.length,
        quality: {
          'acc_event_count': sensorReport?.accCount ?? 0,
          'gyro_event_count': sensorReport?.gyroCount ?? 0,
          'gps_fix_count': gpsReport?.acceptedCount ?? 0,
          'sensor_gap_count': sensorReport?.gapCount ?? 0,
          'dropped_events': sensorReport?.droppedCount ?? 0,
          'pre_roll_dropped_rows': _writer!.droppedPreRollRows,
          'imu_events_outside_video_interval':
              result.accEventsOutsideInterval +
              result.gyroEventsOutsideInterval,
          'gps_fixes_outside_video_interval': result.gpsFixesOutsideInterval,
          'acc_missing_rows': result.accMissingRows,
          'gyro_missing_rows': result.gyroMissingRows,
          'gps_missing_rows': result.gpsMissingRows,
          'gps_stale_rows': result.gpsStaleRows,
        },
        interrupted: _interrupted,
        interruptionReason: _interruptionReason,
      );

      await writeJsonFile(_paths!.diagnosticsFile, _diagnostics.toJson());
      // Written last: presence of a valid metadata.json marks completion.
      await writeJsonFile(_paths!.metadataFile, metadata.toJson());
      _lastMetadata = metadata;

      if (validation.isValid) {
        _transition(RecordingState.completed);
      } else {
        _transition(RecordingState.error, reason: 'validation failed');
      }
    } catch (error, stackTrace) {
      await _releaseResources();
      _diagnostics.record(
        DiagnosticEvent(
          timestampNs: _nowNs(),
          type: 'finalization_failure',
          message: 'Finalization failed: $error',
        ),
      );
      if (_machine.canTransition(RecordingState.error)) {
        _transition(RecordingState.error, reason: error.toString());
      }
      _emitSnapshot();
      Error.throwWithStackTrace(
        error is AppFailure
            ? error
            : AppFailure('Finalization failed', cause: error),
        stackTrace,
      );
    }
    _emitSnapshot();
  }

  Future<void> _writeMerged(List<MergedRow> rows) async {
    final buffer = StringBuffer(MergedRow.header)..write('\n');
    for (final row in rows) {
      buffer.write(row.toCsv());
      buffer.write('\n');
    }
    await File(
      _paths!.mergedFile,
    ).writeAsString(buffer.toString(), flush: true);
  }

  void _onImuEvents(List<ImuEvent> events) {
    _imuEvents.addAll(events);
    _writer?.addImuEvents(events);
  }

  void _onGpsFix(GpsFix fix) {
    _gpsFixes.add(fix);
    _writer?.addGpsFix(fix);
  }

  void _onTick() {
    try {
      _writer?.flush();
    } on StorageFailure catch (error) {
      unawaited(interrupt('storage write failed: $error'));
      return;
    }
    _gpsRecorder?.checkStaleness();
    _emitSnapshot();
  }

  Future<void> _releaseResources() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      await _sensorRecorder?.stop();
    } catch (_) {}
    try {
      await _gpsRecorder?.stop();
    } catch (_) {}
    try {
      await video.dispose();
    } catch (_) {}
    try {
      _writer?.close();
    } catch (_) {}
    try {
      await native.stopForeground();
    } catch (_) {}
  }

  /// Emits the current live snapshot (also called by the 1 Hz ticker).
  void _emitSnapshot() {
    if (_snapshotController.isClosed) return;
    _snapshotController.add(snapshot());
  }

  @override
  Widget buildPreview() => video.buildPreview();

  @override
  RecordingSnapshot snapshot() {
    final sensorReport =
        _sensorRecorder?.report() ??
        const SensorReport(
          accCount: 0,
          gyroCount: 0,
          accAvgRateHz: null,
          gyroAvgRateHz: null,
          accLiveRateHz: null,
          gyroLiveRateHz: null,
          accLastMagnitude: null,
          gyroLastMagnitude: null,
          gyroscopeAvailable: true,
          gapCount: 0,
          droppedCount: 0,
        );
    final gpsReport =
        _gpsRecorder?.report() ??
        const GpsReport(
          acceptedCount: 0,
          rejectedCount: 0,
          lastFix: null,
          lastFixAgeS: null,
          outageCount: 0,
        );
    final startNs = _videoStartNs;
    final elapsedS = startNs == null ? 0.0 : max(0, _nowNs() - startNs) / 1e9;

    final warnings = <String>[
      if (!sensorReport.gyroscopeAvailable)
        'Gyroscope unavailable: gyro columns will be empty',
      if (gpsReport.acceptedCount == 0) 'No GPS fix received yet',
      if (gpsReport.acceptedCount > 0 && gpsReport.isStale(5))
        'GPS data is stale',
      if (_freeStorageBytes < minFreeStorageBytes * 2) 'Storage is low',
    ];

    return RecordingSnapshot(
      state: _machine.state,
      elapsedS: elapsedS,
      sensorReport: sensorReport,
      gpsReport: gpsReport,
      freeStorageBytes: _freeStorageBytes,
      warnings: warnings,
    );
  }

  /// Releases session data and returns the machine to IDLE for the next run.
  @override
  void reset() {
    _transition(RecordingState.idle);
    _imuEvents.clear();
    _gpsFixes.clear();
    _config = null;
    _paths = null;
    _writer = null;
    _sensorRecorder = null;
    _gpsRecorder = null;
    _videoStartNs = null;
    _videoEndNs = null;
    _interrupted = false;
    _interruptionReason = null;
  }

  /// Disposes streams and timers (manager is unusable afterwards).
  Future<void> dispose() async {
    _ticker?.cancel();
    await _stateController.close();
    await _snapshotController.close();
  }
}
