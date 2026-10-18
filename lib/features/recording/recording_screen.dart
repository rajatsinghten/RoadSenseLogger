/// Main recording screen (FR-004): camera preview, live diagnostics and
/// large Record/Stop controls. Contains NO live road-condition labels,
/// marker buttons or classification of any kind (explicitly out of scope).
library;

import 'package:flutter/material.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';
import 'package:roadsense_logger/features/recording/pre_record_dialog.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.controller,
    this.settings = const SessionSettings(),
    this.onOpenSettings,
    this.onOpenHistory,
    this.loadLastConfig,
    this.saveLastConfig,
  });

  final RecordingController controller;

  /// Settings used to prepare the pre-recording camera preview.
  final SessionSettings settings;

  /// Opens the settings screen (wired by the app shell).
  final VoidCallback? onOpenSettings;

  /// Opens the session history (wired by the app shell).
  final VoidCallback? onOpenHistory;

  /// Remembers pre-recording dialog selections (FR-073).
  final Future<SessionConfig?> Function()? loadLastConfig;
  final Future<void> Function(SessionConfig config)? saveLastConfig;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  SessionConfig? _lastConfig;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preparePreview());
  }

  Future<void> _preparePreview() async {
    final settings = _lastConfig?.settings ?? widget.settings;
    try {
      await widget.controller.prepareCamera(
        VideoConfig(
          width: settings.videoWidth,
          height: settings.videoHeight,
          fps: settings.videoFps,
          audio: settings.audioEnabled,
        ),
      );
    } on AppFailure {
      // Surfaced through the preview placeholder below.
    }
    if (mounted) setState(() {});
  }

  Future<void> _startRecording() async {
    final initial = _lastConfig ?? await widget.loadLastConfig?.call();
    if (!mounted) return;
    final config = await showPreRecordDialog(context, initial: initial);
    if (config == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.start(config);
      _lastConfig = config;
      await widget.saveLastConfig?.call(config);
    } on AppFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _busy = true);
    try {
      await widget.controller.stop();
      final id = widget.controller.lastMetadata?.sessionId;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Session saved: $id')));
      }
    } on AppFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RecordingSnapshot>(
      stream: widget.controller.snapshots,
      initialData: widget.controller.snapshot(),
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final recording = data.state == RecordingState.recording;
        return Scaffold(
          appBar: AppBar(
            title: const Text('RoadSense Logger'),
            actions: [
              if (widget.onOpenHistory != null)
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Sessions',
                  onPressed: widget.onOpenHistory,
                ),
              if (widget.onOpenSettings != null)
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: widget.onOpenSettings,
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset to idle',
                onPressed:
                    data.state == RecordingState.completed ||
                        data.state == RecordingState.error
                    ? () => widget.controller.reset()
                    : null,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: _Preview(controller: widget.controller)),
                _DiagnosticsPanel(data: data),
                _Controls(
                  recording: recording,
                  busy: _busy,
                  onStart: _startRecording,
                  onStop: _stopRecording,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    Widget child;
    try {
      child = controller.buildPreview();
    } catch (error) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera preview unavailable\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(child: child),
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.data});

  final RecordingSnapshot data;

  @override
  Widget build(BuildContext context) {
    final speed = data.gpsReport.lastSpeedMps;
    final speedKmh = speed == null ? null : speed * 3.6;
    final fixAge = data.gpsReport.lastFixAgeS;
    final accuracy = data.gpsReport.lastFix?.accuracyM;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            _formatDuration(data.elapsedS),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Metric(
                label: 'Speed',
                value: speedKmh == null
                    ? '—'
                    : '${speedKmh.toStringAsFixed(1)} km/h',
                stale: data.gpsReport.isStale(5),
              ),
              _Metric(
                label: 'GPS',
                value: fixAge == null
                    ? 'no fix'
                    : 'age ${fixAge.toStringAsFixed(1)} s'
                          '${accuracy == null ? '' : ', ±${accuracy.toStringAsFixed(1)} m'}',
                stale: data.gpsReport.isStale(5),
              ),
              _Metric(
                label: 'ACC',
                value: data.sensorReport.accLastMagnitude == null
                    ? '—'
                    : '${data.sensorReport.accLastMagnitude!.toStringAsFixed(2)} m/s²',
              ),
              _Metric(
                label: 'GYRO',
                value: data.sensorReport.gyroLastMagnitude == null
                    ? '—'
                    : '${data.sensorReport.gyroLastMagnitude!.toStringAsFixed(2)} rad/s',
              ),
              _Metric(
                label: 'ACC rate',
                value: data.sensorReport.accLiveRateHz == null
                    ? '—'
                    : '${data.sensorReport.accLiveRateHz!.toStringAsFixed(1)} Hz',
              ),
              _Metric(
                label: 'GYRO rate',
                value: data.sensorReport.gyroLiveRateHz == null
                    ? '—'
                    : '${data.sensorReport.gyroLiveRateHz!.toStringAsFixed(1)} Hz',
              ),
              _Metric(
                label: 'Storage',
                value:
                    '${(data.freeStorageBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB',
              ),
            ],
          ),
          if (data.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  for (final warning in data.warnings)
                    Text(
                      warning,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.stale = false});

  final String label;
  final String value;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: stale ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.recording,
    required this.busy,
    required this.onStart,
    required this.onStop,
  });

  final bool recording;
  final bool busy;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: recording
          ? FilledButton.icon(
              onPressed: busy ? null : onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
            )
          : FilledButton.icon(
              onPressed: busy ? null : onStart,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Record'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
            ),
    );
  }
}

String _formatDuration(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.toInt() : 0;
  final h = (total ~/ 3600).toString().padLeft(2, '0');
  final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
