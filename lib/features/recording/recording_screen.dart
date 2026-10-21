/// Main recording screen (FR-004): camera preview, live diagnostics and
/// large Record/Stop controls. Contains NO live road-condition labels,
/// marker buttons or classification of any kind (explicitly out of scope).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/core/permissions/permission_service.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';
import 'package:roadsense_logger/features/recording/pre_record_dialog.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';
import 'package:roadsense_logger/services/recording/recording_environment.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.controller,
    required this.permissions,
    required this.environment,
    this.settings = const SessionSettings(),
    this.onOpenSettings,
    this.onOpenHistory,
    this.loadLastConfig,
    this.saveLastConfig,
  });

  final RecordingController controller;

  /// Permission checks before recording (FR-080).
  final PermissionsGate permissions;

  /// Keep-awake / orientation-lock around recording (FR-005).
  final RecordingEnvironment environment;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareOnLaunch());
  }

  /// Asks for every permission up front (camera, location, notifications,
  /// and microphone when audio is enabled) so the first Record tap does not
  /// stop for prompts, then warms up the camera preview and GPS.
  Future<void> _prepareOnLaunch() async {
    await widget.permissions.ensurePermissions(
      audio: widget.settings.audioEnabled,
    );
    if (!mounted) return;
    await _prepareIdle();
  }

  /// Camera preview and GPS warm-up for the idle screen. Finalizing a
  /// session releases the camera, so this also runs after every stop.
  Future<void> _prepareIdle() async {
    await _preparePreview();
    if (!mounted) return;
    await widget.controller.prepareGps();
  }

  /// A finished (or failed) session must return to idle before the next
  /// recording can start; the state machine only allows idle -> preparing.
  void _returnToIdle() {
    final state = widget.controller.state;
    if (state == RecordingState.completed || state == RecordingState.error) {
      widget.controller.reset();
    }
  }

  @override
  void didUpdateWidget(RecordingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Settings load asynchronously and can change in the settings screen;
    // keep the preview camera in sync while idle.
    final idle = widget.controller.state == RecordingState.idle;
    if (idle &&
        !_videoConfig(
          oldWidget.settings,
        ).matches(_videoConfig(widget.settings))) {
      _preparePreview();
    }
  }

  static VideoConfig _videoConfig(SessionSettings settings) => VideoConfig(
    width: settings.videoWidth,
    height: settings.videoHeight,
    fps: settings.videoFps,
    audio: settings.audioEnabled,
  );

  Future<void> _preparePreview() async {
    try {
      await widget.controller.prepareCamera(_videoConfig(widget.settings));
    } on AppFailure {
      // Surfaced through the preview placeholder below.
    }
    if (mounted) setState(() {});
  }

  Future<void> _startRecording() async {
    // Covers sessions ended by an automatic interruption, which finalize
    // without going through _stopRecording.
    _returnToIdle();
    final granted = await widget.permissions.ensurePermissions(
      audio: widget.settings.audioEnabled,
    );
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera permission (and microphone, when audio is enabled) '
              'is required to record',
            ),
          ),
        );
      }
      return;
    }
    await widget.controller.prepareGps();
    final initial = _lastConfig ?? await widget.loadLastConfig?.call();
    if (!mounted) return;
    final selection = await showPreRecordDialog(context, initial: initial);
    if (selection == null || !mounted) return;
    // The dialog only collects per-session metadata; capture settings come
    // from the saved settings at the moment recording starts.
    final config = SessionConfig(
      vehicleType: selection.vehicleType,
      mountPosition: selection.mountPosition,
      notes: selection.notes,
      settings: widget.settings,
    );
    final gps = widget.controller.snapshot().gpsReport;
    if (gps.acceptedCount == 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No GPS fix yet'),
          content: Text(
            'No GPS fix has been received. Positions in this session may be '
            'missing.\n\n'
            '${gps.statusMessage ?? 'Go outdoors with a clear view of the sky '
                    'and wait for the GPS indicator to show a fix.'}'
            '\n\nRecord anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Record anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.start(config);
      _lastConfig = config;
      await widget.saveLastConfig?.call(config);
      await _enterRecordingEnvironment();
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

  /// Keep-awake/orientation lock failing must not abort a running session,
  /// but the user is told the screen may now sleep.
  Future<void> _enterRecordingEnvironment() async {
    try {
      await widget.environment.enterRecording();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Recording, but keep-awake/orientation lock failed: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _busy = true);
    try {
      try {
        await widget.controller.stop();
      } finally {
        await widget.environment.exitRecording();
      }
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
      _returnToIdle();
      if (mounted) {
        setState(() => _busy = false);
        await _prepareIdle();
      }
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
        return PopScope(
          canPop: !recording,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Stop the recording before leaving the app'),
                ),
              );
            }
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final bottomInset = MediaQuery.paddingOf(context).bottom;
                  final barHeight = _bottomBarHeight + bottomInset;
                  return Stack(
                    children: [
                      // Viewfinder sits directly on the black bar so the
                      // shutter straddles the viewfinder's bottom edge.
                      Positioned.fill(
                        bottom: barHeight,
                        child: _Preview(controller: widget.controller),
                      ),
                      Positioned.fill(
                        bottom: barHeight,
                        child: SafeArea(
                          bottom: false,
                          child: Column(
                            children: [
                              _TopBar(
                                data: data,
                                recording: recording,
                                onOpenHistory: widget.onOpenHistory,
                                onOpenSettings: widget.onOpenSettings,
                              ),
                              if (data.warnings.isNotEmpty)
                                _Warnings(warnings: data.warnings),
                              const Spacer(),
                              _StatusStrip(data: data),
                              // Keeps readouts clear of the shutter's top half.
                              const SizedBox(height: _shutterSize / 2 + 12),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: barHeight,
                        child: const ColoredBox(color: Colors.black),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        // Shutter centre on the viewfinder/bar boundary.
                        top:
                            constraints.maxHeight -
                            barHeight -
                            _shutterSize / 2,
                        child: Center(
                          child: _ShutterButton(
                            recording: recording,
                            busy: _busy,
                            onStart: _startRecording,
                            onStop: _stopRecording,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Overlay surfaces: near-opaque black with hairline borders and small
/// radii, so text stays crisp over any scene.
const _overlayColor = Color(0xB3000000);
const _hairline = BorderSide(color: Color(0x33FFFFFF), width: 0.5);
const _recordRed = Color(0xFFFF3B30);

/// Black control bar under the viewfinder (excluding the system inset).
const _bottomBarHeight = 72.0;

/// Outer diameter of the shutter ring.
const _shutterSize = 62.0;

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    Widget child;
    try {
      child = controller.buildPreview();
    } catch (error) {
      child = Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white54,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Camera preview unavailable\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    // The full frame is shown (never cropped) so what you see is exactly
    // what is recorded — important when aligning the mount.
    return ColoredBox(
      color: Colors.black,
      child: Align(alignment: Alignment.bottomCenter, child: child),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.data,
    required this.recording,
    required this.onOpenHistory,
    required this.onOpenSettings,
  });

  final RecordingSnapshot data;
  final bool recording;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'RoadSense Logger',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          _TimerPill(elapsedS: data.elapsedS, recording: recording),
          const SizedBox(width: 4),
          if (onOpenHistory != null)
            _OverlayIconButton(
              icon: Icons.video_library_outlined,
              tooltip: 'Sessions',
              onPressed: onOpenHistory!,
            ),
          if (onOpenSettings != null)
            _OverlayIconButton(
              icon: Icons.tune,
              tooltip: 'Settings',
              onPressed: onOpenSettings!,
            ),
        ],
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      color: Colors.white,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: _overlayColor),
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.elapsedS, required this.recording});

  final double elapsedS;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: recording ? _recordRed : _overlayColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recording) ...[
            const Icon(Icons.circle, size: 8, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            _formatDuration(elapsedS),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(
          color: Color(0xE6332200),
          border: Border(left: BorderSide(color: Color(0xFFFFB020), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final warning in warnings)
              Text(
                warning,
                style: const TextStyle(
                  color: Color(0xFFFFD580),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact live readouts over the bottom of the viewfinder.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.data});

  final RecordingSnapshot data;

  @override
  Widget build(BuildContext context) {
    final gps = data.gpsReport;
    final sensors = data.sensorReport;
    final speed = gps.lastSpeedMps;
    final fixAge = gps.lastFixAgeS;
    final accuracy = gps.lastFix?.accuracyM;
    final gpsStale = gps.isStale(5);

    String hz(double? rate) =>
        rate == null ? '—' : '${rate.toStringAsFixed(0)} Hz';
    String mag(double? value, String unit) =>
        value == null ? '—' : '${value.toStringAsFixed(2)} $unit';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: _overlayColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.fromBorderSide(_hairline),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runSpacing: 8,
        children: [
          _Metric(
            label: 'GPS',
            value: fixAge == null
                ? 'no fix'
                : accuracy == null
                ? '${fixAge.toStringAsFixed(1)} s'
                : '±${accuracy.toStringAsFixed(0)} m',
            indicator: fixAge == null
                ? _Indicator.bad
                : gpsStale
                ? _Indicator.warn
                : _Indicator.good,
          ),
          _Metric(
            label: 'Speed',
            value: speed == null
                ? '—'
                : '${(speed * 3.6).toStringAsFixed(1)} km/h',
            dimmed: gpsStale,
          ),
          _Metric(label: 'ACC rate', value: hz(sensors.accLiveRateHz)),
          _Metric(label: 'GYRO rate', value: hz(sensors.gyroLiveRateHz)),
          _Metric(label: 'ACC', value: mag(sensors.accLastMagnitude, 'm/s²')),
          _Metric(
            label: 'GYRO',
            value: mag(sensors.gyroLastMagnitude, 'rad/s'),
          ),
          _Metric(
            label: 'Storage',
            value:
                '${(data.freeStorageBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB',
          ),
        ],
      ),
    );
  }
}

enum _Indicator {
  good(Color(0xFF34C759)),
  warn(Color(0xFFFFB020)),
  bad(_recordRed);

  const _Indicator(this.color);

  final Color color;
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.indicator,
    this.dimmed = false,
  });

  final String label;
  final String value;
  final _Indicator? indicator;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (indicator != null) ...[
                Icon(Icons.circle, size: 7, color: indicator!.color),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dimmed ? Colors.white38 : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera-style shutter: white ring with a red dot that morphs into a
/// rounded square while recording. The label sits below, on the black bar.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
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
    final onTap = busy ? null : (recording ? onStop : onStart);
    final innerSize = recording ? 24.0 : 48.0;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _shutterSize,
              height: _shutterSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x66000000),
                border: Border.all(color: Colors.white, width: 3.5),
              ),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: innerSize,
                      height: innerSize,
                      decoration: BoxDecoration(
                        color: _recordRed,
                        borderRadius: BorderRadius.circular(
                          recording ? 5 : innerSize / 2,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              recording ? 'Stop' : 'Record',
              style: TextStyle(
                color: onTap == null ? Colors.white38 : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
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
