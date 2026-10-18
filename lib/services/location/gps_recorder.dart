/// GPS intake service (FR-030..033): forwards accepted fixes for persistence
/// and tracks availability, staleness and outages as diagnostics.
library;

import 'dart:async';

import 'package:roadsense_logger/domain/models/diagnostic_event.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/location/location_source.dart';

/// Immutable GPS status used for live UI and metadata.
class GpsReport {
  const GpsReport({
    required this.acceptedCount,
    required this.rejectedCount,
    required this.lastFix,
    required this.lastFixAgeS,
    required this.outageCount,
  });

  final int acceptedCount;
  final int rejectedCount;

  /// Latest accepted fix, or null when no fix has arrived yet.
  final GpsFix? lastFix;

  /// Seconds between the last fix and now (monotonic), or null without a fix.
  final double? lastFixAgeS;

  final int outageCount;

  /// Last reported speed (m/s), or null when unavailable (never fabricated).
  double? get lastSpeedMps => lastFix?.speedMps;

  /// True when the last fix is older than [maxAgeS].
  bool isStale(double maxAgeS) => lastFixAgeS == null || lastFixAgeS! > maxAgeS;
}

class GpsRecorder {
  GpsRecorder({
    required LocationSource source,
    required void Function(GpsFix fix) onFix,
    required void Function(DiagnosticEvent event) onDiagnostic,
    required int Function() nowNs,
    this.outageThresholdS = 30,
    this.staleAfterS = 10,
  }) : _source = source,
       _onFix = onFix,
       _onDiagnostic = onDiagnostic,
       _nowNs = nowNs;

  final LocationSource _source;
  final void Function(GpsFix fix) _onFix;
  final void Function(DiagnosticEvent event) _onDiagnostic;
  final int Function() _nowNs;

  /// No accepted fix for this long is reported as a `gps_outage`.
  final double outageThresholdS;

  /// Age above which [checkStaleness] reports a `gps_stale` diagnostic.
  final double staleAfterS;

  StreamSubscription<NativeGpsEvent>? _subscription;
  int _acceptedCount = 0;
  int _rejectedCount = 0;
  int _outageCount = 0;
  GpsFix? _lastFix;
  int? _lastFixNs;
  bool _staleReported = false;

  Future<void> start({required int intervalMs}) async {
    await _source.startGps(intervalMs: intervalMs);
    _subscription = _source.gpsEvents.listen(_onEvent);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _source.stopGps();
  }

  void _onEvent(NativeGpsEvent event) {
    if (!event.accepted || event.fix == null) {
      _rejectedCount++;
      _onDiagnostic(
        DiagnosticEvent(
          timestampNs: _nowNs(),
          type: 'gps_rejected',
          message: 'GPS fix rejected: ${event.reason}',
          context: {'reason': event.reason},
        ),
      );
      return;
    }

    final fix = event.fix!;
    if (_lastFixNs != null) {
      final silenceS = (fix.timestampNs - _lastFixNs!) / 1e9;
      if (silenceS > outageThresholdS) {
        _outageCount++;
        _onDiagnostic(
          DiagnosticEvent(
            timestampNs: fix.timestampNs,
            type: 'gps_outage',
            message: 'GPS outage of ${silenceS.toStringAsFixed(1)} s',
            context: {'silence_s': silenceS},
          ),
        );
      }
    }
    _acceptedCount++;
    _lastFix = fix;
    _lastFixNs = fix.timestampNs;
    _staleReported = false;
    _onFix(fix);
  }

  /// Called from the recording tick: reports the first transition into a
  /// stale-fix state (no fixes for [staleAfterS] seconds).
  void checkStaleness() {
    final lastNs = _lastFixNs;
    if (lastNs == null || _staleReported) return;
    final ageS = (_nowNs() - lastNs) / 1e9;
    if (ageS > staleAfterS) {
      _staleReported = true;
      _onDiagnostic(
        DiagnosticEvent(
          timestampNs: _nowNs(),
          type: 'gps_stale',
          message: 'Last GPS fix is ${ageS.toStringAsFixed(1)} s old',
          context: {'age_s': ageS},
        ),
      );
    }
  }

  GpsReport report() {
    final lastNs = _lastFixNs;
    final ageS = lastNs == null ? null : (_nowNs() - lastNs) / 1e9;
    return GpsReport(
      acceptedCount: _acceptedCount,
      rejectedCount: _rejectedCount,
      lastFix: _lastFix,
      lastFixAgeS: ageS,
      outageCount: _outageCount,
    );
  }
}
