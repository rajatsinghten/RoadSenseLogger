/// Permission handling (FR-080): only the permissions the workflow needs,
/// with rationale surfaced in the UI and safe denial behavior.
library;

import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/services/native/native_control.dart';

/// UI seam for permission checks (faked in widget tests).
abstract interface class PermissionsGate {
  /// Ensures the permissions required to record. Returns false when a
  /// required permission is missing after the request.
  Future<bool> ensurePermissions({required bool audio});
}

class PermissionService implements PermissionsGate {
  PermissionService(this._native);

  final NativeControl _native;

  /// Camera is always required; audio only when audio recording is enabled;
  /// location enables GPS (not fatal on its own — recording can proceed
  /// without GPS after an explicit user decision, FR-033).
  List<String> requiredPermissions({required bool audio}) => [
    'camera',
    'fineLocation',
    'coarseLocation',
    if (audio) 'recordAudio',
  ];

  @override
  Future<bool> ensurePermissions({required bool audio}) async {
    final names = requiredPermissions(audio: audio);
    final status = await _native.checkPermissions(names);
    if (status['camera'] == true) {
      return true;
    }
    final requested = await _native.requestPermissions(names);
    return requested['camera'] == true;
  }

  /// Throws when the camera permission is missing at recording start.
  Future<void> requireCamera() async {
    final status = await _native.checkPermissions(['camera']);
    if (status['camera'] != true) {
      throw AppFailure('Camera permission is required to record video');
    }
  }
}
